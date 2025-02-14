# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe Bitfield do
    [
      {
        layout: proc do
          unsigned :a
          unsigned :b, 2
          unsigned :c, 3
        end,
        size: 1,
        pack: {
          {} => "\0",
          {a: 1} => bitstr("00000001"),
          {b: 3} => bitstr("00000110"),
          {c: 7} => bitstr("00111000"),
          {a: 1, b: 1, c: 1} => bitstr("00001011"),
          {a: 2} => [Dry::Types::SchemaError],
          {invalid_key: 1} => [Dry::Types::UnknownKeysError, /invalid_key/]
        },
        unpack: {
          "\0X" => [{a: 0, b: 0, c: 0}, "X"],
          bitstr("00001011") + "X" => [{a: 1, b: 1, c: 1}, "X"],
          bitstr("10001011") + "X" => [{a: 1, b: 1, c: 1}, "X"],
          "" => [CTypes::MissingBytesError]
        }
      },
      {
        layout: proc do
          unsigned :a
          skip 2
          unsigned :b
          align 8
          signed :signed, 5
        end,
        size: 2,
        pack: {
          {} => "\0\0",
          {a: 1, b: 1, signed: 1} => bitstr("0000000100001001"),
          {a: 1, b: 1, signed: 2} => bitstr("0000001000001001"),
          {a: 1, b: 1, signed: -1} => bitstr("0001111100001001"),
          {a: 1, b: 1, signed: -2} => bitstr("0001111000001001"),
          {a: 1, b: 1, signed: -200} => [Dry::Types::SchemaError]
        },
        unpack: {
          "\0\0X" => [{a: 0, b: 0, signed: 0}, "X"],
          bitstr("0000000100001001") => [{a: 1, b: 1, signed: 1}, ""],
          bitstr("0000001000001001") => [{a: 1, b: 1, signed: 2}, ""],
          bitstr("0001111100001001") => [{a: 1, b: 1, signed: -1}, ""],
          bitstr("0001111000001001") => [{a: 1, b: 1, signed: -2}, ""]
        }
      },
      # left-to-right packing example
      {
        layout: proc do
          field :a, offset: 7, bits: 1
          field :b, offset: 4, bits: 1
        end,
        size: 1,
        pack: {
          {} => "\0",
          {a: 1, b: 1} => bitstr("10010000")
        },
        unpack: {
          bitstr("10010000") => [{a: 1, b: 1}, ""]
        }
      },
      # fixed size
      {
        layout: proc do
          endian :big
          bytes 4
          unsigned :a
        end,
        size: 4,
        pack: {
          {} => "\0\0\0\0",
          {a: 1} => "\0\0\0\1"
        },
        unpack: {
          "\0\0\0\0X" => [{a: 0}, "X"],
          "\0" => [CTypes::MissingBytesError, /missing 3 bytes/]
        }
      }
    ].each do |ctx|
      context "layout %s" % [ctx[:layout].source] do
        let(:bitfield) do
          Class.new(described_class) { layout(&ctx[:layout]) }
        end

        ctx[:pack].each_pair do |input, output|
          if output.is_a?(::String)
            it "pack(%p) # => %p" % [input, output] do
              packed = bitfield.pack(input)
              expect(packed).to eq(output)
            end
          else
            it "pack(%p) will raise error %p" % [input, output] do
              expect { bitfield.pack(input) }.to raise_error(*output)
            end
          end
        end
        ctx[:unpack].each_pair do |input, output|
          if output.first.is_a?(Hash)
            it "unpack_one(%p) # => %p" % [input, output] do
              expect(bitfield.unpack_one(input)).to eq(output)
            end
          else
            it "unpack_one(%p) will raise error %p" % [input, output] do
              expect { bitfield.unpack_one(input) }.to raise_error(*output)
            end
          end
        end
      end
    end
  end
end
