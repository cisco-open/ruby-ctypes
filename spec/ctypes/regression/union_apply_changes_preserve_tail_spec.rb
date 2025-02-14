# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe "regression: Union#apply_changes!" do
    it "will preserve the buf tail when packing smaller member" do
      type = Helpers.union {
        endian :big
        member :u16, uint16
        member :u32, uint32
      }

      value = type.unpack("\xde\xad\xbe\xef")
      value.u16 = 0xabcd
      expect(value.u32).to eq(0xabcdbeef)
    end

    it "will preserve the buf tail for nested unions" do
      type = Helpers.union {
        endian :big
        member :inner, union {
          member :u16, uint16 # we'll set this one
          member :u32, uint32 # this will cause inner to take 4 bytes
        }
        member :u32, uint32
      }

      value = type.unpack("\xde\xad\xbe\xef")
      value.inner.u16 = 0xabcd
      expect(value.u32).to eq(0xabcdbeef)
    end
  end
end
