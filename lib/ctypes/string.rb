# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # Type used to unpack binary strings into Ruby {::String} instances
  #
  # @example greedy string
  #   t = CTypes::String.new
  #   t.unpack("hello world\0bye")      # => "hello world"
  #
  #   # greedy string will consume all bytes, but only return string up to the
  #   # first null-terminator
  #   t.unpack_one("hello world\0bye")  # => ["hello world", ""]
  #
  #   t.pack("test")                    # => "test"
  #   t.pack("test\0")                  # => "test\0"
  #
  # @example null-terminated string
  #   t = CTypes::String.terminated
  #   t.unpack("hello world\0bye")      # => "hello world"
  #
  #   # terminated string will consume bytes up to and including the
  #   # terminator
  #   t.unpack_one("hello world\0bye")  # => ["hello world", "bye"]
  #
  #   t.pack("test")                    # => "test\0"
  #
  # @example fixed-size string
  #   t = CTypes::String.new(size: 5)
  #   t.unpack("hello world\0bye")      # => "hello"
  #   t.unpack_one("hello world\0bye")  # => ["hello", " world\0bye"]
  #   t.pack("hi")                      # => "hi\0\0\0"
  #
  # @example fixed-size string, preserving null bytes
  #   t = CTypes::String.new(size: 8, trim: false)
  #   t.unpack("abc\0\0xyzXXXX")        # => "abc\0\0xyz"
  #   t.pack("hello")                   # => "hello\0\0\0"
  class String
    include Type

    # Return a {String} type that is terminated by the supplied sequence
    # @param terminator [::String] byte sequence to terminate the string
    #
    # @example null-terminated string
    #   t = CTypes::String.terminated
    #   t.unpack("hello world\0bye")    # => "hello world"
    #
    # @example string terminated string
    #   t = CTypes::String.terminated("STOP")
    #   t.unpack("test 1STOPtest 2STOP")  # => "test 1"
    def self.terminated(terminator = "\0")
      size = terminator.size
      Terminated.new(type: new,
        locate: proc { |b, _| [b.index(terminator), size] },
        terminate: terminator)
    end

    # @param size [Integer] number of bytes
    # @param trim [Boolean] set to false to preserve null bytes when unpacking
    def initialize(size: nil, trim: true)
      @size = size
      @trim = trim
      @dry_type = Dry::Types["coercible.string"].default("")
      @dry_type = @dry_type.constrained(max_size: size) if size.is_a?(Integer)
      size ||= "*"

      @fmt_pack = "a%s" % size
      @fmt_unpack = (trim ? "Z%s" : "a%s") % size
    end
    attr_reader :trim

    # pack a ruby String into a binary string, applying any required padding
    #
    # @param value [::String] string to pack
    # @param endian [Symbol] endian to use when packing; ignored
    # @param validate [Boolean] set to false to disable validation
    # @return [::String] binary encoding for value
    def pack(value, endian: default_endian, validate: true)
      value = @dry_type[value] if validate
      [value].pack(@fmt_pack)
    end

    # unpack a ruby String from binary string data
    # @param buf [::String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return [::Array(::String, ::String)] unpacked string, and unused bytes
    def unpack_one(buf, endian: default_endian)
      raise missing_bytes_error(input: buf, need: @size) if
        @size && buf.size < @size
      value = buf.unpack1(@fmt_unpack)
      [value, @size ? buf.byteslice(@size..) : ""]
    end

    # @api private
    def greedy?
      @size.nil?
    end

    # get the size in bytes of the string; returns 0 for greedy strings
    def size
      @size || 0
    end

    def to_s
      "string[#{size}]"
    end

    def pretty_print(q)
      if size && size > 0
        if trim
          q.text("string(%d)" % @size)
        else
          q.text("string(%d, trim: false)" % @size)
        end
      else
        q.text "string"
      end
    end
    alias_method :inspect, :pretty_inspect # :nodoc:

    # @api private
    def export_type(q)
      q << if size && size > 0
        if trim
          "string(%d)" % [@size]
        else
          "string(%d, trim: false)" % [@size]
        end
      else
        "string"
      end
    end

    # @api private
    def type_name
      @size ? "char[#{@size}]" : "char[]"
    end

    # This function is provided as a helper to {Helpers#string} to enable
    # `string.terminated` as a type.
    #
    # @see String.terminated
    def terminated(terminator = "\0")
      String.terminated(terminator)
    end

    def ==(other)
      other.is_a?(self.class) && other.size == size && other.trim == trim
    end
  end
end
