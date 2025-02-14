# encoding: ASCII-8BIT
# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe Array do
    [
      # fixed length array of ints
      {
        array: {type: uint8, size: 5},
        size: 5,
        pack: {
          [] => "\0\0\0\0\0",
          [1] => "\1\0\0\0\0",
          [1,2,3,4,5] => "\1\2\3\4\5",
          [1,2,3,4,5,6] => [Dry::Types::ConstraintError, /size/],
        },
        unpack: {
          "\1\2\3\4\5" => [[1,2,3,4,5], ""],
          "\1\2\3\4\5XXX" => [[1,2,3,4,5], "XXX"],
          "\1\2\3\4" => MissingBytesError,
        },
      },

      # variable length (greedy) array of bytes
      {
        array: {type: uint8, size: nil},
        size: 0,
        pack: {
          [] => "",
          [1] => "\1",
          [1,2,3,4,5] => "\1\2\3\4\5",
          [1,2,3,4,5,6] => "\1\2\3\4\5\6",
        },
        unpack: {
          "\1\2\3\4\5" => [[1,2,3,4,5], ""],
          "\1\2\3\4" => [[1,2,3,4], ""],
          "" => [[], ""],
        },
      },

      # variable length (greedy) array of multibyte ints
      {
        array: {type: uint16.with_endian(:big), size: nil},
        size: 0,
        pack: {
          [] => "",
          [1] => "\0\1",
          [1,2] => "\0\1\0\2",
        },
        unpack: {
          "\0\1\0\2\0\3\0\4\0\5" => [[1,2,3,4,5], ""],
          "\1" => CTypes::MissingBytesError,
          "" => [[], ""],
        },
      },
      {
        array: {type: string(3), size: 2},
        size: 6,
        pack: {
          [] => "\0" * 6,
          ["boo", "hoo"] => "boohoo",
        },
        unpack: {
          "short" => MissingBytesError,
          "boohoo" => [["boo", "hoo"], ""],
          "boohooXXX" => [["boo", "hoo"], "XXX"],
        },
      },
      # array of fixed size structures
      {
        array: {type: struct(a: uint8, b: uint8), size: 2},
        size: 4,
        pack: {
          [] => "\0" * 4,
          [{a: 1, b: 2}, {a: 3, b: 4}] => "\1\2\3\4",
        },
        unpack: {
           "\1\2\3\4" => [[{a: 1, b: 2}, {a: 3, b: 4}], ""],
           "\1\2\3\4XXX" => [[{a: 1, b: 2}, {a: 3, b: 4}], "XXX"],
           "\1\2\3" => MissingBytesError,
        },
      },
      # fixed-size array of variable length strings
      {
        array: {type: string.terminated("\0"), size: 2},
        size: 2,
        pack: {
          [] => "\0\0",
          ["hello", "world"] => "hello\0world\0",
        },
        unpack: {
          "\0\0" => [["", ""], ""],
          "hello\0world\0" => [["hello", "world"], ""],
        },
      },
      # variable-sized array, terminated with a specific value
      {
        array: {type: int8, terminator: -1},
        size: 1,
        pack: {
          [] => "\xff",
          [1,2] => "\1\2\xff",
        },
        unpack: {
          "\xff" => [[], ""],
           "\1\2\xff" => [[1,2], ""],
           "\1\2\xffXXXXX" => [[1,2], "XXXXX"],
           "\1\2" => TerminatorNotFoundError,
           "" => TerminatorNotFoundError,
        },
      },
      # variable-sized array of structs, terminated with a specific value
      {
        array: {
          type: struct do
            attribute :type, int8
            attribute :len, uint8
            attribute :value, string
            size { |s| offsetof(:value) + s[:len] }
          end,
          terminator: {type: -1, len: 0, value: ""},
        },
        size: 2,
        pack: {
          [] => "\xff\0",
          [{type: 1, len: 5, value: "hello"}] => "\x01\x05hello\xFF\x00",
        },
        unpack: {
          "\xff\0" => [[], ""],
          "\x01\x05hello\xFF\x00" => [[{type: 1, len: 5, value: "hello"}], ""],
          "\x01\x05hello\xFF\x00XXX" => [
            [{type: 1, len: 5, value: "hello"}], "XXX"
          ],
          "\x01\x05hello" => TerminatorNotFoundError,
        },
      },
    ].each do |ctx|
      context "Array.new(**%p)" % ctx[:array] do
        let(:array) { described_class.new(**ctx[:array]) }


        it "#size => %d" % ctx[:size] do
          expect(array.size).to eq(ctx[:size])
        end

        describe "#pack" do
          ctx[:pack].each do |input, output|
            if output.is_a?(::String)
              it "pack(%p) # => %p" % [input, output] do
                expect(array.pack(input)).to eq(output)
              end
            else
              it "pack(%p) will raise %p" % [input, output] do
                expect { array.pack(input) }.to raise_error(*output)
              end
            end
          end
        end

        describe "#unpack_one" do
          ctx[:unpack].each do |input, output|
            if output.is_a?(::Array)
              it "unpack_one(%p) # => %p" % [input, output] do
                result = array.unpack_one(input).map do |r|
                  r.is_a?(Struct) ? r.to_h : r
                end

                expect(result).to eq(output)
              end
            else
              it "unpack_one(%p) will raise %p" % [input, output] do
                expect { array.unpack_one(input) }.to raise_error(*output)
              end
            end
          end
        end
      end
    end

    it "Array.new(type: variable-length Union) will raise error" do
      union = Helpers.union do
        member :a, string
      end
      expect { described_class.new(type: union) }
        .to raise_error(Error, /variable-length Union/)
    end

    # At one point we were allocating an array as the default value.  When
    # someone declared a huge array, we happily allocated as much ram as we
    # could before the process was killed.  This should prevent that from ever
    # being committed again.
    it "Array.new(type: uint32, size: 0xffffffff) doesn't crash" do
      described_class.new(type: CTypes::Helpers.uint32, size: 0xffffffff)
    end
  end
end

