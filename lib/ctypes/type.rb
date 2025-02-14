# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # interface for all supported types
  module Type
    # @api private
    # Dry::Type used for constraint checking & defaults
    attr_reader :dry_type

    # endian to use when packing/unpacking.
    # nil means {CTypes.default_endian} will be used.
    # @see #with_endian #with_endian to create fixed-endian types
    attr_reader :endian

    # encode a ruby type into a String containing the binary representation of
    # the c type
    #
    # @param value value to be encoded
    # @param endian [Symbol] endian to pack with
    # @param validate [Boolean] set to false to disable value validation
    # @return [::String] binary encoding for value
    # @see Int#pack
    # @see Struct#pack
    # @see Union#pack
    # @see Array#pack
    # @see String#pack
    # @see Terminated#pack
    def pack(value, endian: default_endian, validate: true)
      raise NotImplementedError
    end

    # convert a String containing the binary represention of a c type into the
    # equivalent ruby type
    #
    # @param buf [::String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return decoded type
    #
    # @see Type#unpack_one
    # @see Int#unpack_one
    # @see Struct#unpack_one
    # @see Union#unpack_one
    # @see Array#unpack_one
    # @see String#unpack_one
    # @see Terminated#unpack_one
    def unpack(buf, endian: default_endian)
      o, = unpack_one(buf, endian:)
      o
    end

    # convert a String containing the binary represention of a c type into the
    # equivalent ruby type
    #
    # @param buf [String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return [Array(Object, ::String)] decoded type, and remaining bytes
    #
    # @see Type#unpack
    # @see Int#unpack_one
    # @see Struct#unpack_one
    # @see Union#unpack_one
    # @see Array#unpack_one
    # @see String#unpack_one
    # @see Terminated#unpack_one
    def unpack_one(buf, endian: default_endian)
      raise NotImplementedError
    end

    # unpack as many instances of Type are present in the supplied string
    #
    # @param buf [String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return Array(Object) decoded types, and remaining
    def unpack_all(buf, endian: default_endian)
      out = []
      until buf.empty?
        t, buf = unpack_one(buf, endian:)
        out << t
      end
      out
    end

    # read a fixed-sized type from an IO instance and unpack it
    #
    # @param buf [::String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return decoded type
    def read(io, endian: default_endian)
      unless fixed_size?
        raise NotImplementedError,
          "read() does not support variable-length types"
      end

      unpack(io.read(@size), endian: default_endian)
    end

    # read a fixed-sized type from an IO instance at a specific offset and
    # unpack it
    #
    # @param buf [::String] bytes that make up the type
    # @param pos [::Integer] seek position
    # @param endian [Symbol] endian of data within buf
    # @return decoded type
    def pread(io, pos, endian: default_endian)
      unless fixed_size?
        raise NotImplementedError,
          "pread() does not support variable-length types"
      end

      unpack(io.pread(@size, pos), endian: default_endian)
    end

    # get a fixed-endian instance of this type.
    #
    # If a type has a fixed endian, it will override the default endian set
    # with {CTypes.default_endian=}.
    #
    # @param value [Symbol] endian; `:big` or `:little`
    # @return [Type] fixed-endian {Type}
    #
    # @example uint32_t
    #   t = CTypes::UInt32
    #   t.pack(1)                 # => "\1\0\0\0"
    #   b = t.with_endian(:big)
    #   b.pack(1)                 # => "\0\0\0\1"
    #   l = t.with_endian(:little)
    #   l.pack(1)                 # => "\1\0\0\0"
    #
    # @example array
    #   include Ctype::Helpers
    #   t = array(uint32, 2)
    #   t.pack([1,2])             # => "\1\0\0\0\2\0\0\0"
    #   b = t.with_endian(:big)
    #   b.pack([1,2])             # => "\0\0\0\1\0\0\0\2"
    #   l = t.with_endian(:little)
    #   l.pack([1,2])             # => "\1\0\0\0\2\0\0\0"
    #
    # @example struct with mixed endian fields
    #   include Ctype::Helpers
    #   t = struct do
    #     attribute native: uint32
    #     attribute big: uint32.with_endian(:big)
    #     attribute little: uint32.with_endian(:little)
    #   end
    #   t.pack({native: 1, big: 2, little: 3}) # => "\1\0\0\0\0\0\0\2\3\0\0\0"
    def with_endian(value)
      return self if value == @endian

      endian = Endian[value]
      @with_endian ||= {}
      @with_endian[endian] ||= begin
        o = clone
        o.instance_variable_set(:@without_endian, self) unless @endian
        o.instance_variable_set(:@endian, endian)
        o
      end
    end

    def without_endian
      @without_endian ||= begin
        o = clone
        o.remove_instance_variable(:@endian)
        o
      end
    end

    def greedy?
      raise NotImplementedError, "Type must implement `.greedy?`: %p" % [self]
    end

    # check if this is a fixed-size type
    def fixed_size?
      !!@size&.is_a?(Integer)
    end

    # @api private
    def default_value
      dry_type[]
    end

    # @api private
    def default_endian
      @endian || CTypes.default_endian
    end

    private

    def missing_bytes_error(input:, need:)
      MissingBytesError.new(type: self, input:, need:)
    end
  end
end
