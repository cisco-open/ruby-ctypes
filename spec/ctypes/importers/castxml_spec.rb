# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

require "ctypes/importers/castxml"

module CTypes::Importers::CastXML
  RSpec.describe self do
    include CTypes::Helpers

    [
      ["#include <stdint.h>",
        {uint8_t: uint8,
         uint16_t: uint16,
         uint32_t: uint32,
         uint64_t: uint64,
         int8_t: int8,
         int16_t: int16,
         int32_t: int32,
         int64_t: int64}],
      [<<~SRC,
        typedef struct record_s {
          int id;
          char name[32];
        } record_t;
      SRC
        {
          record_s: struct(id: int32, name: string(32)),
          record_t: struct(id: int32, name: string(32))
        }],
      [<<~SRC,
        #include <stdint.h>
        struct record_s {
          uint32_t a;
          uint64_t b;
        } __attribute__((aligned(8)));
      SRC
        {
          record_s: struct(a: uint32,
            __pad_4: string(4, trim: false),
            b: uint64)
        }],
      [<<~SRC,
        typedef struct {
          int id;
          unsigned char name[32];
        } record_t;
      SRC
        {
          record_t: struct(id: int32, name: array(uint8, 32))
        }],
      [<<~SRC,
        typedef struct {
          int id;
          struct { int a; } nested;
         } record_t;
      SRC
        {
          record_t: struct(id: int32, nested: struct(a: int32))
        }],
      [<<~SRC,
        typedef union {
          int id;
          char name[32];
        } record_t;
      SRC
        {
          record_t: union(id: int32, name: string(32))
        }],
      [<<~SRC,
        enum state {
          STATE_INVALID = 0,
          STATE_RUNNING,
          STATE_MAX,
        };
      SRC
        {
          state: enum(state_invalid: 0, state_running: 1, state_max: 2)
        }]
    ].each do |(src, types)|
      context src.gsub(/\n/m, "\n  ") do
        types.each_pair do |name, type|
          it ".%s # => %p" % [name, type] do
            mod = described_class.load_source(src)
            expect(mod).to have_attributes(name => type)
          end
        end
      end
    end
  end
end
