# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # This class is used to represent c structures in ruby.  It provides methods
  # for converting structs between their byte representation and a ruby
  # representation that can be modified.
  #
  # @note fields are not automatically aligned based on size; if there are gaps
  #   present between c struct fields, you'll need to manually add padding in
  #   the layout to reflect that alignment.
  #
  # @example working with a Type-Length-Value (TLV) struct
  #   # encoding: ASCII-8BIT
  #
  #   # subclass Struct to define a structure
  #   class TLV < CTypes::Struct
  #     # define structure layout
  #     layout do
  #       attribute :type, enum(uint8, %i[hello read write bye])
  #       attribute :len, uint16.with_endian(:big)
  #       attribute :value, string
  #       size { |struct| offsetof(:value) + struct[:len] }
  #     end
  #
  #     # add any class or instance methods if needed
  #   end
  #
  #   # pack the struct into bytes
  #   bytes = TLV.pack({type: :hello, len: 5, value: "world"})
  #                         # => "\0\0\5world"
  #
  #   # unpack bytes into a struct instance
  #   t = TLV.unpack("\0\0\5world")
  #                         # => #<TLV type=:hello len=5 value="world">
  #
  #   # access struct fields
  #   t.value               # => "world"
  #
  #   # update struct fields, then convert back into bytes
  #   t.type = :bye
  #   t.value = "goodbye"
  #   t.len = t.value.size
  #   t.to_binstr           # => "\3\0\7goodbye"
  #
  # @example nested structs
  #   class Attribute < CTypes::Struct
  #     layout do
  #       attribute :base, uint8
  #       attribute :mod, int8
  #     end
  #   end
  #   class Character < CTypes::Struct
  #     layout do
  #       attribute :str, Attribute
  #       attribute :int, Attribute
  #       attribute :wis, Attribute
  #       attribute :dex, Attribute
  #       attribute :con, Attribute
  #     end
  #   end
  #
  #   ch = Character.new
  #   ch.str.base = 18
  #   ch.int.base = 8
  #   ch.wis.base = 3
  #   ch.dex.base = 13
  #   ch.con.base = 16
  #   ch.to_binstr        # => "\x12\x00\x08\x00\x03\x00\x0d\x00\x10\x00"
  #   ch.str.mod -= 3
  #   ch.to_binstr        # => "\x12\xFD\x08\x00\x03\x00\x0d\x00\x10\x00"
  #
  class Struct
    extend Type
    using PrettyPrintHelpers

    def self.builder
      Builder.new
    end

    # define the layout for this structure
    # @see Builder
    #
    # @example type-length-value (TLV) struct
    #   class TLV < CTypes::Struct
    #     layout do
    #       attribute :type, uint16
    #       attribute :len, uint16
    #       attribute :value, string
    #       size { |s| offsetof(:len) + s.len }
    #     end
    #   end
    def self.layout(&block)
      raise Error, "no block given" unless block
      builder = Builder.new
      builder.instance_eval(&block)
      apply_layout(builder)
    end

    def self.apply_layout(builder) # :nodoc:
      # reset the state of the struct
      @offsets = nil
      @greedy = false

      @name, @fields, @dry_type, @size, @endian = builder.result

      @field_accessors ||= {}
      remove_method(*@field_accessors.values.flatten)
      @field_accessors.clear

      @fields.each do |name, type|
        # the struct will be flagged as greedy if size is not defined by a
        # Proc, and the field type is greedy
        @greedy ||= type.greedy? unless @size.is_a?(Proc)

        case name
        when Symbol
          @field_accessors[name] = attr_accessor(name)
        when ::Array
          name.each { |n| @field_accessors[n] = attr_accessor(n) }
        when Pad
          # no op
        else
          raise Error, "unsupported field name type: %p", name
        end
      end
    end
    private_class_method :apply_layout

    # encode a ruby Hash into a String containing the binary representation of
    # the c type
    #
    # @param value [Hash] value to be encoded
    # @param endian [Symbol] endian to pack with
    # @param validate [Boolean] set to false to disable value validation
    # @return [::String] binary encoding for value
    #
    # @example pack with default values
    #   include CTypes::Helpers
    #   t = struct(id: uint32, value: uint32)
    #   t.pack({})  # => "\0\0\0\0\0\0\0\0"
    #
    # @example pack with some fields
    #   include CTypes::Helpers
    #   t = struct(id: uint32, value: uint32)
    #   t.pack({value: 0xfefefefe})  # => "\x00\x00\x00\x00\xfe\xfe\xfe\xfe"
    #
    # @example pack with all fields
    #   include CTypes::Helpers
    #   t = struct(id: uint32, value: uint32)
    #   t.pack({id: 1, value: 2})  # => "\1\0\0\0\2\0\0\0"
    #
    # @example pack with nested struct
    #   include CTypes::Helpers
    #   t = struct do
    #     attribute :id, uint32
    #     attribute :a, struct(base: uint8, mod: uint8)
    #   end
    #   t.pack({id: 1, a: {base: 2, mod: 3}}) # => "\1\0\0\0\2\3"
    #
    def self.pack(value, endian: default_endian, validate: true)
      value = value.to_hash.freeze
      value = @dry_type[value] unless validate == false
      buf = ::String.new
      @fields.each do |(name, type)|
        case name
        when Pad
          buf << type.pack(nil)
        when Symbol
          buf << type.pack(value[name],
            endian: type.endian || endian,
            validate: false)
        when ::Array
          buf << type.pack(value.slice(*name),
            endian: type.endian || endian,
            validate: false)
        else
          raise Error, "unsupported field name type: %p" % [name]
        end
      end

      return buf if fixed_size? || @size.nil?

      size = instance_exec(value, &@size)
      if size > buf.size
        buf << "\0" * (size - buf.size)
      elsif size < buf.size
        buf[0, size]
      else
        buf
      end
    end

    # convert a String containing the binary represention of a c struct into
    # a ruby type
    #
    # @param buf [String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return [::Array(Struct, ::String)] decoded struct, and remaining bytes
    #
    # @see Type#unpack
    #
    # @example
    #   class TLV < CTypes::Struct
    #     layout do
    #       attribute :type, enum(uint8, %i[hello, read, write, bye])
    #       attribute :len, uint16.with_endian(:big)
    #       attribute :value, string
    #       size { |struct| offsetof(:value) + struct[:len] }
    #     end
    #   end
    #   TLV.unpack_one("\0\0\5helloextra")
    #       # => [#<TLV type=:hello len=5 value="hello">, "extra"]
    #
    def self.unpack_one(buf, endian: default_endian)
      rest = buf
      trimmed = nil # set to the unused portion of buf when we have @size
      out = _new    # output structure instance
      out.instance_variable_set(:@endian, endian)

      @fields.each do |(name, type)|
        # if the type is greedy, and we have a dynamic size, and we haven't
        # already trimmed the input buffer, let's do so now.
        #
        # note: we do this while unpacking because the @size proc may require
        # some of the unpacked fields to determine the size of the struct such
        # as in TLV structs
        if type.greedy? && @size && !trimmed

          # caluclate the total size of the struct from the decoded fields
          size = instance_exec(out, &@size)
          raise missing_bytes_error(input: buf, need: size) if
            size > buf.size

          # adjust the size for how much we've already unpacked
          size -= offsetof(name.is_a?(Array) ? name[0] : name)

          # split the remaining buffer; we stick the part we aren't going to
          # use in trimmed, and update rest to point at our buffer
          trimmed = rest.byteslice(size..)
          rest = rest.byteslice(0, size)
        end

        value, rest = type.unpack_one(rest, endian: type.endian || endian)
        case name
        when Symbol
          out[name] = value
        when ::Array
          name.each { |n| out[n] = value[n] }
        when Pad
          # no op
        else
          raise Error, "unsupported field name type: %p" % [name]
        end
      end

      [out, trimmed || rest]
    end

    # get the offset of a field within the structure in bytes
    #
    # @param attr [Symbol] name of the attribute
    # @return [Integer] byte offset
    def self.offsetof(attr)
      @offsets ||= @fields.inject([0, {}]) do |(offset, o), (key, type)|
        o[key] = offset
        [type.size ? offset + type.size : nil, o]
      end.last

      @offsets[attr]
    end

    # check if this type is greedy
    #
    # @api private
    def self.greedy?
      @greedy
    end

    # get the minimum size of the structure
    #
    # For fixed-size structures, this will return the size of the structure.
    # For dynamic length structures, this will return the minimum size of the
    # structure
    #
    # @return [Integer] structure size in bytes
    def self.size
      return @size if @size.is_a?(Integer)

      @min_size ||= @fields&.inject(0) { |s, (_, t)| s + t.size } || 0
    end

    # check if the struct has a given attribute
    # @param k [Symbol] attribute name
    def self.has_field?(k)
      @field_accessors.has_key?(k)
    end

    # return the list of fields in this structure
    # @api.private
    def self.fields
      @field_accessors.keys
    end

    # return the list of fields with their associated types
    # @api.private
    def self.field_layout
      @fields
    end

    # return the struct name if supplied
    # @api.private
    def self.type_name
      @name
    end

    def self.pretty_print(q) # :nodoc:
      q.ctype("struct", @endian) do
        q.line("name %p" % [@name]) if @name
        q.seplist(@fields, -> { q.breakable(";") }) do |name, type|
          case name
          when Symbol
            q.text("attribute %p, " % name)
            q.pp(type)
          when ::Array
            q.text("attribute ")
            q.pp(type)
          when Pad
            q.pp(type)
          else
            raise Error, "unsupported field name type: %p" % [name]
          end
        end
      end
    end

    # @api.private
    def self.export_type(q)
      q << "CTypes::Struct.builder()"
      q.break
      q.nest(2) do
        q << ".name(%p)\n" % [@name] if @name
        q << ".endian(%p)\n" % [@endian] if @endian
        @fields.each do |name, type|
          case name
          when Symbol
            q << ".attribute(%p, " % [name]
            q << type
            q << ")"
            q.break
          when ::Array
            q << ".attribute("
            q << type
            q << ")"
            q.break
          when Pad
            q << type
            q.break
          else
            raise Error, "unsupported field name type: %p" % [name]
          end
        end
        q << ".build()"
      end
    end

    class << self
      alias_method :inspect, :pretty_inspect # :nodoc:

      # @method _new
      # allocate an uninitialized instance of the struct
      # @return [Struct] uninitialized struct instance
      # @api private
      alias_method :_new, :new
      private :_new
    end

    # allocate an instance of the Struct and initialize default values
    # @param fields [Hash] values to set
    # @return [Struct]
    def self.new(fields = nil)
      buf = fields.nil? ? ("\0" * size) : pack(fields)
      unpack(buf)
    end

    # check if another Struct subclass has the same attributes as this Struct
    # @note this method does not handle dynamic sized Structs correctly, but
    #   the current implementation is sufficient for testing
    def self.==(other)
      return true if super
      return false unless other.is_a?(Class) && other < Struct
      other.field_layout == @fields &&
        other.default_endian == default_endian &&
        other.size == size
    end

    # set an attribute value
    # @param k [Symbol] attribute name
    # @param v value
    #
    # @example
    #   include CTypes::Helpers
    #   t = struct(id: uint32, value: uint32)
    #   i = t.new
    #   i[:id] = 12
    #   i.id            # => 12
    #   i.id = 55
    #   i.id            # => 55
    def []=(k, v)
      has_attribute!(k)
      instance_variable_set(:"@#{k}", v)
    end

    # get an attribute value
    # @param k [Symbol] attribute name
    # @return value
    #
    # @example
    #   include CTypes::Helpers
    #   t = struct(id: uint32, value: uint32)
    #   i = t.new
    #   i[:value] = 123
    #   i[:value]                   # => 123
    def [](k)
      has_attribute!(k)
      instance_variable_get(:"@#{k}")
    end

    # check if the {Struct} has a specific attribute name
    def has_key?(name)
      self.class.has_field?(name)
    end

    # raise an exception unless {Struct} includes a specific attribute name
    def has_attribute!(name)
      raise UnknownAttributeError, "unknown attribute: %p" % name unless
        self.class.has_field?(name)
    end
    private :has_attribute!

    # return a Hash representation of the data type
    # @param shallow [Boolean] set to true to disable deep traversal
    # @return [Hash]
    #
    # @example deep
    #   include CTypes::Helpers
    #   t = struct do
    #     attribute :inner, struct(value: uint8)
    #   end
    #   i = t.new
    #   i.inner.value = 5
    #   i.to_h                      # => {inner: {value: 5}}
    #
    # @example shallow
    #   include CTypes::Helpers
    #   t = struct do
    #     attribute :inner, struct(value: uint8)
    #   end
    #   i = t.new
    #   i.inner.value = 5
    #   i.to_h(shallow: true)       # => {inner: #<Class:0x646456 value=5>}
    def to_h(shallow: false)
      out = {}
      self.class.fields.each do |field|
        value = send(field)
        unless shallow || value.is_a?(::Array) || !value.respond_to?(:to_h)
          value = value.to_h
        end
        out[field] = value
      end
      out
    end
    alias_method :to_hash, :to_h

    # return the binary representation of this Struct instance
    # @return [String] binary representation of struct
    #
    # @example
    #   include CTypes::Helpers
    #   t = struct(id: uint32, value: string)
    #   i = t.new
    #   i.id = 1
    #   i.value = "hello"
    #   i.to_binstr               # => "\1\0\0\0hello"
    def to_binstr(endian: @endian)
      self.class.pack(to_h, endian:)
    end

    # determine if this instance of the struct is equal to another instance
    #
    # @note this implementation also supports Hash equality through {to_h}
    def ==(other)
      case other
      when self.class
        self.class.field_layout.all? do |field, _|
          instance_variable_get(:"@#{field}") == other[field]
        end
      when Hash
        other == to_h
      else
        super
      end
    end

    def pretty_print(q) # :nodoc:
      open = if (name = self.class.type_name || self.class.name)
        "struct #{name} {"
      else
        "struct {"
      end
      q.group(4, open, "}") do
        q.seplist(self.class.field_layout, -> { q.breakable("") }) do |name, _|
          names = name.is_a?(::Array) ? name : [name]
          names.each do |name|
            q.text(".#{name} = ")
            q.pp(instance_variable_get(:"@#{name}"))
            q.text(", ")
          end
        end
      end
    end
    alias_method :inspect, :pretty_inspect # :nodoc:
  end
end

require_relative "struct/builder"
