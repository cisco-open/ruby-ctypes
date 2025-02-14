# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe "regression: apply_changes! with nested union" do
    it "will convert the active field to a hash before calling .pack" do
      type = Helpers.union {
        member :u64, uint64
        member :inner, union {
          member :u8, uint8
          member :u16, uint16
        }
      }

      value = type.new
      value.inner
      expect { value.send(:apply_changes!) }.to_not raise_error
      value.inner
      value.inner.u8 = 3
      expect { value.send(:apply_changes!) }.to_not raise_error
    end
  end
end
