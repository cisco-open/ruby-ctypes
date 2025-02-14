# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe Union do
    describe ".layout" do
      it "will pass provided block to new Union::Builder instance" do
        layout_block = proc { member :a, uint32 }
        builder = described_class::Builder.new(&layout_block)
        expect(described_class::Builder).to receive(:new) do |&block|
          expect(block).to be(layout_block)
          builder
        end
        Class.new(described_class).layout(&layout_block)
      end

      context "called multiple times" do
        let(:union) do
          u = Class.new(described_class)
          u.layout do
            member :remove, uint8
            member :keep, uint8
          end
          u.layout do
            member :keep, uint8
            member :add, uint8
          end
          u
        end

        it "will only have members defined in last call" do
          expect(union.fields).to eq([:keep, :add])
        end

        it "will only have accessors defined in last call" do
          instance = union.new
          aggregate_failures do
            expect(instance).to respond_to(:keep)
            expect(instance).to respond_to(:add)
            expect(instance).to_not respond_to(:remove)
          end
        end
      end

      context "when called within CTypes.using_type_lookup()" do
        it " will call the type lookup method for unknown types" do
          lookup = ->(n) {}
          expect(lookup).to receive(:call).with(:custom_type) { Helpers.uint32 }
          type = Class.new(described_class)
          CTypes.using_type_lookup(lookup) do
            type.layout do
              member :id, custom_type
            end
          end
          expected = Helpers.union do
            member :id, uint32
          end
          expect(type).to eq(expected)
        end
      end
    end

    [
      # fixed-size union
      {
        layout: proc do
          endian :big
          member :char, uint8
          member :word, uint32
        end,
        size: 4,
        export: true,
        greedy: false,
        pack: {
          {} => "\0\0\0\0",
          {char: 0xff} => "\xff\0\0\0",
          {word: 0xdeadbeef} => "\xde\xad\xbe\xef",
          {char: 0, word: 0} => [Error, /conflicting values/]
        },
        unpack: {
          "" => [MissingBytesError, /missing 4/],
          "\0" => [MissingBytesError, /missing 3/],
          "\0\0\0\0" => [{char: 0, word: 0}, ""],
          "\0\0\0\xff" => [{char: 0, word: 255}, ""],
          "\0\0\0\xffXXX" => [{char: 0, word: 255}, "XXX"]
        }
      },
      # variable-length with greedy member
      {
        layout: proc do
          endian :big
          member :word, uint32
          member :str, string
        end,
        size: 4,
        export: true,
        greedy: true,
        pack: {
          {} => "\0\0\0\0",
          {str: "hello world"} => "hello world",
          {word: 0xdeadbeef} => "\xde\xad\xbe\xef"
        },
        unpack: {
          "" => [MissingBytesError, /missing 4/],
          "\0" => [MissingBytesError, /missing 3/],
          "hello world" => [{str: "hello world"}, ""],
          "hello world\0\0\0" => [{str: "hello world"}, ""],
          "\xde\xad\xbe\xefXXXX" => [{word: 0xdeadbeef}, ""]
        }
      },
      # variable-length with non-greedy member
      {
        layout: proc do
          endian :big
          member :word, uint32
          member :str, string.terminated("\0")
        end,
        size: 4,
        greedy: false,
        pack: {
          {} => "\0\0\0\0",
          {str: "hello world"} => "hello world\0",
          {word: 0xdeadbeef} => "\xde\xad\xbe\xef"
        },
        unpack: {
          "" => [MissingBytesError, /missing 4/],
          "\0" => [MissingBytesError, /missing 3/],
          "hello world\0" => [{str: "hello world"}, ""],
          # it is impossible to know which member of the union will be needed,
          # so Union.unpack_one is unable to return the "unused" remainder of
          # the input buffer because it could be either "XXX" or "o world...".
          "hello world\0XXX" => [{str: "hello world"}, ""],
          "\xde\xad\xbe\xef" => [{word: 0xdeadbeef}, ""]
        }
      },
      # nested struct in union
      {
        layout: proc do
          member :struct, struct(a: int8, b: int8, c: int8, d: int8)
          member :word, uint32
        end,
        size: 4,
        greedy: false,
        export: true,
        pack: {
          {} => "\0\0\0\0",
          {struct: {}} => "\0\0\0\0",
          {struct: {b: 1}} => "\0\1\0\0"
        },
        unpack: {
          "" => [MissingBytesError, /missing 4/],
          "\0" => [MissingBytesError, /missing 3/]
        }
      },
      # nested dynamic-sized struct in union
      {
        layout: proc do
          member :struct, struct(a: string.terminated, b: string.terminated)
          member :word, uint32
        end,
        size: 4,
        greedy: false,
        pack: {
          {} => "\0\0\0\0",
          {struct: {}} => "\0\0\0\0",
          {struct: {a: "A", b: ""}} => "A\0\0\0",
          {struct: {b: "hello"}} => "\0hello\0",
          {struct: {a: "world", b: "hello"}} => "world\0hello\0"
        },
        unpack: {
          "" => [MissingBytesError, /missing 4/],
          "\0" => [MissingBytesError, /missing 3/],
          # NOTE: as a union cannot know which member the union should
          # represent, a union containing a dynamically-sized member will be
          # greedy
          "hello\0world\0X" => [{struct: {a: "hello", b: "world"}}, ""]
        }
      },
      # dynamic-size union
      {
        layout: proc do
          member :len, uint8
          member :struct, struct(len: uint8, buf: string)
          size { |u| u[:len] + sizeof(:len) }
        end,
        greedy: false,
        pack: {
          {} => "\0",
          {len: 0} => "\0",
          {struct: {len: 0}} => "\0",
          {len: 5} => "\5\0\0\0\0\0",
          {struct: {len: 5, buf: "hello world"}} => "\5hello"
        },
        unpack: {
          "" => [MissingBytesError, /missing 1/],
          "\0" => [{len: 0}, ""],
          "\0XXX" => [{len: 0}, "XXX"],
          "\5hello world" => [{struct: {len: 5, buf: "hello"}}, " world"]
        }
      },
      # union of zero-sized structs; yes, it happened
      {
        layout: proc do
          member :a, struct {}
          member :b, struct {}
        end,
        greedy: false,
        export: true,
        pack: {
          {} => ""
        },
        unpack: {
          "" => [{a: {}}, ""],
          "X" => [{b: {}}, "X"]
        }
      },
      # unnamed field within a union
      {
        layout: proc do
          member bitfield {
                   unsigned :a
                   unsigned :b
                 }
          member :c, uint16
        end,
        greedy: false,
        export: true,
        pack: {
          {} => "\0\0",
          {a: 1} => "\1\0",
          {b: 1} => "\2\0",
          {a: 1, b: 1} => "\3\0"
        },
        unpack: {
          "\0\0X" => [{a: 0, b: 0}, "X"],
          "\1\0X" => [{a: 1, b: 0}, "X"],
          "\2\0X" => [{a: 0, b: 1}, "X"]
        }
      }
    ].each do |ctx|
      context "layout %s" % ctx[:layout].source do
        let(:union) do
          u = Class.new(described_class)
          u.layout(&ctx[:layout])
          u
        end

        if ctx.has_key?(:size)
          it ".size # => %d" % ctx[:size] do
            expect(union.size).to eq(ctx[:size])
          end
        end

        it ".greedy? # => %p" % ctx[:greedy] do
          expect(union.greedy?).to eq(ctx[:greedy])
        end

        describe ".pack" do
          ctx[:pack].each do |input, output|
            if output.is_a?(::String)
              it ".pack(%p) # => %p" % [input, output] do
                expect(union.pack(input)).to eq(output)
              end
            else
              it ".pack(%p) will raise %p" % [input, output] do
                expect { union.pack(input) }.to raise_error(*output)
              end
            end
          end
        end

        describe ".unpack_one" do
          ctx[:unpack].each_pair do |input, output|
            if output.first.is_a?(Hash)
              it "unpack_one(%p) # => %p" % [input, output] do
                result, rest = union.unpack_one(input)
                aggregate_failures do
                  expect(result).to have_attributes(**output[0])
                  expect(rest).to eq(output[1])
                end
              end
            else
              it "unpack_one(%p) will raise error %p" % [input, output] do
                expect { union.unpack_one(input) }.to raise_error(*output)
              end
            end
          end
        end

        describe ".export_type" do
          it "will output code to create the type", if: ctx[:export] do
            buf = "extend CTypes::Helpers\n"
            exporter = Exporter.new(buf)
            orig = union
            orig.export_type(exporter)
            puts buf
            exported = eval(buf)
            expect(exported).to eq(orig)
          end
        end
      end
    end

    let(:union) do
      Class.new(Union) do
        layout do
          member :int, int32
          member :str, string
        end
      end
    end

    describe "#to_binstr" do
      context "before any member is accessed" do
        it "will not call Union.pack" do
          expect(union).to_not receive(:pack)
          u = union.new(buf: "data", endian: :big)
          u.to_binstr
        end
        it "will return the buf passed to the initializer" do
          u = union.new(buf: "passed", endian: :big)
          expect(u.to_binstr).to eq("passed")
        end
      end
      context "after a member is changed" do
        it "will pack the update value" do
          u = union.new(buf: "failed", endian: :big)
          u.str = "passed"
          expect(u.to_binstr).to eq("passed")
        end
      end
    end

    describe "#[]" do
      it "will raise UnknownMemberError for an unknown member" do
        expect { union.new[:unknown_member] }
          .to raise_error(UnknownMemberError)
      end
      context "with a valid member name" do
        it "will return the member value" do
          expect(union.new[:int]).to eq(0)
        end

        it "will update the active field" do
          u = union.new
          expect(u).to receive(:active_field).with(:str).and_return({})
          u[:str]
        end
      end
    end

    describe "#[]=" do
      it "will raise UnknownMemberError for an unknown member" do
        expect { union.new[:unknown_member] = 3 }
          .to raise_error(UnknownMemberError)
      end
      context "with a valid member name" do
        it "will set the member value" do
          u = union.new
          u[:int] = 0xdeadbeef
          expect(u[:int]).to eq(0xdeadbeef)
        end

        it "will update the active field" do
          u = union.new
          expect(u).to receive(:active_field).with(:str).and_return({})
          u[:str] = "xxx"
        end
      end
    end

    describe "#apply_changes!" do
      it "with no changes will not call pack" do
        expect(union).to_not receive(:pack)
        u = union.new
        u.send(:apply_changes!)
      end

      it "with a read of a non-modifyable type it will not call pack" do
        expect(union).to_not receive(:pack)
        u = union.new
        u.int
        u.send(:apply_changes!)
      end

      it "with a read of a modifyable type it will call pack" do
        expect(union).to receive(:pack)
        u = union.new
        u.str
        u.send(:apply_changes!)
      end

      it "with a set of a field it will call pack" do
        expect(union).to receive(:pack).and_return("passed")
        u = union.new
        u.int = 5
        u.send(:apply_changes!)
        expect(u.instance_variable_get(:@buf)).to eq("passed")
      end
    end

    describe "common usage" do
      it "will apply any pending changes when switching active member" do
        t = CTypes::Helpers.union do
          endian :big
          member :u32, uint32
          member :str, string
        end
        u = t.new
        u.u32 = 0x74657374
        expect(u.str).to eq("test")
      end
    end

    describe "union.with_endian().unpack()" do
      it "will set same endian for active field" do
        s = Helpers.struct do
          attribute :id, uint32
        end
        u = Helpers.union do
          member :struct, s
          member :string, string(11)
        end
        v = u.with_endian(:big).unpack("hello world")
        expect(v.struct.instance_variable_get(:@endian)).to eq(:big)
      end
    end

    describe "regression: #to_h with Array member" do
      it "will not call to_h on the inner Array" do
        u = Helpers.union do
          member :array, array(uint8, 2)
        end
        v = u.unpack("\x01\x02")
        expect(v.to_h).to eq({array: [1, 2]})
      end
    end
  end
end
