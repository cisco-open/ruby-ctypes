# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # map bits in an integer to specific flags
  #
  # This class enables the mapping of individual bits in an integer to specific
  # flags that each bit represents.  This class only supports single bit
  # fields.  See `Bitfield` if you need to unpack multibit values.
  #
  # @example 8-bit bitmap, the long way
  #   b = Bitmap.new(
  #     bits: Enum.new({a: 0, b: 1, c: 7}),
  #     type: CTypes::UInt8)
  #
  #   # pack some values
  #   b.pack([])                # => "\x00"
  #   b.pack([:a])              # => "\x01"
  #   b.pack([:b])              # => "\x02"
  #   b.pack([:c])              # => "\x80"
  #   b.pack([:c, :a])          # => "\x81"
  #   b.pack([:a, :c])          # => "\x81"
  #
  #   # unpack some values
  #   b.unpack("\x00")          # => []
  #   b.unpack("\x01")          # => [:a]
  #   b.unpack("\x02")          # => [:b]
  #   b.unpack("\x03")          # => [:a, :b]
  #   b.unpack("\x80")          # => [:c]
  #
  # @example 8-bit bitmap, using helpers
  #   include CTypes::Helpers   # for bitmap and uint8
  #   b = bitmap(uint8, {a: 0, b: 1, c: 7})
  #   b.pack([:a, :c])          # => "\x81"
  #   b.unpack("\x03")          # => [:a, :b]
  class Bitmap
    extend Forwardable
    include Type

    # create a new Bitmap
    # @param bits [Enum] mapping of bit position to name
    # @param type [Type] ctype to encode value as; defaults to uint32
    def initialize(bits:, type: Helpers.uint32)
      raise Error, "bits must be an Enum instance: %p" % bits unless
        bits.is_a?(Enum)

      @type = type
      @bits = bits
      @bits_max = type.size * 8
      @bits_constraint = Dry::Types["integer"]
        .constrained(gteq: 0, lt: @bits_max)
      @dry_type = Dry::Types["array"].of(@bits.dry_type).default([].freeze)
    end
    def_delegators :@type, :greedy?

    def size
      @type.size
    end

    def fixed_size?
      @type.fixed_size?
    end

    # pack a ruby Array containing symbol names for each bit into a binary
    # string
    # @param value [::Array] Array of bits to be set, by name or right-to-left
    #   index
    # @param endian [Symbol] optional endian override
    # @param validate [Boolean] set to false to disable value validation
    # @return [::String] binary encoding for value
    #
    # @example packing with named values
    #   b = CTypes::Helpers.bitmap(uint8, {a: 0, b: 1, c: 7})
    #   b.pack([:a, :c])          # => "\x81"
    #
    # @example packing explicit bits
    #   b = CTypes::Helpers.bitmap(uint8, {a: 0, b: 1, c: 7})
    #   b.pack([0, 7])                    # => "\x81" (0b10000000)
    #   b.pack([0, 6])                    # => Dry::Types::ConstraintError
    #   b.pack([0, 6], validate: false)   # => "\x41" (0b01000001)
    #
    def pack(value, endian: default_endian, validate: true)
      value = @dry_type[value] unless validate == false
      mapping = @bits.mapping
      bits = value.inject(0) do |out, v|
        bit = case v
        when Integer
          v
        when /\Abit_(\d+)\z/
          $1.to_i
        when Symbol
          mapping[v]
        else
          raise Error, "unknown bitmap value: %p" % v
        end
        @bits_constraint[bit]
        out |= 1 << bit
      end
      @type.pack(bits, endian: @type.endian || endian, validate: validate)
    end

    # convert a String containing the binary represention of a c type into the
    # equivalent ruby type
    #
    # @param buf [::String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return [::Array] unpacked bitfield
    #
    # @example
    #   b = bitmap(uint8, {a: 0, b: 1, c: 7})
    #   b.unpack("\x00")                  # => []
    #   b.unpack("\x01")                  # => [:a]
    #   b.unpack("\x81")                  # => [:a, :c]
    #
    # @example allow unlabelled bits in the value
    #   b = bitmap(uint8, {a: 0, b: 1, c: 7})
    #   b.unpack("\x04")                  # => Dry::Types::ConstraintError
    #
    #   # create a new permissive bitmap from the initial bitmap
    #   bp = b.permissive
    #   bp.unpack("\x04")                 # => [:bit_2]
    #
    #   # known bits are still unpacked with the proper name
    #   bp.unpack("\x05")                 # => [:a, :bit_2]
    #
    def unpack_one(buf, endian: default_endian)
      value, rest = @type.unpack_one(buf, endian: @type.endian || endian)
      bits = []
      @bits_max.times do |bit|
        next if value & (1 << bit) == 0
        v = @bits.dry_type[bit]
        v = :"bit_#{v}" if v.is_a?(Integer)
        bits << v
      end
      [bits, rest]
    end

    # get a permissive version of this bitmap
    # @return [Bitmap] permissive version of the bitmap.
    #
    # @example
    #   b = CTypes::Helpers.bitmap(uint8, {a: 0})
    #   b.unpack("\x04")                  # => Dry::Types::ConstraintError
    #
    #   b = CTypes::Helpers.bitmap(uint8, {a: 0}).permissive
    #   b.unpack("\x04")                  # => [:bit_2]
    def permissive
      Bitmap.new(type: @type, bits: @bits.permissive)
    end
  end
end
