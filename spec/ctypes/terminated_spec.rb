# encoding: ASCII-8BIT
# frozen_string_literal: true
# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe Terminated do
    [
      {
        type: CTypes::String.new,
        locate: ->(b, _) { return b.index("X"), 1  },
        terminate: "X",
        size: 1,
        pack: {
          "hello" => "helloX"
        },
        unpack: {
          "helloX" => "hello",
          "helloXworld" => "hello"
        }
      },
    ].each do |ctx|

      context "Terminated.new(type: %s, locate: %s, terminate: %s)" %
        [ctx[:type],
         ctx[:locate].is_a?(Proc) ?
         ctx[:locate].source : ctx[:locate].inspect,
         ctx[:terminate].is_a?(Proc) ?
         ctx[:terminate].source : ctx[:terminate].inspect] do
           let(:type) do
             described_class.new(type: ctx[:type],
                                 locate: ctx[:locate],
                                 terminate: ctx[:terminate])
           end

           it "#size => %d" % ctx[:size] do
             expect(type.size).to eq(ctx[:size])
           end

           describe ".pack" do
             ctx[:pack].each_pair do |input, output|
               it "pack(%p) # => %p" % [input, output] do
                 expect(type.pack(input)).to eq(output)
               end
             end
           end

           describe ".unpack" do
             ctx[:unpack].each_pair do |input, output|
               it "unpack(%p) # => %p" % [input, output] do
                 expect(type.unpack(input)).to eq(output)
               end
             end
           end
         end
    end
  end
end
