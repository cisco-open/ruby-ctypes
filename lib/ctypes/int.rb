# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # Handles packing and unpacking of integer types of various lengths and
  # signed-ness.  The most common integer sizes have been declared as
  # constants:
  # - unsigned: {UInt64}, {UInt32}, {UInt16}, {UInt8}
  # - signed: {Int64}, {Int32}, {Int16}, {Int8}
  # or their respective helpers in {Helpers}.
  class Int
    include Type

    # initialize an {Int} type
    #
    # @param [Integer] bits number of bits in the integer
    # @param [Boolean] signed set to true if integer is signed
    # @param [String] format {::Array#pack} format for integer
    # @param [String] desc human-readable description of type
    #
    def initialize(bits:, signed:, format:, desc:)
      type = Dry::Types["integer"].default(0)
      @signed = !!signed
      if @signed
        @min = 0 - (1 << (bits - 1))
        @max = 1 << (bits - 1) - 1
      else
        @min = 0
        @max = (1 << bits) - 1
      end
      @dry_type = type.constrained(gteq: @min, lteq: @max)
      @size = bits / 8
      if @size > 1
        @format_big = "#{format}>"
        @format_little = "#{format}<"
      else
        @format_big = @format_little = format.to_s
      end
      @fmt = (@size > 1) ? {big: "#{format}>", little: "#{format}<"} :
        {big: format.to_s, little: format.to_s}
      @desc = desc
    end
    attr_reader :size, :min, :max

    # convert an Integer into a String containing the binary representation of
    # that number for the given type.
    #
    # @param value [Integer] number to pack
    # @param endian [Symbol] byte order
    # @param validate [Boolean] set to false to disable bounds checking
    # @return [String] binary encoding for value
    #
    # @example pack a uint32_t using the native endian
    #   CTypes::UInt32.pack(0x12345678) # => "\x78\x56\x34\x12"
    #
    # @example pack a big endian uint32_t
    #   CTypes::UInt32.pack(endian: :big) # => "\x12\x34\x56\x78"
    #
    # @example pack a fixed-endian (big) uint32_t
    #   t = UInt32.with_endian(:big)
    #   t.pack(0x12345678) # => "\x12\x34\x56\x78"
    #
    # @see CTypes::Type#pack
    def pack(value, endian: default_endian, validate: true)
      value = (value.nil? ? @dry_type[] : @dry_type[value]) if validate
      endian ||= default_endian
      [value].pack(@fmt[endian])
    end

    # decode an Integer from the byte String provided, returning both the
    # Integer and any unused bytes in the String
    #
    # @param buf [String] bytes to be unpacked
    # @param endian [Symbol] endian of data within buf
    # @return [Integer, String] decoded Integer, and remaining bytes
    #
    # @example pack a uint32_t using the native endian
    #   CTypes::UInt32.pack(0x12345678) # => "\x78\x56\x34\x12"
    #
    # @example pack a big endian uint32_t
    #   CTypes::UInt32.pack(endian: :big) # => "\x12\x34\x56\x78"
    #
    # @example pack a fixed-endian (big) uint32_t
    #   t = UInt32.with_endian(:big)
    #   t.pack(0x12345678) # => "\x12\x34\x56\x78"
    #
    # @see CTypes::Type#unpack
    # @see CTypes::Type#unpack_one
    def unpack_one(buf, endian: default_endian)
      endian ||= default_endian # override nil
      value = buf.unpack1(@fmt[endian]) or
        raise missing_bytes_error(input: buf, need: @size)
      [value, buf.byteslice(@size..)]
    end

    # @api private
    def greedy?
      false
    end

    # @api private
    def signed?
      @signed
    end

    # @api private
    def pretty_print(q) # :nodoc:
      if @endian
        q.text(@desc + ".with_endian(%p)" % @endian)
      else
        q.text(@desc)
      end
    end
    alias_method :inspect, :pretty_inspect # :nodoc:

    # @api private
    def export_type(q) # :nodoc:
      q << @desc
      q << ".with_endian(%p)" % [@endian] if @endian
    end

    # @api private
    def type_name
      "#{@desc}_t"
    end
  end

  # base type for unsiged 8-bit integers
  UInt8 = Int.new(bits: 8, signed: false, format: "C", desc: "uint8")
  # base type for unsiged 16-bit integers
  UInt16 = Int.new(bits: 16, signed: false, format: "S", desc: "uint16")
  # base type for unsiged 32-bit integers
  UInt32 = Int.new(bits: 32, signed: false, format: "L", desc: "uint32")
  # base type for unsiged 64-bit integers
  UInt64 = Int.new(bits: 64, signed: false, format: "Q", desc: "uint64")
  # base type for siged 8-bit integers
  Int8 = Int.new(bits: 8, signed: true, format: "c", desc: "int8")
  # base type for siged 16-bit integers
  Int16 = Int.new(bits: 16, signed: true, format: "s", desc: "int16")
  # base type for siged 32-bit integers
  Int32 = Int.new(bits: 32, signed: true, format: "l", desc: "int32")
  # base type for siged 64-bit integers
  Int64 = Int.new(bits: 64, signed: true, format: "q", desc: "int64")
end
