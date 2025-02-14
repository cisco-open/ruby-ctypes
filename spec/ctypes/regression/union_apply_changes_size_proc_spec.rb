# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe "regression: Union#unpack" do
    it "not infinitely recurse on size Proc accessing multiple members" do
      type = Helpers.union {
        endian :big
        member :common, struct {
          attribute :type, uint8
        }
        member :a, struct {
          attribute :type, uint8
          attribute :size, uint8
        }
        member :b, struct {
          attribute :type, uint8
          pad 3
          attribute :size, uint32
        }
        size do |v|
          # XXX switch :type to be in a struct
          type = v[:common][:type]
          v[%i[a b][type]][:size]
        end
      }

      expect { type.unpack("\x00\x02\x00\x00\x00\x00") }.to_not raise_error
    end
  end
end
