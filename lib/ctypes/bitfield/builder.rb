# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # {Bitfield} layout builder
  #
  # This class is used to describe the memory layout of a {Bitfield} type.
  # There are two approaches provided here for describing the layout, the first
  # is a constructive interface using {Builder#unsigned}, {Builder#signed},
  # {Builder#align}, and {Builder#skip}, to build the bitfield from
  # right-to-left.  These methods track how many bits have been used, and
  # automatically determine the offset of fields as they're declared.
  #
  # The second interface is the programmatic interface that can be used to
  # generate the {Bitfield} layout from data.  This uses {Builder#field} to
  # explicitly declare fields using bit size, offset, and signedness.
  #
  # @example using the constructive interface via {CTypes::Bitfield#layout}
  #   class MyBits < CTypes::Bitfield
  #     layout do
  #       # the body of this block is evaluated within a Builder instance
  #       unsigned :bit             # single bit for a at offset 0
  #       unsigned :two, 2          # two bits for this field at offset 1
  #       signed :nibble, 4         # four bit nibble as a signed int, offset 3
  #     end
  #   end
  #
  # @example using the programmatic interface via {CTypes::Bitfield#layout}
  #   class MyBits < CTypes::Bitfield
  #     layout do
  #       # the body of this block is evaluated within a Builder instance
  #       field :bit, size: 1, offset: 0      # single bit at offset 0
  #       field :two, size: 2, offset: 1      # two bits at offset 1
  #       field :nibble, size: 4, offset: 3   # four bits at offset 3
  #     end
  #   end
  #
  # @example construct {CTypes::Bitfield} programmatically
  #   b = CTypes::Bitfield.builder        # => #<CTypes::Bitfield::Builder>
  #   b.field(:one, bits: 1, offset: 0)   # one bit at offset 0, named :one
  #
  #   # Create additional fields from data loaded from elsewhere
  #   extra_fields = [
  #     [:two, 2, 1],                     # two bits for this field named :two
  #     [:nibble, 4, 3]                   # four bits for the :nibble field
  #   ]
  #   extra_fields.each do |name, bits, offset|
  #     b.field(name, bits:, offset:)
  #   end
  #
  #   # build the type
  #   t = b.build                         # => #<Bitfield ...>
  class Bitfield::Builder
    include Helpers

    def initialize
      @fields = []
      @schema = {}
      @default = {}
      @offset = 0
      @layout = []
      @max = 0
    end

    # get the offset of the next unused bit in the bitfield
    attr_reader :offset

    # build a {Bitfield} instance with the layout configured in this builder
    # @return [Bitfield] bitfield with the layout defined in this builder
    def build
      k = Class.new(Bitfield)
      k.send(:apply_layout, self)
      k
    end

    # get the layout description for internal use in {Bitfield}
    # @api private
    def result
      dry_type = Dry::Types["coercible.hash"]
        .schema(@schema)
        .strict
        .default(@default.freeze)

      type = case @max
      when 0..8
        UInt8
      when 9..16
        UInt16
      when 17..32
        UInt32
      when 32..64
        UInt64
      else
        raise Error, "bitfields greater than 64 bits not supported"
      end

      [type, @fields, dry_type, @endian, @layout]
    end

    # set the endian for this {Bitfield}
    # @param value [Symbol] `:big` or `:little`
    def endian(value)
      @endian = Endian[value]
      self
    end

    # skip `bits` bits in the layout of this bitfield
    # @param bits [Integer] number of bits to skip
    def skip(bits)
      raise Error, "cannot mix `#skip` and `#field` in Bitfield layout" unless
          @offset
      @offset += bits
      @max = @offset if @offset > @max
      @layout << "skip #{bits}"
      self
    end

    # set the alignment of the next field declared using {Builder#signed} or
    # {Builder#unsigned}
    # @param bits [Integer] bit alignment of the next field
    # @note {Builder#align} cannot be mixed with calls to {Builder#field}
    #
    # @example
    #   class MyBits < CTypes::Bitfield
    #     layout do
    #       unsigned :a       # single bit at offset 0
    #       align 4
    #       unsigned :b, 2    # two bits at offset 4
    #       align 4
    #       unsigned :c       # single bit at offset 8
    #     end
    #   end
    #
    def align(bits)
      raise Error, "cannot mix `#align` and `#field` in Bitfield layout" unless
          @offset
      @offset += bits - (@offset % bits)
      @layout << "align #{bits}"
      self
    end

    # append a new unsigned field to the bitfield
    # @param name [String, Symbol] name of the field
    # @param bits [Integer] number of bits
    def unsigned(name, bits = 1)
      unless @offset
        raise Error,
          "cannot mix `#unsigned` and `#field` in Bitfield layout"
      end

      name = name.to_sym
      raise Error, "duplicate field: %p" % [name] if
          @fields.any? { |(n, _)| n == name }

      @layout << ((bits == 1) ?
          "unsigned %p" % [name] :
          "unsigned %p, %d" % [name, bits])

      __field_impl(name:, bits:, offset: @offset, signed: false)
      @offset += bits
      self
    end

    # append a new signed field to the bitfield
    # @param name [String, Symbol] name of the field
    # @param bits [Integer] number of bits
    def signed(name, bits = 1)
      unless @offset
        raise Error,
          "cannot mix `#signed` and `#field` in Bitfield layout"
      end

      name = name.to_sym
      raise Error, "duplicate field: %p" % [name] if
          @fields.any? { |(n, _)| n == name }

      @layout << ((bits == 1) ?
          "signed %p" % [name] :
          "signed %p, %d" % [name, bits])

      __field_impl(name:, bits:, offset: @offset, signed: true)
      @offset += bits
      self
    end

    # set the size of the {Bitfield} in bytes
    #
    # Once the size is set, the Bitfield cannot grow past that size.  Any calls
    # to {Builder#signed} or {Builder#unsigned} that go beyond the size will
    # raise errors.
    #
    # @param n [Integer] size in bytes
    def bytes(n)
      @layout << "bytes #{n}"
      @max = n * 8
      self
    end

    # declare a bit field at a specific offset
    # @param name [String, Symbol] name of the field
    # @param offset [Integer] right to left bit offset, where 0 is the least
    #   significant bit in a byte
    # @param bits [Integer] number of bits used by this bitfield
    # @param signed [Boolean] set to true to unpack as a signed integer
    #
    # This method is an alternative the construtive interface provided by
    # {Builder#skip}, {Builder#align},
    # {Builder#unsigned}, and {Builder#signed}.  This is a programmatic
    # interface for explicitly declaring fields using offset & bitcount.
    #
    # @note This method should not be used in combination with
    # {Builder#skip}, {Builder#align}, {Builder#unsigned}, {Builder#signed}.
    def field(name, offset:, bits:, signed: false)
      name = name.to_sym
      raise Error, "duplicate field: %p" % [name] if
          @fields.any? { |(n, _)| n == name }

      @layout << "field %p, offset: %d, bits: %d, signed: %p" %
        [name, offset, bits, signed]
      @offset = nil

      __field_impl(name:, offset:, bits:, signed:)
      self
    end

    private

    # @api private
    def __field_impl(name:, offset:, bits:, signed:) # :nodoc:
      mask = (1 << bits) - 1

      schema = Dry::Types["integer"].default(0)
      @schema[name] = if signed
        schema.constrained(gteq: 0 - (1 << (bits - 1)), lt: 1 << (bits - 1))
      else
        schema.constrained(gteq: 0, lt: 1 << bits)
      end
      @default[name] = 0

      @fields << [name, offset, mask, signed ? bits : nil, :"@#{name}"]
      @max = offset + bits if offset + bits > @max
    end
  end
end
