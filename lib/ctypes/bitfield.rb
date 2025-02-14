# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # define a bit-field type for use in structures
  # @example 8-bit integer split into three multibit values
  #   class MyBits < CTypes::Bitfield
  #     # declare bit layout in right-to-left order
  #     layout do
  #       unsigned :bit             # single bit for a
  #       skip 1                    # skip one bit
  #       unsigned :two, 2          # two bits for this field
  #       signed :nibble, 4         # four bit nibble as a signed int
  #     end
  #   end
  #
  #   # size is the number of bytes required by the layout, but can be larger
  #   # when requested in #layout
  #   MyBits.size                   # => 1
  #
  #   # The bits are packed right-to-left
  #   MyBits.pack({bit: 1})         # => "\x01" (0b00000001)
  #   MyBits.pack({two: 3})         # => "\x0c" (0b00001100)
  #   MyBits.pack({nibble: -1})     # => "\xf0" (0b11110000)
  #
  #   # unpack a value and access individual fields
  #   value = MyBits.unpack("\xf1") # => #<Bitfield bit: 1, two: 0, nibble: -1>
  #   value.bit                     # => 1
  #   value.two                     # => 0
  #   value.nibble                  # => -1
  #
  #   # update the value and repack
  #   value.two = 1
  #   value.nibble = 0
  #   value.to_binstr               # => "\x05" (0b00000101)
  class Bitfield
    extend Type
    using PrettyPrintHelpers

    # describe the layout of the bitfield
    #
    # @example right-to-left bit layout
    #   layout do
    #     unsigned :bit             # single bit for a
    #     skip 1                    # skip one bit
    #     unsigned :two, 2          # two bits for this field
    #     signed :nibble, 4         # four bit nibble as a signed int
    #   end
    #
    # @example explicit bit layout
    #   layout do
    #     field :bit, offset: 0, bits: 1
    #     field :two, offset: 2, bits: 2
    #     field :nibble, offset: 4, bits: 4
    #   end
    #
    # @example create a two-byte bitfield, but only one bit declared
    #   layout do
    #     size 2                    # bitfield will take two bytes
    #     field :bit, offset: 9, bits: 1
    #   end
    #
    def self.layout(&block)
      raise Error, "no block given" unless block
      builder = Builder.new(&block)
      builder.instance_eval(&block)
      apply_layout(builder)
    end

    # @api private
    def self.builder
      Builder.new
    end

    # @api private
    def self.apply_layout(builder)
      @type, @bits, @dry_type, @endian, @layout = builder.result

      # clear all existing field accessors
      @fields ||= {}
      @fields.each { |_, methods| remove_method(*methods) }
      @fields.clear

      @bits.each do |name, _|
        @fields[name] = attr_accessor(name)
      end

      self
    end
    private_class_method :apply_layout

    # get the size of the bitfield in bytes
    def self.size
      @type.size
    end

    # check if bitfield is a fixed size
    def self.fixed_size?
      true
    end

    # check if bitfield is greedy
    def self.greedy?
      false
    end

    # pack a ruby hash containing bitfield values into a binary string
    # @param value [Hash] value to be encoded
    # @param endian [Symbol] optional endian override
    # @param validate [Boolean] set to false to disable value validation
    # @return [::String] binary encoding for value
    def self.pack(value, endian: default_endian, validate: true)
      value = value.to_hash.freeze
      value = @dry_type[value] unless validate == false
      out = 0
      @bits.each do |(name, offset, mask, _)|
        out |= (value[name] & mask) << offset
      end
      @type.pack(out, endian:, validate:)
    end

    # convert a String containing the binary represention of a c type into the
    # equivalent ruby type
    #
    # @param buf [::String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return [Bitfield] unpacked bitfield
    def self.unpack_one(buf, endian: default_endian)
      value, rest = @type.unpack_one(buf, endian:)
      out = _new
      @bits.each do |(name, offset, mask, signed, var)|
        v = (value >> offset) & mask
        v |= (-1 << signed) | v if signed && v[signed - 1] == 1
        out.instance_variable_set(var, v)
      end

      [out, rest]
    end

    # get the list of fields defined in this bitfield
    def self.fields
      @fields.keys
    end

    # check if the bitfield declared a specific field
    def self.has_field?(name)
      @fields.has_key?(name)
    end

    def self.pretty_print(q)
      q.ctype("bitfield", @endian) do
        q.seplist(@layout, -> { q.breakable(";") }) do |cmd|
          q.text(cmd)
        end
      end
    end
    class << self
      alias_method :inspect, :pretty_inspect # :nodoc:
    end

    # generate ruby code needed to create this type
    def self.export_type(q)
      q << "bitfield {"
      q.break
      q.nest(2) do
        @layout.each do |cmd|
          q << cmd
          q.break
        end
      end
      q << "}"
      q << ".with_endian(%p)" % [@endian] if @endian
    end

    class << self
      # @method _new
      # allocate an uninitialized instance of the bitfield
      # @return [Bitfield] uninitialized bitfield instance
      # @api private
      alias_method :_new, :new
      private :_new
    end

    # allocate an instance of the Bitfield and initialize default values
    # @param fields [Hash] values to set
    # @return [Bitfield]
    def self.new(fields = nil)
      buf = fields.nil? ? ("\0" * size) : pack(fields)
      unpack(buf)
    end

    def self.==(other)
      return true if super
      return false unless other.is_a?(Class) && other < Bitfield
      other.field_layout == @bits &&
        other.default_endian == default_endian &&
        other.size == size
    end

    # @api private
    def self.field_layout # :nodoc:
      @bits
    end

    # set a bitfield value
    # @param k [Symbol] field name
    # @param v value
    def []=(k, v)
      has_field!(k)
      instance_variable_set(:"@#{k}", v)
    end

    # get an bitfield value
    # @param k [Symbol] field name
    # @return value
    def [](k)
      has_field!(k)
      instance_variable_get(:"@#{k}")
    end

    def has_key?(name)
      self.class.has_field?(name)
    end

    def has_field!(name) # :nodoc:
      raise UnknownFieldError, "unknown field: %p" % name unless
        self.class.has_field?(name)
    end
    private :has_field!

    def to_h(shallow: false)
      out = {}
      self.class.field_layout.each do |name, _, _, _, var|
        out[name] = instance_variable_get(var)
      end
      out
    end
    alias_method :to_hash, :to_h

    def pretty_print(q) # :nodoc:
      q.group(4, "bitfield {", "}") do
        q.seplist(self.class.field_layout, -> { q.breakable("") }) do |name, _|
          q.text(".#{name} = ")
          q.pp(instance_variable_get(:"@#{name}"))
          q.text(", ")
        end
      end
    end
    alias_method :inspect, :pretty_inspect # :nodoc:

    # return the binary representation of this Bitfield instance
    # @return [::String] binary representation of struct
    def to_binstr(endian: self.class.default_endian)
      self.class.pack(to_h, endian:)
    end

    # determine if this instance of the bitfield is equal to another instance
    #
    # @note this implementation also supports Hash equality through {to_h}
    def ==(other)
      case other
      when self.class
        self.class.field_layout.all? do |name, _, _, _, var|
          instance_variable_get(var) == other[name]
        end
      when Hash
        other == to_h
      else
        super
      end
    end
  end
end

require_relative "bitfield/builder"
