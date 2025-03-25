# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

require "dry-types"

module CTypes
  module Helpers
    extend self

    # define integer types
    [8, 16, 32, 64, 128].each do |bits|
      define_method("uint%d" % bits) { CTypes.const_get("UInt#{bits}") }
      define_method("int%d" % bits) { CTypes.const_get("Int#{bits}") }
    end

    # create an {Enum} type
    # @param type [Type] integer type to encode as; default uint32
    # @param values [Array, Hash] value names, or name-value pairs
    #
    # @example 8-bit enum with two known values
    #   t = enum(uint8, [:a, :b])
    #   t.pack(:a)                  # => "\x00"
    #   t.pack(:b)                  # => "\x01"
    #   t.pack(:c)                  # Dry::Types::ConstraintError
    #
    # @example sparse 32-bit enum
    #   t = enum(uint32, {none: 0, a: 0x1000, b: 0x20})
    #   t.pack(:none)               # => "\0\0\0\0"
    #   t.pack(:a)                  # => "\x00\x10\x00\x00" (little endian)
    #   t.pack(:b)                  # => "\x20\x00\x00\x00" (little endian)
    #
    # @example sparse 32-bit enum using builder
    #   t = enum(uint16) do |e|
    #     e << %i{a b c}            # a = 0, b = 1, c = 2
    #     e << {d: 16}              # d = 16
    #     e << :e                   # e = 17
    #   end
    #   t.pack(:e)                  # => "\x11\x00" (little endian)
    def enum(type = nil, values = nil, &)
      Enum.new(type, values, &)
    end

    # create a {Bitmap} type
    # @param type [Type] integer type to encode as; default min bytes required
    # @param bits [Hash, Enum] map of names to bit position
    #
    # @example 32-bit bitmap
    #   bitmap({a: 0, b: 1, c: 2})  # => #<Bitmap ...>
    #
    # @example 32-bit bitmap using block syntax; same as [Enum]
    #   bitmap do |b|
    #     b << :a
    #     b << :b
    #   end # => #<Bitmap a: 0, b: 1>
    #
    # @example 8-bit bitmap
    #   bitmap(uint8, {a: 0, b: 1}) # => #<Bitmap a: 0, b: 1>
    #
    def bitmap(type = nil, bits = nil, &)
      if bits.nil?
        bits = type
        type = uint32
      end

      bits = enum(bits, &) unless bits.is_a?(Enum)
      Bitmap.new(type: type, bits: bits)
    end

    # create a {String} type
    # @param size [Integer] optional string size in bytes
    # @param trim [Boolean] set to false to preserve trailing null bytes when
    #   unpacking
    #
    # @example 5 byte string
    #   s = string(5)
    #   s.unpack("hello world")   # => "hello")
    def string(size = nil, trim: true)
      String.new(size:, trim:)
    end

    # create a {Struct} type
    # @param attributes [Hash] name/type attribute pairs
    # @yield block passed to {Struct::Builder}
    #
    # @example hash syntax
    #   t = struct(id: uint32, name: string.terminated)
    #   t.pack({id: 1, name: "Karlach"})    # => "\1\0\0\0Karlach\0"
    #
    # @example block syntax
    #   t = struct do
    #     attribute :id, uint32
    #     attrubite :name, string.terminated
    #   end
    #   t.pack({id: 1, name: "Karlach"})    # => "\1\0\0\0Karlach\0"
    def struct(attributes = nil, &block)
      Class.new(Struct) do
        if attributes
          layout do
            attributes.each do |name, type|
              attribute name, type
            end
          end
        else
          layout(&block)
        end
      end
    end

    # create a {Union} type
    # @param members [Hash] name/type member pairs
    # @yield block bassed to {Union::Builder}
    #
    # @example hash syntax
    #   t = union(word: uint32, halfword: uint16, byte: uint8)
    #   t.pack({byte: 3})   # => "\x03\x00\x00\x00"
    #
    # @example block syntax
    #   t = union do
    #     member :word, uint32
    #     member :halfword, uint16
    #     member :byte, uint8
    #   end
    #   t.pack({byte: 3})   # => "\x03\x00\x00\x00"
    def union(members = nil, &block)
      Class.new(Union) do
        if members
          layout do
            members.each do |name, type|
              member name, type
            end
          end
        else
          layout(&block)
        end
      end
    end

    # create an {Array} type
    # @param type [Type] data type contained within the array
    # @param size [Integer] optional array size; no size implies greedy array
    # @param terminator optional unpacked value that represents the array
    #   terminator
    #
    # @example
    #   # greedy array of uint32 values
    #   array(uint32)
    #   # array of 4 uint8 values
    #   array(uint8, 4)
    #   # array of signed 32-bit integers terminated with a -1
    #   array(int32, terminator: -1)
    def array(type, size = nil, terminator: nil)
      Array.new(type:, size:, terminator:)
    end

    # create a {Bitfield} type
    # @param type [Type] type to use for packed representation
    # @param bits [Hash] map of name to bit count
    # @yield block passed to {Bitfield::Builder}
    #
    # @example dynamically sized
    #   t = bitfield(a: 1, b: 2, c: 3)
    #   t.pack({c: 0b111})    # => "\x38" (0b00111000)
    #
    # @example fixed size to pad to 16 bits.
    #   t = bitfield(uint16, a: 1, b: 2, c: 3)
    #   t.pack({c: 0b111})    # => "\x38\x00" (0b00111000_00000000)
    #
    def bitfield(type = nil, bits = nil, &block)
      if bits.nil? && !block
        bits = type
        type = nil
      end

      Class.new(Bitfield) do
        if bits
          layout do
            bytes(type.size) if type
            bits.each do |name, size|
              unsigned name, size
            end
          end
        else
          layout(&block)
        end
      end
    end
  end

  # To make CTypes easier to use without including Helpers everywhere, we're
  # going to extend Helpers into the CTypes namespace.  This is to support
  # interactive sessions through pry/irb where you need to quickly create types
  # without having to constantly type out `Helpers`.
  CTypes.extend(Helpers)
end
