# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # Used to export CTypes
  # @api private
  class Exporter
    def initialize(output = "".dup)
      @output = output
      @indent = 0
      @indented = false
      @type_lookup = nil
    end
    attr_writer :type_lookup
    attr_reader :output

    def nest(indent, &block)
      @indent += indent
      yield
    ensure
      @indent -= indent
    end

    def break
      self << "\n"
    end

    def <<(arg)
      case arg
      when CTypes::Type
        if buf = @type_lookup&.call(arg)
          self << buf
        else
          nest(2) { arg.export_type(self) }
        end
      when ::String
        unless @indented
          @output << " " * @indent
          @indented = true
        end
        @output << arg
        @indented = !arg.end_with?("\n")
      else
        raise Error, "not supported"
      end
    end
  end
end
