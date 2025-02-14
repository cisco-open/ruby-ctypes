# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # Generic type to represent a gap in the data structure.  Unpacking this
  # type will consume the pad size and return nil.  Packing this type will
  # return a string of null bytes of the appropriate size.
  #
  # @example
  #   t = Pad.new(4)
  #   t.unpack_one("hello_world)  # => [nil, "o_world"]
  #   t.pack("blahblahblah")      # => "\0\0\0\0"
  class Pad
    include Type

    def initialize(size)
      @size = size
      @dry_type = Dry::Types::Any.default(nil)
    end
    attr_reader :size

    def pack(value, endian: default_endian, validate: true)
      "\0" * @size
    end

    def unpack_one(buf, endian: default_endian)
      raise missing_bytes_error(input: buf, need: @size) if
        @size && buf.size < @size
      [nil, buf.byteslice(@size..)]
    end

    def greedy?
      false
    end

    def to_s
      "pad(%d)" % [@size]
    end

    def pretty_print(q)
      q.text("pad(%d)" % @size)
    end
    alias_method :inspect, :pretty_inspect # :nodoc:

    def export_type(q)
      q << ".pad(%d)" % [@size]
    end

    def ==(other)
      other.is_a?(self.class) && other.size == size
    end
  end
end
