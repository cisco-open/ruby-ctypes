# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe "Type" do
    describe "#with_endian" do
      it "will return the same object with multiple calls" do
        int8 = CTypes::Int8
        expect(int8.with_endian(:big)).to be(int8.with_endian(:big))
      end

      # hit a case where a struct declared with an explicit endian caused an
      # infinite loop when #with_endian was called.
      it "regression: type declared with endian does not throw exception" do
        t = Helpers.struct do
          endian :big
          attribute :name, string
        end
        expect { t.with_endian(:big) }.to_not raise_error
        expect { t.with_endian(:little) }.to_not raise_error
      end
    end

    describe "#without_endian" do
      it "will return the endian-free object" do
        int8 = CTypes::Int8
        expect(int8.with_endian(:big).without_endian).to be(int8)
      end
    end
  end
end
