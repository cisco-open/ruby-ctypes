# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # {Union} layout builder
  #
  # This class is used to describe the memory layout of a {Union} type. There
  # are two approaches available for defining the layout, the declaritive
  # approach used in ruby source files, or a programmatic approach that enables
  # the construction of {Union} types from data.
  #
  # @example declaritive approach using CTypes::Union
  #   class MyUnion < CTypes::Union
  #     layout do
  #       # this message uses network-byte order
  #       endian :big
  #
  #       # TLV message header with some fixed types
  #       header = struct(
  #         msg_type: enum(uint8, {invalid: 0, hello: 1, read: 2}),
  #         len: uint16)
  #
  #       # add header as an unnamed field; adds MyUnion#type, MyUnion#len
  #       member header
  #
  #       member :hello, struct(header:, version: string)
  #       member :read, struct(header:, offset: uint64, size: uint64)
  #       member :raw, string(trim: false)
  #
  #       # dynamic size based on the len in header
  #       size { |union| header.size + union[:len] }
  #     end
  #   end
  #
  # @example programmatic approach building a union from data
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
  #   b = CTypes::Union.builder          # => #<CTypes::Union::Builder ...>
  #
  #   # populate the fields in the builder
  #   fields.each do |field|
  #     b.member(field[:name], field[:type])
  #   end
  #
  #   # build the Union type
  #   t = b.build                         # => #<CTypes::Union ...>
  class Union::Builder
    include Helpers

    def initialize(type_lookup: CTypes.type_lookup)
      @type_lookup = type_lookup
      @fields = []
      @field_names = Set.new
      @schema = []
      @size = 0
      @fixed_size = true
    end

    # build a {Union} instance with the layout configured in this builder
    # @return [Union] bitfield with the layout defined in this builder
    def build
      k = Class.new(Union)
      k.send(:apply_layout, self)
      k
    end

    # @api private
    def result
      dry_type = Dry::Types["coercible.hash"]
        .schema(@schema)
        .strict
        .default(@default.freeze)
      [@name, @fields.freeze, dry_type, @size, @fixed_size, @endian]
    end

    # set the name of this union for use in pretty-printing
    def name(value)
      @name = value.dup.freeze
      self
    end

    # set the endian of this union
    def endian(value)
      @endian = Endian[value]
      self
    end

    # declare a member in the union
    # @param name name of the member
    # @param type [CTypes::Type] type of the field
    #
    # This function supports the use of {Struct} and {Union} types for
    # declaring unnamed fields (ISO C11).  See example below for more details.
    #
    # @example declare named union members
    #   member(:word, uint32)
    #   member(:bytes, array(uint8, 4))
    #   member(:half_words, array(uint16, 2))
    #   member(:header, struct(type: uint16, len: uint16))
    #
    # @example add an unnamed field (ISO C11)
    #   include CTypes::Helpers
    #
    #   # declare the type to be used in the unnamed field
    #   header = struct(id: uint32, len: uint32)
    #
    #   # create our union type with an unnamed field
    #   t = union do
    #     # add the unnamed field, in this case the header type
    #     member header
    #     member :raw, string
    #     size { |union| header.size + union.len }
    #   end
    #
    #   # now unpack an instance of the union type
    #   packet = t.unpack("\x01\0\0\0\x13\0\0\0hello worldXXX")
    #
    #   # access the unnamed field attributes
    #   p.id    # => 1
    #   p.len   # => 19
    def member(name, type = nil)
      # named field
      if type
        name = name.to_sym
        @fields << [name, type].freeze
        @field_names << name
        @schema << Dry::Types::Schema::Key
          .new(type.dry_type.type, name, required: false)
        @default ||= {name => type.default_value}

      # unnamed field
      else
        type = name
        dry_keys = type.dry_type.keys or
          raise Error, "unsupported type for unnamed field: %p" % [type]
        names = dry_keys.map(&:name)

        if (duplicate = names.any? { |n| @field_names.include?(n) })
          raise Error, "duplicate field name %p in unnamed field: %p" %
            [duplicate, type]
        end

        @fields << [names, type].freeze
        @field_names += names
        @schema += dry_keys.map do |key|
          # for all of the keys in the type, we need to create an equivalent
          # Key where the key is omittable.
          #
          # note: we strip the default value off the dry type here when defining
          # the schema for our own dry type.  If we do not do this, `dry_type[{}]`
          # has every member in it, resulting in "only one member" error being
          # raised in Union.pack when the union is nested within a struct.
          #
          # Example:
          #   struct(id: uint8, value: union(byte: uint8, word: uint32))
          #     .pack({value: byte: 1})
          Dry::Types::Schema::Key.new(key.type.type, key.name, required: false)
        end

        @default ||= type.default_value
      end

      # fix up the size
      @size = type.size if @size.is_a?(Integer) && type.size > @size
      @fixed_size &&= type.fixed_size?
      self
    end

    # Add a proc for determining Union size based on decoded bytes
    # @param block block will be called to determine struct size in bytes
    #
    # When unpacking a variable length {Union}, the size proc is passed a
    # frozen {Union} instance with the entire input buffer.  The size proc will
    # then unpack only those members it needs to calculate the total union
    # size, and return the union size in bytes.
    #
    # @example variable length type-length-value (TLV) union
    #   CTypes::Helpers.struct do
    #     # TLV message header with some fixed types
    #     header = struct(
    #       msg_type: enum(uint8, {invalid: 0, hello: 1, read: 2}),
    #       len: uint16)
    #
    #     member :header, header
    #     member :hello, struct(header:, version: string)
    #     member :read, struct(header:, offset: uint64, size: uint64)
    #     member :raw, string(trim: false)
    #
    #     # the header#len field contains the length of the remaining union
    #     # bytes after the header.  So we add the header size, and the value
    #     # in header.len to get the total union size.
    #     size { |union| header.size + union.header.len }
    #   end
    def size(&block)
      @fixed_size = false
      @size = block
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
