# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # This class represents a C union in ruby.  It provides methods for unpacking
  # unions from their binary representation into a modifiable Ruby instance,
  # and methods for repacking them into binary.
  #
  # The ruby representation of a union does not get the same memory overlap
  # benefits as experienced in C.  As a result, the ruby {Union} must unpack
  # the binary string each time a different union member is accessed.  To
  # support modification, this also means every time we switch between union
  # members, any active union member must be packed into binary format, then
  # unpacked at the new member.  **This is a significant performance penalty
  # when working with read-write Unions.**
  #
  # To get arond the performance penalty, you can do one of the following:
  # - do not swap between multiple union members unless absolutely necessary
  # - {Union#freeze} the unpacked union instance to eliminate the repacking
  #   performance hit
  # - figure out a memory-overlayed union implementation in ruby that doesn't
  #   require unpack for every member access (it would be welcomed)
  #
  # @example
  #   # encoding: ASCII-8BIT
  #   require_relative "./lib/ctypes"
  #
  #   # subclass Union to define a union
  #   class Msg < CTypes::Union
  #     layout do
  #       # this message uses network-byte order
  #       endian :big
  #
  #       # create enum for the message type used in members
  #       type = enum(uint8, {invalid: 0, hello: 1, read: 2})
  #
  #       # define union members
  #       member :hello, struct({type:, version: string})
  #       member :read, struct({type:, offset: uint64, len: uint64})
  #       member :type, type
  #       member :raw, string
  #     end
  #   end
  #
  #   # unpack a message and access member values
  #   msg = Msg.unpack("\x02" +
  #                    "\xfe\xfe\xfe\xfe\xfe\xfe\xfe\xfe" +
  #                    "\xab\xab\xab\xab\xab\xab\xab\xab")
  #   msg.type                      # => :read
  #   msg.read.offset               # => 0xfefefefefefefefe
  #   msg.read.len                  # => 0xabababababababab
  #
  #   # create new messages
  #   Msg.pack({hello: {type: :hello, version: "v1.0"}})
  #                                 # => "\1v1.0\0\0\0\0\0\0\0\0\0\0\0\0"
  #   Msg.pack({read: {type: :read, offset: 0xffff, len: 0x1000}})
  #                                 # => "\2\0\0\0\0\0\0\xFF\xFF\0\0\0\0\0\0\x10\0"
  #
  #   # work with a message instance to create a message
  #   msg = Msg.new
  #   msg.hello.type = :hello
  #   msg.hello.version = "v1.0"
  #   msg.to_binstr                 # => "\1v1.0\0\0\0\0\0\0\0\0\0\0\0\0"
  #
  class Union
    extend Type
    using PrettyPrintHelpers

    # define the layout of this union
    # @see Builder
    #
    # @example
    #   class Msg < CTypes::Union
    #     layout do
    #       # this message uses network-byte order
    #       endian :big
    #
    #       # create enum for the message type used in members
    #       type = enum(uint8, {invalid: 0, hello: 1, read: 2})
    #
    #       # define union members
    #       member :hello, struct({type:, version: string})
    #       member :read, struct({type:, offset: uint64, len: uint64})
    #       member :type, type
    #       member :raw, string
    #     end
    #   end
    def self.layout(&block)
      raise Error, "no block given" unless block
      builder = Builder.new(&block)
      builder.instance_eval(&block)
      apply_layout(builder)
    end

    # get an instance of the {Union::Builder}
    def self.builder
      Builder.new
    end

    # @api private
    def self.apply_layout(builder)
      @name, @fields, @dry_type, @size, @fixed_size, @endian = builder.result

      @field_accessors ||= []
      remove_method(*@field_accessors.flatten)
      @field_accessors.clear
      @field_types = {}
      @greedy = false

      @fields.each do |field|
        # split out the array; we do it this way because we want to reference
        # the original fields array when assigning @field_types
        name, type = field

        # the union will be flagged as greedy if size is not defined by a Proc,
        # and the field type is greedy
        @greedy ||= type.greedy? unless @size.is_a?(Proc)

        case name
        when Symbol
          @field_accessors += [
            define_method(name) { self[name] },
            define_method(:"#{name}=") { |v| self[name] = v }
          ]
          @field_types[name] = field
        when ::Array
          name.each do |n|
            @field_accessors += [
              define_method(n) { self[n] },
              define_method(:"#{n}=") { |v| self[n] = v }
            ]
            @field_types[n] = field
          end
        else
          raise Error, "unsupported field name type: %p", name
        end
      end
    end
    private_class_method :apply_layout

    # encode a ruby Hash into a String containing the binary representation of
    # the Union
    #
    # @param value [Hash] value to be encoded; must have size <= 1
    # @param endian [Symbol] endian to pack with
    # @param validate [Boolean] set to false to disable value validation
    # @param pad_bytes [String] bytes to used to pad; defaults to null bytes
    # @note do not provide multiple member values to this method; only zero or
    #   one member values are supported.
    # @return [::String] binary encoding for value
    #
    # @example
    #   include CTypes::Helpers
    #   t = union(word: uint32, bytes: array(uint8, 4))
    #   t.pack({word: 0xfeedface})        # => "\xCE\xFA\xED\xFE"
    #   t.pack({word: 0xfeedface}, endian: :big)
    #                                     # => "\xFE\xED\xFA\xCE"
    #
    #   t.pack({bytes: [1, 2, 3, 4]})     # => "\x01\x02\x03\x04"
    #   t.pack({bytes: [1, 2, 3, 4]}, endian: :big)
    #                                     # => "\x01\x02\x03\x04"
    #
    #   t.pack({bytes: [1, 2]})           # => "\x01\x02\x00\x00"
    #   t.pack({bytes: []})               # => "\x00\x00\x00\x00"
    #   t.pack({bytes: nil})              # => "\x00\x00\x00\x00"
    #   t.pack({})                        # => "\x00\x00\x00\x00"
    #   t.pack({word: 20, bytes: []})     # => CTypes::Error
    #
    # @example using pad_bytes
    #   t = union { member :u8, uint8, member :u32, uint32 }
    #   t.pack({u8: 0}, pad_bytes: "ABCD") # => "\0BCD"
    def self.pack(value, endian: default_endian, validate: true, pad_bytes: nil)
      value = value.to_hash.freeze
      unknown_keys = value&.keys
      members = @fields.filter_map do |name, type|
        case name
        when Symbol
          unknown_keys.delete(name)
          [name, type, value[name]] if value.has_key?(name)
        when ::Array
          unknown_keys.reject! { |k| name.include?(k) }
          [name, type, value.slice(*name)] if name.any? { |n| value.has_key?(n) }
        else
          raise Error, "unsupported field name type: %p" % [name]
        end
      end

      # raise an error if they provided multiple member values
      if members.size > 1
        raise Error, <<~MSG % [members.map { |name, _| name }]
          conflicting values for Union#pack; only supply one union member: %p
        MSG

      # raise an error if they provided extra keys that aren't for a member
      elsif !unknown_keys.empty?
        raise Error, "unknown member names: %p" % [unknown_keys]

      # if they didn't provide any key, use the first member
      elsif members.empty?
        name, type = @fields.first
        members << [name, type, type.default_value]
      end

      # we have a single member value to pack; let's grab the type & value and
      # pack it
      _, type, val = members[0]
      out = if type.respond_to?(:ancestors) && type.ancestors.include?(Union)
        type.pack(val, endian: type.endian || endian, validate:, pad_bytes:)
      else
        type.pack(val, endian: type.endian || endian, validate:)
      end

      # @size has two different behaviors.  When @size is a proc, then the size
      # is an absolute length.  Otherwise, size is a minimum length.  To start
      # with, let's calculate a minimum length.
      #
      # @size has two different behaviors.  When @size is a Proc, it represents
      # an absolute length.  Otherwise, size represents a minimum length.  We
      # do this to support unions with greedy members without the union itself
      # being greedy.
      #
      # So grab the minimum length of the output string and expand the output
      # to be at least that long.
      min_length = if @size.is_a?(Proc)

        # Run the size proc with a Union made of our output.  Yes we end up
        # unpacking what we just packed in this case, but it's the cost of
        # supporting pack of dynamically sized unions.
        begin
          instance_exec(new(buf: out, endian:).freeze, &@size)

        # so there's a chance that the packed union value has fewer bytes
        # than what is required to evaluate the size proc.  If we get a missing
        # bytes error, let's pad the out string with the needed number of
        # bytes.  This may happen multiple times as we have no idea what is
        # in the size proc.
        rescue CTypes::MissingBytesError => ex
          out << if pad_bytes && out.size < pad_bytes.size
            pad_bytes.byteslice(out.size, ex.need)
          else
            "\0" * ex.need
          end
          retry
        end
      else
        @size
      end

      # when we need to pad the output, use pad_bytes first
      if out.size < min_length && pad_bytes
        out << pad_bytes.byteslice(out.size, min_length - out.size)
      end

      # if we still need more bytes, pad with zeros
      if out.size < min_length
        out << "\0" * (min_length - out.size)
      end

      # Now, if @size is a Proc only return the absolute length bytes of our
      # output string.  Everything else gets the full output string
      @size.is_a?(Proc) ? out.byteslice(0, min_length) : out
    end

    # convert a String containing the binary represention of a c union into
    # a ruby type
    #
    # @param buf [String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return [::Array(Union, ::String)] Union, and remaining bytes
    #
    # @see Type#unpack
    #
    # @example
    #   class Msg < CTypes::Union
    #     layout do
    #       type = enum(uint8, {invalid: 0, hello: 1, read: 2})
    #       member :hello, struct({type:, version: string})
    #       member :read, struct({type:, offset: uint64, len: uint64})
    #       member :type, type
    #     end
    #   end
    #
    #   msg, rest = Msg.unpack_one("\x02" +
    #                              "\xfe\xfe\xfe\xfe\xfe\xfe\xfe\xfe" +
    #                              "\xab\xab\xab\xab\xab\xab\xab\xab" +
    #                              "extra_bytes")
    #   msg.type                      # => :read
    #   msg.read.offset               # => 0xfefefefefefefefe
    #   msg.read.len                  # => 0xabababababababab
    #   rest                          # => "extra_bytes"
    def self.unpack_one(buf, endian: default_endian)
      size = if @size.is_a?(Proc)
        instance_exec(new(buf:, endian:).freeze, &@size)
      else
        @size
      end

      raise missing_bytes_error(input: buf, need: size) if buf.size < size
      if fixed_size? || @size.is_a?(Proc)
        buf, rest = buf.byteslice(0, size), buf.byteslice(size..)
      else
        rest = ""
      end

      [new(buf:, endian:), rest]
    end

    # @api private
    def self.unpack_field(field:, buf:, endian:)
      name, type = @field_types[field]
      raise UnknownMemberError, "unknown member: %p" % [field] unless type

      case name
      when Symbol
        {name => type.with_endian(endian).unpack(buf)}
      when ::Array
        type.with_endian(endian).unpack(buf, endian:)
      end
    end

    # return the struct name
    # @api private
    def self.type_name
      @name
    end

    # @api private
    def self.greedy?
      @greedy
    end

    # check if this is a fixed-size Union
    def self.fixed_size?
      @fixed_size
    end

    # return minimum size of the Union
    # @see Type.size
    def self.size
      @size
    end

    # return the size of a member
    # @see Type.size
    def self.sizeof(member)
      @field_types[member][1].size
    end

    # get the list of members in this Union
    #
    # @return [::Array<Symbol>] member names
    def self.fields
      @field_types.keys
    end

    # get the list of members in this Union
    #
    # @return array of field layout
    def self.field_layout
      @fields
    end

    # check if the Union has a given member
    # @param member [Symbol] member name
    def self.has_field?(member)
      @field_types.has_key?(member)
    end

    # check if another Union subclass has the same members as this Union
    def self.==(other)
      return true if super
      return false unless other.is_a?(Class) && other < Union
      other.field_layout == @fields &&
        other.default_endian == default_endian &&
        other.size == size
    end

    def self.pretty_print(q) # :nodoc:
      q.ctype("union", @endian) do
        q.seplist(@fields, -> { q.breakable("; ") }) do |name, type|
          case name
          when Symbol
            q.text("member %p, " % name)
          when ::Array
            q.text("member ")
          end
          q.pp(type)
        end
      end
    end

    class << self
      alias_method :inspect, :pretty_inspect # :nodoc:
    end

    # @api private
    def self.export_type(q)
      q << "CTypes::Union.builder()"
      q.break
      q.nest(2) do
        q << ".endian(%p)\n" % [@endian] if @endian
        @fields.each do |name, type|
          case name
          when Symbol
            q << ".member(%p, " % [name]
            q << type
            q << ")"
          when ::Array
            q << ".member("
            q << type
            q << ")"
          else
            raise Error, "unsupported field name type: %p" % [name]
          end
          q.break
        end
        q << ".build()"
      end
    end

    # @param buf [String] binary String containing Union memory
    # @param endian [Symbol] byte-order of buf
    def initialize(
      buf: "\0" * self.class.size,
      endian: self.class.default_endian
    )
      @buf = buf
      @endian = endian
    end

    # freeze the values within the Union
    #
    # This is used to eliminate the pack/unpack performance penalty when
    # accessing multiple members in a read-only Union.  By freezing the Union
    # we can avoid packing the existing member when accessing another memeber.
    def freeze
      @frozen = true
      self
    end

    def frozen?
      @frozen == true
    end

    # get a member value
    #
    # @param member [Symbol] member name
    # @note only the value for the most recently accessed member is cached
    # @note WARNING: accessing any member will erase any modifications made to
    #   other members of the union
    #
    # @example
    #   include CTypes::Helpers
    #   t = union(word: uint32, bytes: array(uint8, 4), str: string)
    #   u = t.unpack("hello world")
    #   u[:str]                           # => "hello world"
    #   u[:word]                          # => 1819043176
    #   u[:bytes]                         # => [104, 101, 108, 108]
    #
    # @example nested struct
    #   include CTypes::Helpers
    #   t = union(a: struct(a: uint8, b: uint8, c: uint16), raw: string)
    #   u = t.unpack("\x01\x02\xed\xfe")
    #   u.a                               # => #<struct a=1, b=2, c=0xfeed>
    #
    # @example ERROR: wiping modified member value by accident
    #   include CTypes::Helpers
    #   t = union(word: uint32, bytes: array(uint8, 4))
    #   u = t.new
    #   u[:bytes] = [1,2,3]
    #   u[:word]                          # ERROR!!!  erases changes to bytes
    #   u[:bytes]                         # => [0, 0, 0, 0]
    #
    def [](name)
      v = active_field(name)[name]
      unless frozen? ||
          v.is_a?(Integer) ||
          v.is_a?(TrueClass) ||
          v.is_a?(FalseClass)
        @changed = true
      end
      v
    end

    # set a member value
    # @param member [Symbol] member name
    # @param value member value
    # @note WARNING: modifying any member will erase any modifications made to
    #   other members of the union
    #
    # @example
    #   include CTypes::Helpers
    #   t = union(word: uint32, bytes: array(uint8, 4), str: string)
    #   u = t.new
    #   u[:bytes] = [1,2,3,4]
    #   u.to_binstr                       # => "\x01\x02\x03\x04"
    #   u[:bytes] = [1,2,3]
    #   u.to_binstr                       # => "\x01\x02\x03\x00"
    def []=(name, value)
      raise FrozenError, "can't modify frozen Union: %p" % [self] if frozen?
      active_field(name)[name] = value
      @changed = true
    end

    def has_key?(name)
      self.class.has_field?(name)
    end

    # return a Hash representation of the Union
    # @param shallow [Boolean] set to true to disable deep traversal
    # @return [Hash]
    #
    # @example
    #   include CTypes::Helpers
    #   t = union(bytes: array(uint8, 4),
    #             str: string,
    #             nested: struct(a: uint8, b: uint8, c: uint16))
    #   u = t.unpack("hello world")
    #   u.to_h                            # => {:bytes=>[104, 101, 108, 108],
    #                                     #     :str=>"hello world",
    #                                     #     :nested=>{
    #                                     #       :a=>104, :b=>101, :c=>27756
    #                                     #     }}
    def to_h(shallow: false)
      # grab the cached active field, or the default one
      out = @active_field || active_field
      out = out.is_a?(Hash) ? out.dup : out.to_h

      # now convert all the values to hashes unless we're doing a shallow to_h
      unless shallow
        out.transform_values! do |v|
          case v
          when ::Array
            v
          else
            v.respond_to?(:to_h) ? v.to_h : v
          end
        end
      end

      out
    end
    alias_method :to_hash, :to_h

    def pretty_print(q) # :nodoc:
      # before printing, apply any changes to the buffer
      apply_changes!

      active = to_h

      open = if (name = self.class.type_name || self.class.name)
        "union #{name} {"
      else
        "union {"
      end
      q.group(4, open, "}") do
        q.seplist(self.class.fields, -> { q.breakable("") }) do |name|
          q.text(".#{name} = ")
          unless active.has_key?(name)
            begin
              v = self.class.unpack_field(field: name, buf: @buf, endian: @endian)
              active.merge!(v)
            rescue Error => ex
              active[name] = "[unpack failed: %p]" % [ex]
            end
          end

          q.pp(active[name])
          q.text(", ")
        end
      end
    end
    alias_method :inspect, :pretty_inspect # :nodoc:

    # return the binary representation of this Union
    #
    # This method calls [Union.pack] on the most recentlu accessed member of
    # the Union.  If no member has been accessed, it returns the original
    # String it was initialized with
    #
    # @return [String] binary representation of union
    #
    # @example
    #   include CTypes::Helpers
    #   t = union(word: uint32, bytes: array(uint8, 4), str: string)
    #   u = t.new
    #   u.bytes = [1,2,3,4]
    #   u.to_binstr                       # => "\x01\x02\x03\x04"
    #
    # @example accessing member after modifying other member resets members
    #   include CTypes::Helpers
    #   t = union(word: uint32, bytes: array(uint8, 4), str: string)
    #   u = t.new
    #   u.bytes = [1,2,3,4]
    #   u.to_binstr                       # => "\x01\x02\x03\x04"
    #   u.word                            # => ERROR: resets changes to .bytes
    #   u.to_binstr                       # => "\x00\x00\x00\x00"
    def to_binstr(endian: @endian)
      endian ||= self.class.default_endian

      if endian != @endian
        self.class.pack((@active_field || active_field).to_h, endian:)
      else
        apply_changes!
        @buf.dup
      end
    end

    # @api private
    def active_field(name = nil)
      name ||= self.class.fields.first

      unless @active_field&.has_key?(name)
        apply_changes!
        @active_field = nil
        @active_field = self.class
          .unpack_field(field: name, buf: @buf, endian: @endian)
      end
      @active_field
    end
    private :active_field

    # @api private
    def apply_changes!
      return false if frozen?
      return false unless @active_field && @changed
      @buf = self.class.pack(@active_field, pad_bytes: @buf)
      @changed = false
      true
    end
    private :apply_changes!
  end
end
require_relative "union/builder"
