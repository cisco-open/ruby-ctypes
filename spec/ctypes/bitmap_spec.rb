# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe Bitmap do
    [
      {
        type: uint32,
        bits: {a: 0, b: 16},
        size: 4,
        pack: {
          [] => "\0\0\0\0",
          [:a] => "\1\0\0\0",
          [:b] => "\0\0\1\0",
          [:a, :b] => "\1\0\1\0",
          [5] => Dry::Types::ConstraintError,
          [32] => Dry::Types::ConstraintError,
          [-1] => Dry::Types::ConstraintError
        },
        unpack: {
          "\0\0\0\0X" => [[], "X"],
          "\1\0\0\0X" => [[:a], "X"],
          "\0\0\1\0X" => [[:b], "X"],
          "\1\0\1\0X" => [[:a, :b], "X"],
          "\1\1\1\1" => [Dry::Types::ConstraintError],
          "\1\1" => [MissingBytesError, /missing 2 bytes/]
        }
      },
      {
        type: uint8,
        bits: {a: 0, b: 5},
        size: 1,
        pack: {
          [] => "\0",
          [:a] => "\1",
          [:b] => uint8.pack(1 << 5),
          [:a, :b] => uint8.pack(1 | (1 << 5)),
          [1] => Dry::Types::ConstraintError,
          [8] => Dry::Types::ConstraintError,
          [-1] => Dry::Types::ConstraintError
        },
        unpack: {
          "\0X" => [[], "X"],
          "\1X" => [[:a], "X"],
          uint8.pack(1 << 5) << "X" => [[:b], "X"],
          uint8.pack(1 | (1 << 5)) << "X" => [[:a, :b], "X"],
          "\8" => [Dry::Types::ConstraintError]
        }
      },
      {
        type: uint8,
        bits: {a: 0, b: 5},
        size: 1,
        permissive: true,
        pack: {
          [] => "\0",
          [:a] => "\1",
          [:b] => uint8.pack(1 << 5),
          [:a, :b] => uint8.pack(1 | (1 << 5)),
          [0, :b] => uint8.pack(1 | (1 << 5)),
          [1] => uint8.pack(1 << 1),
          [:bit_1, :bit_3] => uint8.pack((1 << 1) | (1 << 3)),
          [8] => Dry::Types::ConstraintError,
          [:bit_8] => Dry::Types::ConstraintError,
          [-1] => Dry::Types::ConstraintError
        },
        unpack: {
          "\0X" => [[], "X"],
          "\1X" => [[:a], "X"],
          uint8.pack(1 << 5) << "X" => [[:b], "X"],
          uint8.pack(1 | (1 << 5)) << "X" => [[:a, :b], "X"],
          uint8.pack((1 << 0) | (1 << 1) | (1 << 3)) =>
            [[:a, :bit_1, :bit_3], ""]
        }
      }
    ].each do |ctx|
      context "Bitmap.new(%s, %p)" % [ctx[:type], ctx[:bits]] do
        let(:bitmap) do
          enum = Enum.new(ctx[:bits])
          bitmap = described_class.new(type: ctx[:type], bits: enum)
          ctx[:permissive] ? bitmap.permissive : bitmap
        end

        it "#size # => %d" % ctx[:size] do
          expect(bitmap.size).to eq(ctx[:size])
        end

        describe "#pack" do
          ctx[:pack].each_pair do |input, output|
            if output.is_a?(::String)
              it "pack(%p) # => %p" % [input, output] do
                expect(bitmap.pack(input)).to eq(output)
              end
            else
              it "pack(%p) will raise error %p" % [input, output] do
                expect { bitmap.pack(input) }.to raise_error(*output)
              end
            end
          end
        end

        describe "#unpack_one" do
          ctx[:unpack].each_pair do |input, output|
            if output.first.is_a?(::Array)
              it "unpack(%p) # => %p" % [input, output] do
                result = bitmap.unpack_one(input)
                expect(result).to eq(output)
              end
            else
              it "unpack(%p) will raise error %p" % [input, output] do
                expect { bitmap.unpack_one(input) }.to raise_error(*output)
              end
            end
          end
        end
      end
    end
  end
end
