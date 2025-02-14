# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # helpers for use when pretty printing ctypes
  # @api private
  module PrettyPrintHelpers
    refine PrettyPrint do
      def ctype(type, endian = nil)
        text "#{type} {"
        group_sub do
          nest(4) do
            current_group.break
            breakable
            yield
          end
        end
        current_group.break
        breakable
        text "}"
        text ".with_endian(%p)" % [endian] if endian
      end

      def line(buf)
        text buf
        current_group.break
        breakable
      end
    end
  end
end
