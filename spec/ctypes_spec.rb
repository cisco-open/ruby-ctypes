# frozen_string_literal: true

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

RSpec.describe CTypes do
  it "has a version number" do
    expect(CTypes::VERSION).not_to be nil
  end
end
