# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # {Enum} layout builder
  #
  # This class is used to define the name/value pairs for {Enum} types.  The
  # builder supports dynamic numbering similar to that used in C.  The
  # {Builder} is used internally by {Enum}, and should not be used directly.
  #
  # @example Supported syntax and dynamic numbering
  #   CTypes::Enum.new do |builder|
  #     # automatic numbering
  #     builder << :a       # :a will have value 0
  #     builder << :b       # :b will have value 1
  #     builder << {c: 10}  # :c will have value 10
  #     builder << :d       # :d will have value 11
  #
  #     # bulk assignment
  #     builder << %i[e f g]  # :e == 12, :f == 11, :g == 12
  #
  #     # bulk assignment with values
  #     builder << {z: 25, y: 24, x: 23}
  #     builder << :max       # :max == 26
  #   end
  class Enum::Builder
    def initialize(&block)
      @map = {}
      @next = 0
      @default = nil
      block.call(self)
    end
    attr_reader :map
    attr_accessor :default

    # append new key/value pairs to the {Enum}
    # @param value name or name/value pairs
    #
    # @example
    #   CTypes::Enum.new do |builder|
    #     # automatic numbering
    #     builder << :a       # :a will have value 0
    #     builder << :b       # :b will have value 1
    #     builder << {c: 10}  # :c will have value 10
    #     builder << :d       # :d will have value 11
    #
    #     # bulk assignment
    #     builder << %i[e f g]  # :e == 12, :f == 11, :g == 12
    #
    #     # bulk assignment with values
    #     builder << {z: 25, y: 24, x: 23}
    #     builder << :max       # :max == 26
    #   end
    def <<(value)
      case value
      when Hash
        value.each_pair { |k, v| set(k, v) }
      when ::Array
        value.each { |v| set(v, @next) }
      else
        set(value, @next)
      end
      self
    end

    def push(*values)
      values.each { |v| self << v }
    end

    private

    def set(key, value)
      key = key.to_sym
      raise Error, "duplicate key %p" % key if
          @map.has_key?(key)
      raise Error, "value must be Integer: %p" unless
          value.is_a?(Integer)
      @map[key] = value
      @next = value + 1 if value >= @next
      @default ||= key
    end
  end
end
