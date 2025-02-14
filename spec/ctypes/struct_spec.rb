# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe Struct do
    describe ".layout" do
      it "will pass provided block to new Struct::Builder instance" do
        layout_block = proc { attribute :a, uint32 }
        builder = described_class::Builder.new(&layout_block)
        expect(builder).to receive(:instance_eval) do |&block|
          expect(block).to be(layout_block)
        end
        expect(described_class::Builder).to receive(:new) do |&block|
          builder
        end
        Class.new(described_class).layout(&layout_block)
      end

      context "called multiple times" do
        let(:struct) do
          st = Class.new(described_class)
          st.layout do
            attribute :resize, enum(uint8, %i[a r s t])
            attribute :remove, uint8
            attribute :keep, uint8
          end

          # lookup an offset to ensure we also clear those on reload
          expect(st.offsetof(:keep)).to eq(2)

          st.layout do
            attribute :resize, enum(uint32, %i[a r s t])
            attribute :keep, uint8
            attribute :add, uint8
          end
          st
        end

        it "will only have attributes defined in last call" do
          expect(struct.fields).to eq([:resize, :keep, :add])
        end

        it "will only have accessors defined in last call" do
          instance = struct.new
          aggregate_failures do
            expect(instance).to respond_to(:resize)
            expect(instance).to respond_to(:keep)
            expect(instance).to respond_to(:add)
            expect(instance).to_not respond_to(:remove)
          end
        end

        it "will update the size" do
          expect(struct.size).to eq(6)
        end

        it "will update the field offsets" do
          aggregate_failures do
            expect(struct.offsetof(:resize)).to eq(0)
            expect(struct.offsetof(:keep)).to eq(4)
            expect(struct.offsetof(:add)).to eq(5)
          end
        end
      end

      context "when called within CTypes.using_type_lookup()" do
        it " will call the type lookup method for unknown types" do
          lookup = ->(n) {}
          expect(lookup).to receive(:call).with(:custom_type) { Helpers.uint32 }
          struct = Class.new(described_class)
          CTypes.using_type_lookup(lookup) do
            struct.layout do
              attribute :id, custom_type
            end
          end
          expected = Helpers.struct do
            attribute :id, uint32
          end
          expect(struct).to eq(expected)
        end
      end
    end

    [{
      layout: proc do
        endian :big
        attribute :id, uint8
        attribute :val, uint32
      end,
      endian: :big,
      pack: {
        {} => "\x00\x00\x00\x00\x00",
        {id: 1} => "\x01\x00\x00\x00\x00",
        {id: 1, val: 0xdeadbeef} => "\x01\xde\xad\xbe\xef",
        {val: 0xdeadbeef, id: 1} => "\x01\xde\xad\xbe\xef"
      },
      unpack: {
        "\x00\x00\x00\x00\x00" => [{id: 0, val: 0}, ""],
        "\x01\x00\x00\x00\x00" => [{id: 1, val: 0}, ""],
        "\x01\xde\xad\xbe\xef" => [{id: 1, val: 0xdeadbeef}, ""]
      },
      size: 5,
      greedy: false,
      export: true
    },
      # little endian check
      {
        layout: proc do
          endian :little
          attribute :id, uint8
          attribute :val, uint32
        end,
        endian: :little,
        pack: {
          {val: 0xdeadbeef, id: 1} => "\x01\xef\xbe\xad\xde"
        },
        unpack: {
          "\x01\xef\xbe\xad\xde" => [{id: 1, val: 0xdeadbeef}, ""]
        },
        size: 5,
        greedy: false,
        export: true
      },
      # mixed endian struct
      {
        layout: proc do
          endian :big
          attribute :b, uint32
          attribute :l, uint32.with_endian(:little)
        end,
        pack: {
          {b: 0xdeadbeef, l: 0xdeadbeef} => "\xde\xad\xbe\xef\xef\xbe\xad\xde"
        },
        unpack: {
          "\xde\xad\xbe\xef\xef\xbe\xad\xde" =>
            [{b: 0xdeadbeef, l: 0xdeadbeef}, ""]
        },
        size: 8,
        greedy: false,
        export: true
      },
      # fixed length string
      {
        layout: proc do
          attribute :len, uint8
          attribute :path, string(32)
        end,
        pack: {{} => "\0" * 33},
        unpack: {
          "\0" * 33 => [{len: 0, path: ""}, ""],
          ("\0" + "X" * 64) => [{len: 0, path: "X" * 32}, "X" * 32]
        },
        size: 33,
        greedy: false,
        export: true
      },
      # variable (greedy) length string
      {
        layout: proc do
          attribute :id, uint8
          attribute :str, string
        end,
        pack: {
          {} => "\0",
          {str: "hello"} => "\0hello"
        },
        unpack: {
          "\0hello" => [{id: 0, str: "hello"}, ""],
          "\0helloXXXX\0" => [{id: 0, str: "helloXXXX"}, ""]
        },
        size: 1,
        greedy: true,
        export: true
      },
      # terminated string
      {
        layout: proc do
          attribute :id, uint8
          attribute :str, string.terminated("XXX")
        end,
        pack: {
          {} => "\0XXX",
          {str: "hello"} => "\0helloXXX"
        },
        unpack: {
          "\0helloXXX" => [{id: 0, str: "hello"}, ""],
          "\0helloXXXextra" => [{id: 0, str: "hello"}, "extra"]
        },
        greedy: false,
        size: 4
      },
      # TLV with variable length value
      {
        layout: proc do
          attribute :type, uint8
          attribute :len, uint8
          attribute :value, string
          size { |s| offsetof(:value) + s[:len] }
        end,
        # silently truncate value when too long?  can we detect its too long?
        pack: {
          {type: 1, len: 6, value: "abcdef"} => "\1\6abcdef",
          {type: 1, len: 6, value: "abcdefXXXX"} => "\1\6abcdef",
          {type: 1, len: 6, value: "abc"} => "\1\6abc\0\0\0"
        },
        unpack: {
          "\1\6abcdef" => [{type: 1, len: 6, value: "abcdef"}, ""],
          "\1\6abcdefXXXX" => [{type: 1, len: 6, value: "abcdef"}, "XXXX"],
          "\1\6abc" => [MissingBytesError, /missing 3/]
        },
        size: 2,
        greedy: false
      },
      # nested struct
      {
        layout: proc do
          attribute :id, uint8
          attribute :inner, struct(a: uint8)
        end,
        pack: {
          {} => "\0\0",
          {inner: {a: 1}} => "\0\1"
        },
        unpack: {
          "\0\0" => [{id: 0, inner: {a: 0}}, ""],
          "\0\xffXXX" => [{id: 0, inner: {a: 255}}, "XXX"]
        },
        size: 2,
        greedy: false,
        export: true
      },
      # union inside a struct
      {
        layout: proc do
          attribute :id, uint8
          attribute :value, union(byte: uint8, word: uint32)
        end,
        pack: {
          {} => "\0\0\0\0\0",
          {value: {byte: 1}} => "\0\1\0\0\0",
          {value: {word: 0xfeed}} => "\0\xed\xfe\0\0",
          {value: {byte: 1, word: 0xfeed}} => [Error, /conflicting values/]
        },
        unpack: {
          "\0\0\0\0\0" => [{id: 0, value: {byte: 0}}, ""],
          "\0\0\0\0\0XXX" => [{id: 0, value: {byte: 0}}, "XXX"],
          "\0\xed\xfe\0\0" => [{id: 0, value: {byte: 0xed}}, ""]
        },
        size: 5,
        greedy: false,
        export: true
      },
      # struct with an enum field
      {
        layout: proc do
          attribute :id, uint8
          attribute :state, enum(uint8, %i[a b c d])
        end,
        size: 2,
        greedy: false,
        export: true,
        pack: {
          {} => "\0\0",
          {id: 0, state: :unknown_ff} =>
              [Dry::Types::SchemaError, /unknown_ff/]
        },
        unpack: {
          "\0\0X" => [{id: 0, state: :a}, "X"],
          "\0\1X" => [{id: 0, state: :b}, "X"],
          "\0\xfeX" => [Dry::Types::ConstraintError],
          "\0" => [MissingBytesError, /missing 1 bytes/]
        }
      },
      # struct with a permissive enum field
      {
        layout: proc do
          attribute :id, uint8
          attribute :state, enum(uint8, %i[a b c d]).permissive
        end,
        size: 2,
        greedy: false,
        export: true,
        pack: {
          {} => "\0\0",
          # XXX fails due to verification happening at the struct layer
          {id: 0, state: :unknown_ff} => "\0\xff"
        },
        unpack: {
          "\0\0X" => [{id: 0, state: :a}, "X"],
          "\0\1X" => [{id: 0, state: :b}, "X"],
          "\0\xfeX" => [{id: 0, state: :unknown_fe}, "X"],
          "\0" => [MissingBytesError, /missing 1 bytes/]
        }
      },
      # struct with a bitmap field
      {
        layout: proc do
          attribute :id, uint8
          attribute :flags, bitmap(uint8, %i[a b c d])
        end,
        size: 2,
        greedy: false,
        pack: {
          {} => "\0\0",
          {id: 1} => "\1\0",
          {flags: []} => "\0\0",
          {flags: [:a]} => "\0\1",
          {id: 1, flags: [:b, :c]} => "\1\6",
          {id: 1, flags: [:bit_7]} => [Dry::Types::SchemaError, /bit_7/]
        },
        unpack: {
          "\0\0X" => [{id: 0, flags: []}, "X"],
          "\0\1X" => [{id: 0, flags: [:a]}, "X"],
          "\0\6X" => [{id: 0, flags: %i[b c]}, "X"],
          "\0\8X" => [Dry::Types::ConstraintError],
          "\0" => [MissingBytesError, /missing 1 bytes/]
        }
      },
      # struct with a permissive bitmap field
      {
        layout: proc do
          attribute :id, uint8
          attribute :flags, bitmap(uint8, %i[a b c d]).permissive
        end,
        size: 2,
        greedy: false,
        pack: {
          {} => "\0\0",
          {id: 1} => "\1\0",
          {flags: []} => "\0\0",
          {flags: [:a]} => "\0\1",
          {id: 1, flags: [:b, :c]} => "\1\6",
          {id: 1, flags: [:bit_7]} => "\1\x80"
        },
        unpack: {
          "\0\0X" => [{id: 0, flags: []}, "X"],
          "\0\1X" => [{id: 0, flags: [:a]}, "X"],
          "\0\6X" => [{id: 0, flags: %i[b c]}, "X"],
          "\0\8X" => [{id: 0, flags: [:d, :bit_4, :bit_5]}, "X"],
          "\0" => [MissingBytesError, /missing 1 bytes/]
        }
      },
      # struct that's more of a record with multiple variable-length fields
      {
        layout: proc do
          attribute :a, string.terminated("A")
          attribute :b, string.terminated("B")
        end,
        size: 2,
        greedy: false,
        pack: {
          {} => "AB",
          {a: "hello"} => "helloAB",
          {a: "hello", b: "world"} => "helloAworldB"
        },
        unpack: {
          "ABX" => [{a: "", b: ""}, "X"],
          "helloAworldBX" => [{a: "hello", b: "world"}, "X"],
          "A" => [TerminatorNotFoundError]
        }
      },
      # struct with unnamed union
      {
        layout: proc do
          attribute union(a: uint8, b: int8)
          attribute :c, uint8
        end,
        size: 2,
        greedy: false,
        export: true,
        pack: {
          {} => "\0" * 2,
          {a: 0xff} => "\xff\0",
          {b: -1} => "\xff\0",
          {b: -1, c: 0xff} => "\xff\xff",
          {a: 0xff, b: -1} => [Error, /conflicting values/]
        },
        unpack: {
          "\0\1X" => [{a: 0, b: 0, c: 1}, "X"],
          "\xff\1X" => [{a: 255, b: -1, c: 1}, "X"]
        }
      },
      # struct with unnamed struct
      {
        layout: proc do
          attribute struct(a: uint8, b: int8)
          attribute :c, uint8
        end,
        size: 3,
        greedy: false,
        export: true,
        pack: {
          {} => "\0" * 3,
          {a: 0xff} => "\xff\0\0",
          {b: -1} => "\0\xff\0",
          {c: 255} => "\0\0\xff",
          {b: -1, c: 0xff} => "\0\xff\xff",
          {a: 1, b: 2, c: 3} => "\1\2\3"
        },
        unpack: {
          "\1\2\3X" => [{a: 1, b: 2, c: 3}, "X"],
          "\xff\xff\3X" => [{a: 255, b: -1, c: 3}, "X"]
        }
      },
      # struct with a bitfield
      {
        layout: proc do
          attribute bitfield {
            unsigned :a
            unsigned :b
          }
          attribute :c, uint8
        end,
        size: 2,
        greedy: false,
        export: true,
        pack: {
          {} => "\0" * 2,
          {a: 1} => bitstr("00000001") + "\0",
          {b: 1} => bitstr("00000010") + "\0",
          {c: 0xff} => "\0\xff",
          {a: 1, b: 1, c: 0xff} => bitstr("00000011") + "\xff"
        },
        unpack: {
          bitstr("00000011") + "\xffX" => [{a: 1, b: 1, c: 0xff}, "X"]
        }
      },
      # empty struct because for some reason it has happened
      {
        layout: proc {},
        size: 0,
        greedy: false,
        export: true,
        pack: {
          {} => ""
        },
        unpack: {
          "blah" => [{}, "blah"]
        }
      },
      # struct with padding
      {
        layout: proc do
          attribute :a, uint8
          pad 2
          attribute :b, uint8
        end,
        size: 4,
        greedy: false,
        export: true,
        pack: {
          {} => "\0\0\0\0",
          {a: 1, b: 2} => "\1\0\0\2",
          {a: 0xff, b: 2} => "\xff\0\0\2"
        },
        unpack: {
          "\1YY\2X" => [{a: 1, b: 2}, "X"]
        }
      }].each do |ctx|
      context "layout %s" % ctx[:layout].source do
        let(:struct) do
          Class.new(described_class) { layout(&ctx[:layout]) }
        end

        it ".size # => %d" % ctx[:size] do
          expect(struct.size).to eq(ctx[:size])
        end

        it "greedy? # => %p" % ctx[:greedy] do
          expect(struct.greedy?).to eq(ctx[:greedy])
        end

        describe ".pack" do
          ctx[:pack].each_pair do |input, output|
            if output.is_a?(::String)
              it "pack(%p) # => %p" % [input, output] do
                expect(struct.pack(input)).to eq(output)
              end
            else
              it "pack(%p) will raise error %p" % [input, output] do
                expect { struct.pack(input) }.to raise_error(*output)
              end
            end
          end
        end

        describe ".unpack_one" do
          ctx[:unpack].each_pair do |input, output|
            if output.first.is_a?(Hash)
              it "unpack(%p) # => %p" % [input, output] do
                result = struct.unpack_one(input)
                expect(result).to eq(output)
              end
              it "unpacked instance has @endian == %p" % ctx[:endian], if: ctx[:endian] do
                result, _ = struct.unpack_one(input)
                expect(result.instance_variable_get(:@endian)).to eq(ctx[:endian])
              end
            else
              it "unpack(%p) will raise error %p" % [input, output] do
                expect { struct.unpack_one(input) }.to raise_error(*output)
              end
            end
          end
        end

        describe ".export_type" do
          it "will output code to create the type", if: ctx[:export] do
            buf = "extend CTypes::Helpers\n"
            exporter = Exporter.new(buf)
            orig = struct
            orig.export_type(exporter)
            puts(buf)
            exported = eval(buf)
            expect(exported).to eq(orig)
          end
        end
      end
    end

    describe ".read" do
      context "a variable-length struct" do
        it "will raise an error" do
          t = Class.new(described_class) do
            layout do
              attribute :id, uint8
              attribute :str, string
            end
          end
          io = StringIO.new("\x5hello")
          expect { t.read(io) }
            .to raise_error(NotImplementedError, /variable-length/)
        end
      end

      context "a fixed-length struct" do
        let(:struct) do
          Class.new(described_class) do
            layout do
              attribute :key, uint8
              attribute :value, uint8
            end
          end
        end

        let(:io) do
          StringIO.new("\x0\x1\x2\x3")
        end

        it "will unpack a fixed-length struct" do
          value = struct.read(io)
          expect(value).to have_attributes(key: 0, value: 1)
        end

        it "will move io cursor to the byte after the struct data" do
          struct.read(io)
          expect(io.pos).to eq(struct.size)
        end
      end
    end

    describe ".pread" do
      context "a variable-length struct" do
        it "will raise an error" do
          t = Class.new(described_class) do
            layout do
              attribute :id, uint8
              attribute :str, string
            end
          end
          io = StringIO.new("\x5hello")
          expect { t.pread(io, 0) }
            .to raise_error(NotImplementedError, /variable-length/)
        end
      end

      context "a fixed-length struct" do
        let(:struct) do
          Class.new(described_class) do
            layout do
              attribute :key, uint8
              attribute :value, uint8
            end
          end
        end

        let(:io) do
          StringIO.new("\x0\x1\x2\x3")
        end

        it "will unpack a fixed-length struct" do
          expect(io).to receive(:pread).with(2, 0).and_return("\x0\x1")
          value = struct.pread(io, 0)
          expect(value).to have_attributes(key: 0, value: 1)
        end

        it "will read structure at specific offset" do
          expect(io).to receive(:pread).with(2, 2).and_return("\x2\x3")
          value = struct.pread(io, 2)
          expect(value).to have_attributes(key: 2, value: 3)
        end
      end
    end

    describe ".unpack_all" do
      let(:struct) do
        Class.new(described_class) do
          layout do
            attribute :key, uint8
            attribute :value, uint8
          end
        end
      end

      it "will raise MissingBytesError for an incomplete buffer" do
        expect { struct.unpack_all("\x0\x1\x2") }
          .to raise_error(MissingBytesError)
      end

      it "will return unpacked types for a complete buffer" do
        expect(struct.unpack_all("\x0\x1\x2\x3"))
          .to contain_exactly(
            {key: 0, value: 1},
            {key: 2, value: 3}
          )
      end
    end
  end
end
