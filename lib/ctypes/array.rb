# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # @example array of unsigned 32-bit integers
  #   t = CTypes::Array.new(type: CTypes::Helpers.uint32)
  #   t.unpack("\xaa\xaa\xaa\xaa\xbb\xbb\xbb\xbb")
  #                                     # => [0xaaaaaaaa, 0xbbbbbbbb]
  #   t.pack([0,0xffffffff])            # => "\0\0\0\0\xff\xff\xff\xff"
  #
  # @example array of signed 8-bit integers
  #   t = CTypes::Array.new(type: CTypes::Helpers.int8)
  #   t.unpack("\x01\x02\x03\x04")      # => [1, 2, 3, 4]
  #   t.pack([1, 2, 3, 4])              # => "\x01\x02\x03\x04"
  #
  # @example fixed-size array of 8-bit integers
  #   t = CTypes::Array.new(type: CTypes::Helpers.int8, size: 2)
  #   t.unpack("\x01\x02\x03\x04")      # => [1, 2]
  #   t.pack([1, 2])                    # => "\x01\x02"
  #
  # @example terminated array of 8-bit integers
  #   t = CTypes::Array.new(type: CTypes::Helpers.int8, terminator: -1)
  #   t.unpack("\x01\xff\x03\x04")      # => [1]
  #   t.pack([1])                       # => "\x01\xff"
  #
  # @example array of structures
  #   include CTypes::Helpers
  #   s = struct do
  #     attribute :type, uint8
  #     attribute :value, uint8
  #   end
  #   t = array(s)
  #   t.unpack("\x01\x02\x03\x04")      # => [ { .type = 1, value = 2 },
  #                                     #      { .type = 3, value = 4 } ]
  #   t.pack([{type: 1, value: 2}, {type: 3, value: 4}])
  #                                     # => "\x01\x02\x03\x04"
  class Array
    include Type

    # TODO Add support for a pre-unpack terminator that checks against the
    # remaining buffer before calling unpack on inner type.  This allows easier
    # support for DWARF-type types (.debug_line file_names)

    # declare a new Array type
    # @param type [CTypes::Type] type contained within the array
    # @param size [Integer] number of elements in the array; nil means greedy
    #   unpack
    # @param terminator array value that denotes the end of the array; the
    #   value will not be appended in `unpack` results, but will be appended
    #   during `pack`
    def initialize(type:, size: nil, terminator: nil)
      raise Error, "cannot use terminator with fixed size array" if
        size && terminator
      raise Error, "cannot make an Array of variable-length Unions" if
        type.is_a?(Class) && type < Union && !type.fixed_size?

      @type = type
      @size = size
      if terminator
        @terminator = terminator
        @term_packed = @type.pack(terminator)
        @term_unpacked = @type.unpack(@term_packed)
      end

      @dry_type = Dry::Types["coercible.array"].of(type.dry_type)
      @dry_type = if size
        @dry_type.constrained(size:)
          .default { ::Array.new(size, type.dry_type[]) }
      else
        @dry_type.default([].freeze)
      end
    end
    attr_reader :type, :terminator

    # pack a ruby array into a binary string
    # @param value [::Array] array value to pack
    # @param endian [Symbol] optional endian override
    # @param validate [Boolean] set to false to disable value validation
    # @return [::String] binary string
    def pack(value, endian: default_endian, validate: true)
      value = @dry_type[value] if validate
      out = value.inject(::String.new) do |o, v|
        o << @type.pack(v, endian: @type.endian || endian)
      end
      out << @term_packed if @term_packed
      out
    rescue Dry::Types::ConstraintError
      raise unless @size && @size > value.size

      # value is short some elements; fill them in and retry
      value += ::Array.new(@size - value.size, @type.default_value)
      retry
    end

    # unpack an instance of an array from the beginning of the supplied binary
    # string
    # @param buf [::String] binary string
    # @param endian [Symbol] optional endian override
    # @return [Array(Object, ::String)] unpacked Array, unused bytes fron buf
    def unpack_one(buf, endian: default_endian)
      rest = buf
      if @size
        value = @size.times.map do |i|
          o, rest = @type.unpack_one(rest, endian: @type.endian || endian)
          o or raise missing_bytes_error(input: value,
            need: @size * @type.size)
        end
      else
        # handle variable-length array; both greedy and terminated
        value = []
        loop do
          if rest.empty?
            if @term_packed
              raise TerminatorNotFoundError,
                "terminator not found in: %p" % buf
            end
            break
          end

          v, rest = @type.unpack_one(rest, endian: @type.endian || endian)
          break if v === @term_unpacked
          value << v
        end
      end
      [value, rest]
    end

    # check if this Array is greedy
    def greedy?
      !@size && !@terminator
    end

    # return the size of the array if one is defined
    def size
      s = @size ? @size * @type.size : 0
      s += @term_packed.size if @term_packed
      s
    end

    def pretty_print(q) # :nodoc:
      q.group(1, "array(", ")") do
        q.pp(@type)
        if @size
          q.comma_breakable
          q.text(@size.to_s)
        end
        if @terminator
          q.comma_breakable
          q.text("terminator: #{@terminator}")
        end
      end
    end
    alias_method :inspect, :pretty_inspect # :nodoc:

    def export_type(q) # :nodoc:
      q << "array("
      q << @type
      q << ", #{@size}" if @size
      q << ", terminator: #{@terminator}" if @terminator
      q << ")"
      q << ".with_endian(%p)" % [@endian] if @endian
    end

    def type_name
      @size ?
        "%s[%s]" % [@type.type_name, @size] :
        "%s[]" % [@type.type_name]
    end

    def ==(other)
      return false unless other.is_a?(Array)
      other.type == @type &&
        other.size == size &&
        other.terminator == terminator
    end
  end
end
