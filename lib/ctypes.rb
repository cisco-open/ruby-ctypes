# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

require "dry-types"
require "pp" # standard:disable Lint/RedundantRequireStatement

require_relative "ctypes/version"
require_relative "ctypes/type"
require_relative "ctypes/int"
require_relative "ctypes/helpers"
require_relative "ctypes/pretty_print_helpers"
require_relative "ctypes/enum"
require_relative "ctypes/bitmap"
require_relative "ctypes/struct"
require_relative "ctypes/string"
require_relative "ctypes/array"
require_relative "ctypes/terminated"
require_relative "ctypes/union"
require_relative "ctypes/bitfield"
require_relative "ctypes/exporter"
require_relative "ctypes/pad"

# Manipulate binary data in ruby using C-like data types
module CTypes
  class Error < StandardError; end

  class TruncatedValueError < Error; end

  class UnknownAttributeError < Error; end

  class UnknownMemberError < Error; end

  class UnknownFieldError < Error; end

  class TerminatorNotFoundError < Error; end

  # @api private
  Endian = Dry::Types["coercible.symbol"].enum(*%i[big little])

  # set the endian for any datatype that does not have an explicit endian set
  #
  # @param value [Symbol] endian, :big or little
  #
  # @example big endian
  #   CTypes.default_endian = :big
  #   t = CTypes::UInt32
  #   t.pack(0xdeadbeef)                  # => "\xde\xad\xbe\xef"
  #   t.pack(0xdeadbeef, endian: :little) # => "\xef\xbe\xad\xde"
  #
  #   # create a type that overrides the default endian
  #   l = CTypes::UInt32.with_endian(:little)
  #   l.pack(0xdeadbeef)                  # => "\xef\xbe\xad\xde"
  #
  # @example little endian
  #   CTypes.default_endian = :little
  #   t = CTypes::UInt32
  #   t.pack(0xdeadbeef)                  # => "\xef\xbe\xad\xde"
  #   t.pack(0xdeadbeef, endian: :big)    # => "\xde\xad\xbe\xef"
  #
  def self.default_endian=(value)
    @endian = Endian[value]
  end

  # get the default endian for the system; defaults to native endian
  def self.default_endian
    @endian ||= host_endian
  end

  # get the endian of the system this code is running on
  def self.host_endian
    @host_endian ||= ("\xde\xad".unpack1("S") == 0xDEAD) ? :big : :little
  end

  # set a unknown type lookup method to use in the layout blocks of
  # `Ctypes::Struct` and `CTypes::Union`.
  #
  # Note: the current implementation is not thread-safe.
  #
  # @example
  #   @my_types = { id_t: uint32 }
  #   my_struct = CTypes.using_type_lookup(->(n) { @my_types[n] }) do
  #     struct do
  #       attribute id, id_t
  #     end
  #   end
  def self.using_type_lookup(lookup)
    @type_lookup ||= []
    @type_lookup.push(lookup)
    yield
  ensure
    @type_lookup.pop
  end

  # @api private
  def self.type_lookup # :nodoc:
    @type_lookup && @type_lookup[-1]
  end
end

require_relative "ctypes/missing_bytes_error"
