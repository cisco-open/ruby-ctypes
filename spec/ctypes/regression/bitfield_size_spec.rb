# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe "regression: bitfield size calculation" do
    it "will correctly calculate bitfield size with .skip" do
      type = Helpers.bitfield {
        skip 3
        unsigned :base, 25
        skip 3
        unsigned :en
        skip 31
      }

      expect(type.size).to eq(8)
    end

    it "will correctly calculate bitfield size with .field" do
      type = Helpers.bitfield {
        field(:base, offset: 3, bits: 25)
        field(:en, offset: 32, bits: 1)
      }

      expect(type.size).to eq(8)
    end
  end
end
