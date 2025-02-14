# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe "regression: Union#pack smallest member with proc size" do
    it "will correctly pad temporary Union passed to size proc" do
      type = Helpers.union {
        endian :big
        member :type, uint8
        member :inner, struct {
          attribute :type, uint8
          attribute :size, uint32
        }
        size { |u| u.inner.size }
      }

      # will generate empty string because generated pad for inner will be all
      # zeros
      buf = type.pack({type: 5})
      expect(buf).to eq("")

      # this is the same as the above, but we're explicitly supplying the pad
      # of all zeros
      buf = type.pack({type: 5}, pad_bytes: "\x00\x00\x00\x00\x00")
      expect(buf).to eq("")

      # we're going to set a size of 1 in the pad bytes here to get 1 byte
      # containing the type.  Keep in mind pad_bytes is used internally by
      # Union in apply_changes! to preserve the tail of the buffer
      buf = type.pack({type: 5}, pad_bytes: "\x00\x00\x00\x00\x01")
      expect(buf).to eq("\x05")

      # a more likely example, size in the buffer is valid, and covers the
      # whole original pad string
      buf = type.pack({type: 0xf}, pad_bytes: "\x00\x00\x00\x00\x05")
      expect(buf).to eq("\x0f\x00\x00\x00\x05")

      # can actually extend the buffer beyond the pad to add trailing zeros
      buf = type.pack({type: 0xf}, pad_bytes: "\x00\x00\x00\x00\x09")
      expect(buf).to eq("\x0f\x00\x00\x00\x09\x00\x00\x00\x00")
    end
  end
end
