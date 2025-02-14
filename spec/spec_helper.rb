# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

require "ctypes"
require "pry-rescue/rspec"
require_relative "proc_source"

module Helpers
  # helper for converting strings of 1s & 0s into a String containing bytes
  # of those bits.
  def bitstr(buf)
    fmt = case buf.size
    when 0..8
      "C"
    when 9..16
      "S"
    when 17..32
      "L"
    when 33..64
      "Q"
    else
      raise "buf must not be longer than 64 characters: %p" % buf
    end

    value = buf.to_i(2)
    [value].pack(fmt)
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.extend(CTypes::Helpers)
  config.extend(Helpers)
end
