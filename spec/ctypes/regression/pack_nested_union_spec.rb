# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # Caused failures in:
  # - DryType validation in Struct#pack with deeply nested virtual fields
  # - Union#to_binstr() causes Union#pack to try to delete from Struct instance
  # - Struct#to_binstr() calls Union#pack with multiple keys
  #   - this is a result of Union#to_h returning multiple keys
  RSpec.describe "regression: struct { union { struct { bitfield }} }#to_binstr" do
    it "will pack correctly" do
      type = Helpers.struct {
        attribute :union, union {
          member :u32, uint32
          member :bits, struct {
            attribute bitfield {
              unsigned :a
            }
          }
        }
      }

      value = type.new
      value.union.bits.a = 1
      expect(value.to_binstr).to eq("\x01\0\0\0")
    end
  end
end
