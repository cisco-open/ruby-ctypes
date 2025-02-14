# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe "regression: bitfield size calculation" do
    it "will correctly propagate u64 changes to bitfield" do
      type = Helpers.union {
        member :u64, uint64
        member bitfield {
          bytes 8
          field :en, offset: 31, bits: 1, signed: false
          field :base, offset: 3, bits: 25, signed: false
        }
      }.with_endian(:big)

      value = type.new
      value.u64 = 0x0000000081fc0048
      expect(value.en).to eq(1)
    end
  end
end
