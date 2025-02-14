# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  # Exception raised when attempting to unpack a {Type} that requires more
  # bytes than were provided in the input.
  class MissingBytesError < Error
    def initialize(type:, input:, need:)
      @type = type
      @input = input
      @need = need
      super("insufficent input to unpack %s; missing %d bytes" %
        [@type, missing])
    end
    attr_reader :type, :input, :need

    # get the number of additional bytes required to unpack this type
    def missing
      @need - @input.size
    end
  end
end
