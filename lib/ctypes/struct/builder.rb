# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # {Struct} layout builder
  #
  # This class is used to describe the memory layout of a {Struct} type.
  # There are two approaches available for defining the layout, the
  # declaritive approach used in ruby source files, or a programmatic
  # approach that enables the construction of {Struct} types from data.
  #
  # @example declaritive approach using CTypes::Struct
  #   class MyStruct < CTypes::Struct
  #     layout do
  #       # the code in this block is evaluated within a Builder instance
  #
  #       # add a struct name for use in pretty-printing
  #       name "struct my_struct"
  #
  #       # set the endian if needed
  #       endian :big
  #
  #       # add attributes
  #       attribute :id, uint32           # 32-bit unsigned int identifier
  #       attribute :name, string(256)    # name that takes up to 256 bytes
  #
  #       # add an array of four 64-bit unsigned integers
  #       attribute :values, array(uint64, 4)
  #
  #       # Append a variable length member to the end of the structure.
  #       attribute :tail_len, uint32
  #       attribute :tail, string
  #       size { |struct| offsetof(:tail) + struct[:tail_len] }
  #     end
  #   end
  #
  # @example programmatic approach
  #   # include helpers for `uint32`, `string`, and `array` methods
  #   include CTypes::Helpers
  #
  #   # data loaded from elsewhere
  #   fields = [
  #     {name: :id, type: uin32},
  #     {name: :name, type: string(256)},
  #   ]
  #
  #   # create a builder instance
  #   b = CTypes::Struct.builder          # => #<CTypes::Struct::Builder ...>
  #
  #   # populate the fields in the builder
  #   fields.each do |field|
  #     b.attribute(field[:name], field[:type])
  #   end
  #
  #   # build the Struct type
  #   t = b.build                         # => #<CTypes::Struct ...>
  #
  class Struct::Builder
    include Helpers

    def initialize(type_lookup: CTypes.type_lookup)
      @type_lookup = type_lookup
      @fields = []
      @schema = []
      @default = {}
      @bytes = 0
    end

    # build a {Struct} instance with the layout configured in this builder
    # @return [Struct] bitfield with the layout defined in this builder
    def build
      k = Class.new(Struct)
      k.send(:apply_layout, self)
      k
    end

    # get the layout description for internal use in {Struct}
    # @api private
    def result
      dry_type = Dry::Types["coercible.hash"]
        .schema(@schema)
        .strict
        .default(@default.freeze)
      [@name, @fields.freeze, dry_type, @size || @bytes, @endian]
    end

    # set the name of this structure for use in pretty-printing
    def name(value)
      @name = value.dup.freeze
      self
    end

    # set the endian of this structure
    def endian(value)
      @endian = Endian[value]
      self
    end

    # declare an attribute in the structure
    # @param name name of the attribute, optional for unnamed fields
    # @param type [CTypes::Type] type of the field
    #
    # This function supports the use of {Struct} and {Union} types for
    # declaring unnamed fields (ISO C11).  See example below for more details.
    #
    # @example
    #   attribute(:name, string)
    #
    # @example add an attribute with a struct type
    #   include CTypes::Helpers
    #   attribute(:header, struct(id: uint32, len: uint32))
    #
    # @example add an unnamed field (ISO C11)
    #   include CTypes::Helpers
    #
    #   # declare the type to be used in the unnamed field
    #   header = struct(id: uint32, len: uint32)
    #
    #   # create our struct type with an unnamed field
    #   t = struct do
    #     # add the unnamed field, in this case the header type
    #     attribute(header)
    #
    #     # add any other field needed in the struct
    #     attribute(:body, string)
    #     size { |struct| struct[:len] }
    #   end
    #
    #   # now unpack an instance of the struct type
    #   packet = t.unpack("\x01\0\0\0\x13\0\0\0hello worldXXX")
    #
    #   # access the unnamed struct fields directly by the inner names
    #   p.id    # => 1
    #   p.len   # => 19
    #
    #   # access the body
    #   p.body  # => "hello world"
    #
    def attribute(name, type = nil)
      # handle a named field
      if type
        name = name.to_sym
        if @default.has_key?(name)
          raise Error, "duplicate field name: %p" % name
        end

        @fields << [name, type]
        @schema << Dry::Types::Schema::Key.new(type.dry_type, name)
        @default[name] = type.default_value

      # handle the unnamed field by adding the child fields to our type
      else
        type = name
        dry_keys = type.dry_type.keys or
          raise Error, "unsupported type for unnamed field: %p" % [type]
        names = dry_keys.map(&:name)

        if (duplicate = names.any? { |n| @default.has_key?(n) })
          raise Error, "duplicate field name %p in unnamed field: %p" %
            [duplicate, type]
        end

        @fields << [names, type]
        @schema += dry_keys
        @default.merge!(type.default_value)
      end

      # adjust the byte count for this type
      if @bytes && type.fixed_size?
        @bytes += type.size
      else
        @bytes = nil
      end

      self
    end

    # Add a proc for determining struct size based on decoded bytes
    # @param block block will be called to determine struct size in bytes
    #
    # When unpacking variable length {Struct}s, we unpack each attribute in
    # order of declaration until we encounter a field that has a
    # variable-length type.  At that point, we call the block provided to
    # {Builder#size} do determine the total size of the struct.  The block
    # will receive a single argument, which is an incomplete unpacking of the
    # {Struct}, containing only those fixed-length fields that have been
    # unpacked so far.  The block can access unpacked fields using
    # {Struct#[]}.  Using the unpacked fields, the block must return the total
    # size of the struct in bytes.
    #
    # @example type-length-value (TLV) struct with variable length
    #   CTypes::Helpers.struct do
    #     attribute :type, enum(uint8, %i[hello read write bye])
    #     attribute :len, uint16.with_endian(:big)
    #     attribute :value, string
    #
    #     # The :len field contains the length of :value.  So we add a size
    #     # proc that takes the offset of :value within the struct (3 bytes),
    #     # and adds the value of the :len field.  Note that
    #     size { |struct| offsetof(:value) + struct[:len] }
    #   end
    def size(&block)
      @size = block
      self
    end

    # allocate unused bytes in the {Struct}
    # @param bytes [Integer] number of bytes to pad
    #
    # This method is used to enforce alignment of other fields, or accurately
    # mimic padding added in C structs by the compiler.
    #
    # @example
    #   CTypes::Helpers.struct do
    #     attribute :id, uint16       # 16-bit integer taking up two bytes
    #     pad 2                       # pad two bytes (16-bits) to align value
    #     attribute :value, uint32    # value aligned at 4-byte boundary
    #   end
    def pad(bytes)
      pad = Pad.new(bytes)

      # we use the Pad instance as the name of the field so Struct knows to
      # treat the field as padding
      @fields << [pad, pad]
      @bytes += bytes if @bytes

      self
    end

    # used for custom type resolution
    # @see CTypes.using_type_lookup
    def method_missing(name, *args, &block)
      if @type_lookup && args.empty? && block.nil?
        type = @type_lookup.call(name)
        return type if type
      end
      super
    end
  end
end
