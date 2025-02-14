# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

module CTypes
  RSpec.describe Enum::Builder do
    [
      {
        block: ->(b) { b << :a },
        map: {a: 0},
        default: :a
      },
      {
        block: ->(b) { b << %i[a a] },
        raise: [Error, /duplicate key :a/]
      },
      {
        block: ->(b) { b << %i[a b] },
        map: {a: 0, b: 1},
        default: :a
      },
      {
        block: proc do |b|
          b << :a
          b << :b
        end,
        map: {a: 0, b: 1},
        default: :a
      },
      {
        block: proc do |b|
          b << %i[a b]
          b << :c
        end,
        map: {a: 0, b: 1, c: 2},
        default: :a
      },
      {
        block: proc do |b|
          b << {b: 65, a: 4}
        end,
        map: {a: 4, b: 65},
        default: :b
      },
      {
        block: proc do |b|
          b.default = :a
          b << {b: 65, a: 4}
        end,
        map: {a: 4, b: 65},
        default: :a
      },
      {
        block: proc do |b|
          b << %i[a b]
          b << {c: 80}
          b << :d
        end,
        map: {a: 0, b: 1, c: 80, d: 81},
        default: :a
      }
    ].each do |ctx|
      context "Enum::Builder.new(%s)" % [ctx[:block].source] do
        let(:builder) do
          described_class.new(&ctx[:block])
        end

        if ctx[:raise]
          it "will raise %p" % ctx[:raise] do
            expect { builder }.to raise_error(*ctx[:raise])
          end
        else
          it "will have map %p" % ctx[:map] do
            expect(builder.map).to eq(ctx[:map])
          end

          it "will have default" % ctx[:default] do
            expect(builder.default).to eq(ctx[:default])
          end
        end
      end
    end
  end
end
