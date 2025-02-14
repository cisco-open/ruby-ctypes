# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe "regression: Union#to_h" do
    it "will not expose internal state" do
      type = Helpers.union do
        member :len, uint8
        member :body, string
      end
      inst = type.unpack("\1")
      inst.to_h[:blah] = 3
      expect(inst.to_h).to_not have_key(:blah)
    end
  end
end
