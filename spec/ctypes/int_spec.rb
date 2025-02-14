# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe UInt32 do
    data_set = [
      {value: 0, endian: :big, str: "\x00\x00\x00\x00"},
      {value: 1, endian: :big, str: "\x00\x00\x00\x01"},
      {value: 0xffffffff, endian: :big, str: "\xff\xff\xff\xff"},
      {value: 0, endian: :little, str: "\x00\x00\x00\x00"},
      {value: 1, endian: :little, str: "\x01\x00\x00\x00"},
      {value: 0xffffffff, endian: :little, str: "\xff\xff\xff\xff"}
    ]

    describe ",pack" do
      data_set.each do |c|
        it "pack(%<value>p, endian: %<endian>p) -> %<str>p" % c do
          expect(described_class.pack(c[:value], endian: c[:endian]))
            .to eq(c[:str])
        end
      end
      it "pack(0xffffffff+1) will raise Dry::Types::ConstraintError" do
        expect { described_class.pack(0xffffffff + 1) }
          .to raise_error(Dry::Types::ConstraintError)
      end
    end

    describe ".unpack" do
      data_set.each do |c|
        it "unpack(%<str>p, endian: %<endian>p) -> %<value>p" % c do
          expect(described_class.unpack(c[:str], endian: c[:endian]))
            .to eq(c[:value])
        end
      end

      it 'unpack("\x00") will raise MissingBytesError' do
        expect { described_class.unpack("\x00") }
          .to raise_error(MissingBytesError)
      end
    end
  end
end
