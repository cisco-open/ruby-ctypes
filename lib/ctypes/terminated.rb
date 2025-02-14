# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # Wrap another CTypes::Type to provide terminated implementations of that
  # type.  Used by {CTypes::Array} and {CTypes::String} to truncate the buffer
  # passed to the real type to terminate greedy types.
  #
  # During #unpack, this class will locate the terminator in the input buffer,
  # then pass a truncated input to the underlying greedy type for unpacking.
  #
  # During #pack, this class will call the underlying greedy type #pack
  # method, then append the terminator.
  #
  # @api private
  class Terminated
    include Type

    def initialize(type:, locate:, terminate:)
      @type = type
      @locate = locate
      @term = terminate
    end

    def dry_type
      @type.dry_type
    end

    def greedy?
      false
    end

    def size
      @term_size ||= terminate(@type.default_value.dup,
        endian: default_endian).size
    end

    def pack(value, endian: default_endian, validate: true)
      buf = @type.pack(value, endian:, validate:)
      terminate(buf, endian:)
    end

    def unpack_one(buf, endian: default_endian)
      value_size, term_size = @locate.call(buf, endian:)
      if value_size.nil?
        raise TerminatorNotFoundError,
          "terminator not found in: %p" % buf
      end
      value = @type.unpack(buf[0, value_size], endian:)
      [value, buf.byteslice((value_size + term_size)..)]
    end

    def terminate(buf, endian:)
      buf << case @term
      when Proc
        @term.call(buf, endian)
      else
        @term.to_s
      end
    end
  end
end
