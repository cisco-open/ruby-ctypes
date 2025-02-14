# encoding: ASCII-8BIT

# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe String do
    data_set = [
      # fixed-size, trim null bytes
      {
        string: {size: 8, trim: true},
        size: 8,
        pack: {
          "" => "\0\0\0\0\0\0\0\0",
          "hello" => "hello\0\0\0",
          "feedface" => "feedface",
          "feedfaceXXX" => Dry::Types::ConstraintError
        },
        unpack: {
          "\0\0\0\0\0\0\0\0" => ["", ""],
          "hello\0\0\0" => ["hello", ""],
          "feedface" => ["feedface", ""],
          "feedfaceXXX" => ["feedface", "XXX"]
        }
      },
      # fixed-size, preserve null bytes
      {
        string: {size: 8, trim: false},
        size: 8,
        pack: {
          "" => "\0\0\0\0\0\0\0\0",
          "hello" => "hello\0\0\0",
          "feedface" => "feedface",
          "feedfaceXXX" => Dry::Types::ConstraintError
        },
        unpack: {
          "\0\0\0\0\0\0\0\0" => ["\0\0\0\0\0\0\0\0", ""],
          "hello\0\0\0" => ["hello\0\0\0", ""],
          "feedface" => ["feedface", ""],
          "feedfaceXXX" => ["feedface", "XXX"]
        }
      },
      # nil size should be greedy
      {
        string: {size: nil, trim: true},
        size: 0,
        pack: {
          "" => "",
          "hello" => "hello",
          "hello\0\0\0" => "hello\0\0\0"
        },
        unpack: {
          "\0\0\0\0" => ["", ""],
          "hello\0\0\0" => ["hello", ""],
          "hello" => ["hello", ""]
        }
      }
    ].each do |ctx|
      context "String.new(**%p)" % ctx[:string] do
        let(:string) { String.new(**ctx[:string]) }

        it "#size => %d" % ctx[:size] do
          expect(string.size).to eq(ctx[:size])
        end

        describe "#pack" do
          ctx[:pack].each do |input, output|
            if output.is_a?(::String)
              it "pack(%p) # => %p" % [input, output] do
                expect(string.pack(input)).to eq(output)
              end
            else
              it "pack(%p) will raise %p" % [input, output] do
                expect { string.pack(input) }.to raise_error(*output)
              end
            end
          end
        end

        describe "#unpack_one" do
          ctx[:unpack].each_pair do |input, output|
            if output.first.is_a?(::String)
              it "unpack(%p) # => %p" % [input, output] do
                result = string.unpack_one(input)
                expect(result).to eq(output)
              end
            else
              it "unpack(%p) will raise error %p" % [input, output] do
                expect { string.unpack_one(input) }.to raise_error(*output)
              end
            end
          end
        end
      end

      context "String.new(size: 16)" do
        it "unpack(\"short\") will raise MissingBytesError" do
          expect { String.new(size: 16).unpack("short") }
            .to raise_error(MissingBytesError, /16/)
        end
      end
    end
  end
end
