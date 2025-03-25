# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

RSpec.describe CTypes::Enum do
  [
    {
      enum: ->(b) { b << %i[a b] },
      size: 4,
      pack: {
        :a => uint32.pack(0),
        :b => uint32.pack(1),
        :c => Dry::Types::ConstraintError,
        0 => uint32.pack(0),
        1 => uint32.pack(1),
        3 => Dry::Types::ConstraintError
      },
      unpack: {
        "\0\0\0\0" => [:a, ""],
        "\1\0\0\0" => [:b, ""],
        "\0\0\0\0X" => [:a, "X"],
        "\2\0\0\0" => Dry::Types::ConstraintError
      }
    },
    # try it with a different endian
    {
      enum: [uint32.with_endian(:big), %i[a b c]],
      size: 4,
      pack: {
        :a => uint32.with_endian(:big).pack(0),
        :b => uint32.with_endian(:big).pack(1),
        0 => uint32.with_endian(:big).pack(0),
        1 => uint32.with_endian(:big).pack(1)
      },
      unpack: {
        "\0\0\0\0" => [:a, ""],
        "\0\0\0\1" => [:b, ""],
        "\0\0\0\2" => [:c, ""],
        "\0\0\0\3" => Dry::Types::ConstraintError
      }
    },
    # try permissive enum
    {
      enum: ->(b) { b << %i[a b] },
      permissive: true,
      size: 4,
      pack: {
        :a => uint32.pack(0),
        :b => uint32.pack(1),
        :c => CTypes::Error,
        :unknown_0a => uint32.pack(0xa),
        0 => uint32.pack(0),
        1 => uint32.pack(1),
        3 => uint32.pack(3),
        0xa => uint32.pack(0xa)
      },
      unpack: {
        "\0\0\0\0" => [:a, ""],
        "\1\0\0\0" => [:b, ""],
        "\0\0\0\0X" => [:a, "X"],
        "\2\0\0\0" => [:unknown_00000002, ""]
      }
    }
  ].each do |ctx|
    desc = if ctx[:enum].is_a?(Proc)
      "Enum.new(%s)" % ctx[:enum].source
    else
      "Enum.new(*%p)" % ctx[:enum]
    end
    context desc do
      let(:enum) do
        enum = ctx[:enum].is_a?(Proc) ?
          described_class.new(&ctx[:enum]) :
          described_class.new(*ctx[:enum])
        ctx[:permissive] ? enum.permissive : enum
      end

      it "#size # => %d" % ctx[:size] do
        expect(enum.size).to eq(ctx[:size])
      end

      ctx[:pack].each do |input, output|
        if output.is_a?(::String)
          it "#pack(%p) # => %p" % [input, output] do
            expect(enum.pack(input)).to eq(output)
          end
        else
          it "#pack(%p) will raise %p" % [input, output] do
            expect { enum.pack(input) }.to raise_error(*output)
          end
        end
      end

      ctx[:unpack].each do |input, output|
        if output.is_a?(::Array)
          it "#unpack_one(%p) # => %p" % [input, output] do
            expect(enum.unpack_one(input)).to eq(output)
          end
        else
          it "#unpack_one(%p) will raise %p" % [input, output] do
            expect { enum.unpack_one(input) }.to raise_error(*output)
          end
        end
      end
    end
  end
  context "#default_value" do
    # ensure default_value works for enums without a zero value
    [
      [{zero: 0}, :zero],
      [{one: 1}, :one]
    ].each do |values, value|
      it "will return %p for enum(%p)" % [value, values] do
        e = described_class.new(values)
        expect(e.default_value).to eq(value)
      end
    end
  end

  context "#[]" do
    it "will return the Symbol for a known value" do
      e = described_class.new(%i[a b c])
      expect(e[1]).to eq(:b)
    end

    it "will return nil for an unknown value" do
      e = described_class.new(%i[a b c])
      expect(e[100]).to be_nil
    end

    it "will return the value for a known Symbol" do
      e = described_class.new({x: 0x1000})
      expect(e[:x]).to eq(0x1000)
    end

    it "will return nil for an unknown Symbol" do
      e = described_class.new(%i[a b c])
      expect(e[:unknown]).to be_nil
    end
  end
end
