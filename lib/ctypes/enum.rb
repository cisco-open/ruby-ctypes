# encoding: ASCII-8BIT
# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT
require "forwardable"

module CTypes
  # Pack & unpack C enum values
  #
  # @example 32-bit contiguous enum
  #   state = Enum.new(%i[start stop block])
  #   state.pack(:block)                # => "\2\0\0\0"
  #   state.unpack("\0\0\0\0")          # => :start
  #
  # @example 8-bit contiguous enum
  #   state = Enum.new(UInt8, %i[start stop block])
  #   state.pack(:block)                # => "\2"
  #   state.unpack("\1")                # => :stop
  #
  # @example sparse enum
  #   state = Enum.new do |e|
  #     e << %i{a b c}
  #     e << {d: 32}
  #   end
  #   state.pack(:d)                    # => "\x20\x00\x00\x00"
  #   state.unpack("\x02\x00\x00\x00")  # => :c
  #
  class Enum
    include Type
    using PrettyPrintHelpers
    extend Forwardable

    # @example contiguous 32-bit enum
    #   Enum.new([:a, :b, :c])
    #   Enum.new(%i[a b c])
    #
    # @example contiguous 8-bit enum
    #   Enum.new(:uint8, %i[a b c])
    #
    # @example sparse enum
    #   Enum.new({a: 46, b: 789})
    #
    # @example 16-bit sparse enum
    #   Enum.new(UInt16, {a: 46, b: 789})
    #
    # @example 8-bit sparse enum
    #   Enum.new(Uint8) do |e|
    #     e << %i{zero one two}         # define 0, 1, 2
    #     e << {eighty: 80}             # skip 3-79 (incl), define 80
    #     e << :eighty_one
    #     e << {a: 100, b: 200}         # define multiple sparse values
    #   end
    #
    # @example dynamically generated enum
    #   Enum.new do |e|
    #     # declare state_0 through state_31
    #     32.times do |i|
    #       e << "state_#{i}"
    #     end
    #   end
    #
    # @see Builder
    def initialize(type = Helpers.uint32, values = nil, permissive: false,
      &block)
      builder = if block
        Builder.new(&block)
      else
        if values.nil?
          values = type
          type = Helpers.uint32
        end

        Builder.new { |b| b << values }
      end

      @dry_type = Dry::Types["symbol"]
        .default(builder.default)
        .enum(builder.map)
      @type = type
      @size = @type.size
      @dry_type = @dry_type.lax if permissive
    end
    attr_reader :size, :type
    def_delegators :@type, :signed?, :greedy?

    # encode a ruby type into a String containing the binary representation of
    # the enum
    #
    # @param value [Symbol, Integer] value to be encoded
    # @param endian [Symbol] endian to pack with
    # @param validate [Boolean] set to false to disable value validation
    # @return [::String] binary encoding for value
    #
    # @example
    #   e = Enum.new(%i[stopped running blocked])
    #   e.pack(:running)                  # => "\1\0\0\0"
    #   e.pack(2)                         # => "\2\0\0\0"
    def pack(value, endian: default_endian, validate: true)
      value = @dry_type[value] if validate
      out = @dry_type.mapping[value]
      out ||= case value
      when /\Aunknown_(\h+)\z/
        out = $1.to_i(16)
      when Integer
        value
      else
        raise Error, "unknown enum value: %p" % value
      end

      @type.pack(out, endian: @type.endian || endian, validate:)
    end

    # convert a String containing the binary represention of a c enum into the
    # ruby value
    #
    # @param buf [String] bytes that make up the type
    # @param endian [Symbol] endian of data within buf
    # @return [Array(Symbol, ::String)] decoded type, and remaining bytes
    # @see Type#unpack
    #
    # @example
    #   e = Enum.new(%i[stopped running blocked])
    #   e.unpack("\1\0\0\0")            # => :running
    def unpack_one(buf, endian: default_endian)
      value, rest = @type.unpack_one(buf, endian: @type.endian || endian)
      out = @dry_type[value]
      out = ("unknown_%0#{@size * 2}x" % value).to_sym unless out.is_a?(Symbol)
      [out, rest]
    end

    # @api private
    def mapping
      @dry_type.mapping
    end

    def pretty_print(q) # :nodoc:
      q.group(2, "enum(", ")") do
        if @type != Helpers.uint32
          q.pp(@type)
          q.comma_breakable
        end
        q.group(0, "{", "}") do
          q.seplist(@dry_type.mapping) do |name, value|
            q.text("#{name}: #{value}")
          end
        end
      end
    end
    alias_method :inspect, :pretty_inspect # :nodoc:

    def export_type(q)
      q << "enum("
      if @type != UInt32
        q << @type
        q << ", "
      end
      q << "{"
      q.break

      q.nest(2) do
        @dry_type.mapping.each do |name, value|
          q << "#{name}: #{value},"
          q.break
        end
      end
      q << "})"
      q << ".permissive" if @dry_type.is_a?(Dry::Types::Lax)
    end

    def ==(other)
      return false unless other.is_a?(Enum)
      other.type == @type && other.mapping == @dry_type.mapping
    end

    def default_value
      # with `.lax` added to dry_type for permissive enum, the standard
      # `dry_type[]` doesn't work for a default.  Instead, we're going to try
      # whatever key is set for 0, and failing that, just the first value
      # defined for the enum
      self[0] || @dry_type.mapping.first.first
    end

    def permissive
      Enum.new(@type, @dry_type.mapping, permissive: true)
    end

    # Convert a enum key to value, or value to key
    # @param arg [Integer, Symbol] key or value
    # @return [Symbol, Integer, nil] value or key if known, nil if unknown
    #
    # @example
    #   e = Enum.new(%i[a b c])
    #   e[1]    # => :b
    #   e[5]    # => nil
    #   e[:b]   # => 1
    #   e[:x]   # => nil
    def [](arg)
      case arg
      when Integer
        @inverted_mapping ||= @dry_type.mapping.invert
        @inverted_mapping[arg]
      when Symbol
        @dry_type.mapping[arg]
      else
        raise ArgumentError, "arg must be Integer or Symbol: %p" % [arg]
      end
    end
  end
end

require_relative "enum/builder"
