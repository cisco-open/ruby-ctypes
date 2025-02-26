# CTypes Ruby Gem

[![Version](https://img.shields.io/gem/v/ctypes.svg)](https://rubygems.org/gems/ctypes)
[![GitHub](https://img.shields.io/badge/github-elf__utils-blue.svg)](http://github.com/cisco-open/ruby-ctypes)
[![Documentation](https://img.shields.io/badge/docs-rdoc.info-blue.svg)](http://rubydoc.info/gems/ctypes/frames)

[![Contributor-Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-fbab2c.svg)](CODE_OF_CONDUCT.md)
[![Maintainer](https://img.shields.io/badge/Maintainer-Cisco-00bceb.svg)](https://opensource.cisco.com)

Manipulate common C types in Ruby.

- unpack complex binary data into ruby types, modify, and repack them as binary 
- bounds checking on types (when packing)
- complex types supported
    - structs with flexible array members
    - arrays terminated by specific values
    - strings terminated by a specific byte sequence
- flexible endian support
    - default endian globally configurable; defaults to host endian
    - individual types can have fixed-endian
    - structs support per attribute endian
- minimal reserved words for Union and Struct types
    - want to avoid colliding with struct & union field names so you don't have
      to rename fields like `len`
- reloadable type definitions (pry `reload-code` friendly)
    - useful for using REPL-based development

## Comparisons
- BinData gem:
    - Tightly coupled with file I/O
    - no support for non-blocking I/O (non-blocking network sockets)
    - reserves common struct attribute names such as `len`
    - does not support reloading of types (pry `reload-code`)
- Fiddle gem:
    - only supports native endian
    - no support for dynamically sized & terminated types

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add ctypes

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install ctypes

## Usage

### Basic types
```ruby
require "ctypes"

# load optional helpers for common types
include CTypes::Helpers

# common integer types all defined: uint64, int64, ..., uint8, int8
# can be used to pack and unpack values
uint32.pack(0xfeedface)                     # => "\xce\xfa\xed\xfe"
uint32.pack(0xfeedface, endian: :big)       # => "\xfe\xed\xfa\xce"
uint32.unpack("\xce\xfa\xed\xfe")           # => 0xfeedface
uint32.unpack("\xfe\xed\xfa\xce", endian: :big)
                                            # => 0xfeedface

# `unpack_one` can be used to manually unpack sequential types from a string. # We recommend using `CTypes::Struct` for complex types, but this approach
# can be useful when exploring binary data.
buf = "\xaa\xbb\xcc\xdd\x11\x22"
word, buf = uint32.unpack_one(buf)          # => [0xddccbbaa, "\x11\x22"]
hword, buf = uint16.unpack_one(buf)         # => [0x2211, ""]

# create fixed-endian types from existing types
u32be = uint32.with_endian(:big)
u32be.pack(0xfeedface)                      # => "\xfe\xed\xfa\xce"

# c strings (char[], uint8[], int8[]) supported by string
string.unpack("hello world\0\0\0\0")        # => "hello world"
string.pack("hello world")                  # => "hello world"

# note: by default strings are greedy; they will consume all bytes in the
# input, but only return the bytes up to the first null byte
string.unpack("first\0second\0")            # => ["first", ""]

# to unpack null-terminated strings use string.terminated
_, rest = string.terminated.unpack("first\0second\0")
                                            # => ["first", "second\x00"]
string.terminated.unpack(rest)              # => ["second", ""]
string.terminated.pack("first")             # => "first\0"

# other bytes can be used to terminate strings
t = string.terminated("\xff")
t.unpack("test\xff")                        # => "test"
t.pack("hello\0world")                      # => "hello\x00world\xFF"

# along with byte sequences
t = string.terminated("STOP")
t.unpack("this is the messageSTOPnext messageSTOP")
                                            # => "this is the message"
t.pack("this is a reply")                   # => "this is a replySTOP"

# fixed-width string (char[16])
string(16).pack("hello world")              # => "hello world\0\0\0\0\0"
string(16).unpack("hello world\0\0\0\0\0")  # => "hello world\0\0\0\0\0"
string(16).unpack("hello world")            # => Exception raised

# fixed-width string, but preserve null bytes when unpacking
char_16 = string(16, trim: false)
char_16.unpack("hello world\0\0\0\0\0")     # => "hello world\0\0\0\0\0"
char_16.pack("hello world")                 # => "hello world\0\0\0\0\0"

```

### Arrays
```ruby
require "ctypes"
include CTypes::Helpers

# fixed-length arrays
pair = array(uint32, 2)
pair.unpack("\x01\x02\x03\x04\x05\x06\x07\x08")
                                            # => [0x04030201, 0x08070605]
pair.unpack("\x01\x02\x03\x04\x05\x06\x07\x08\xff\xff\xff\xff")
                                            # => [0x04030201, 0x08070605]

# dynamic length (greedy) arrays
bytes = array(uint8)
bytes.unpack("hello")                       # => [104, 101, 108, 108, 111]
bytes.unpack("\1\2\3")                      # => [1, 2, 3]
bytes.pack([4,5,6])                         # => "\4\5\6"

# any type can be converted to a fixed-endian type
be_pair = pair.with_endian(:big)
be_pair.unpack("\x01\x02\x03\x04\x05\x06\x07\x08")
                                            # => [0x01020304, 0x05060708]

# and it can be done for the inner type too
be_pair_inner = array(uint8.with_endian(:big))
be_pair_inner.unpack("\x01\x02\x03\x04\x05\x06\x07\x08")
                                            # => [0x01020304, 0x05060708]

# array of null-terminated strings, terminated by an empty string
strings = array(string.terminated("\0"), terminator: "")
strings.unpack("first\0second\0third\0\0")
                                            # => ["first", "second", "third"]

# array of integers, terminated by -1
ints = array(int8, terminator: -1)
ints.pack([1, 2, 3, 4])                     # => "\x01\x02\x03\x04\xFF"
ints.unpack("\x01\x02\x03\x04\xFFtail")     # => [1, 2, 3, 4]
ints.unpack_one("\x01\x02\x03\x04\xFFtail") # => [[1, 2, 3, 4], "tail"]

# array of structs; terminated by the :end type
type = struct do
  attribute :type, enum(uint8, %i[record end])
  attribute :value, uint32
end
records = array(type, terminator: {type: :end, value: 0})
records.pack([{type: :record, value: 0xffff}])
                            # => "\x00\xFF\xFF\x00\x00\x01\x00\x00\x00\x00"
records.unpack("\x00\xFF\xFF\x00\x00\x01\x00\x00\x00\x00")
                            # => struct {
                            #       .type = :record,
                            #       .value = 65535 (0xffff), }
```

### Enums
```ruby
require "ctypes"
include CTypes::Helpers

# default enum is uint32, start numbering at zero
state = enum(%i[invalid running sleep blocked])
state.pack(:running)                        # => "\1\0\0\0"

# can use other integer types
state = enum(uint8, %i[invalid running sleep blocked])
state.pack(:running)                        # => "\1"

# can be sparse
state = enum(uint8, {invalid: 0, running: 5, sleep: 6, blocked: 0xff})
state.pack(:blocked)                        # => "\xff"

# same as above with block syntax
state = enum(uint8) do |e|
  e << :invalid
  e << {running: 5}
  e << :sleep # assigned value 6
  e << {blocked: 0xff}
end
state.pack(:blocked)                        # => "\xff"
```

### Structures
```ruby
# Declare a TLV struct.  Size of each structure is determined by the `len`
# field.
class TLV < CTypes::Struct
  layout do
    endian :big     # all fields will use network-byte order
    attribute :type, enum(uint8, %i[invalid hello read write goodbye])
    attribute :len, uint32
    attribute :value, string
    # dynamically determine the size of the struct when unpacking
    size { |struct| offsetof(:value) + struct[:len] }
  end
end

# pack the tlv struct
version = "v1.0"
TLV.pack({type: :hello, len: version.size, value: version})
                                    # => "\x01\x04\x00\x00\x00v1.0"

# unpack a binary structure
msg = TLV.unpack("\x01\x04\x00\x00\x00v1.0")
msg.type                            # => :hello
msg.value                           # => "v1.0"

# modify the structure and repack into binary representation
msg.type = :goodbye
msg.len = 0
msg.to_binstr                       # => "\x04\x00\x00\x00\x00"
```

### Unions
Note: because the underlying memory for union values is not shared between each
member, accessing multiple members in a union does have a performance penalty
to pack the existing member and unpack the new member.  This penalty can be
avoided for read-only unions by freezing the union instance.

```ruby
class Msg < CTypes::Union
  layout do
    endian :big # network byte-order

    type = enum(uint8, {invalid: 0, hello: 1, read: 2})
    member :hello, struct({type:, version: string})
    member :read, struct({type:, offset: uint64, len: uint64})
    member :type, type
  end
end

# provide only one member when packing
Msg.pack({hello: {type: :hello, version: "v1.0"}})    # => "\x01v1.0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
Msg.pack({read: {type: :read, offset: 0xfeed, len: 0xdddd}}) # => "\x02\x00\x00\x00\x00\x00\x00\xFE\xED\x00\x00\x00\x00\x00\x00\xDD\xDD"

# unpack a message and access member values
msg = Msg.unpack("\x02" +
                 "\xfe\xfe\xfe\xfe\xfe\xfe\xfe\xfe" +
                 "\xab\xab\xab\xab\xab\xab\xab\xab")
msg.type                      # => :read
msg.read.offset               # => 18374403900871474942
msg.read.len                  # => 12370169555311111083

# modify and pack into binary
msg.hello.type = :hello
msg.hello.version = "v1.0"
msg.to_binstr                 # => "\x01v1.0\xFE\xFE\xFE\xFE\xAB\xAB\xAB\xAB\xAB\xAB\xAB\xAB"
```

### Terminated
Some greedy dynamic length types are terminated with byte sequences, or
variable byte sequences.  To handle these types we use CTypes::Terminated.

```ruby
# string.terminated returns a CTypes::Terminated instance
telegram = string.terminated("STOP")
telegrams = array(telegram)
telegrams.unpack("hello worldSTOPnext messageSTOP")
                              # => ["hello world", "next message"]


# record is an id along with an array of data bytes
record = struct({id: uint8, data: array(uint8)})
# each record is terminated with the byte sequence \xff\xee (for reasons?)
term = "\xff\xee"
# create a terminated type for the record (yea, it is ugly right now)
terminated_record = CTypes::Terminated
    .new(type: record,
         locate: proc { |b,_| [b.index(term), term.size] },
         terminate: term)
# and then an array of terminated records type
records = array(terminated_record)

# now pack & unpack as needed
records.pack([
    {id: 1, data: [1, 2, 3, 4]},
    {id: 2, data: [5, 5]},
    {id: 3}
])          # => "\x01\x01\x02\x03\x04\xFF\xEE\x02\x05\x05\xFF\xEE\x03\xFF\xEE"
records.unpack("\x01\x01\x02\x03\x04\xFF\xEE\x02\x05\x05\xFF\xEE\x03\xFF\xEE")
            # => [#<struct id=1, data=[1, 2, 3, 4]>,
            #     #<struct id=2, data=[5, 5]>,
            #     #<struct id=3, data=[]>]
```

### Custom Types
Custom types can be created then used within other CTypes. The following is an
custom CTypes implementation of the DWARF ULEB128 datatype.  It is a compressed
representation of a 128-bit integer that uses 7 bits per byte for the encoded
value, with the highest bit set on the last byte of the value. The bytes are
stored in little endian order.

```ruby
module ULEB128
  extend CTypes::Type

  # declare the underlying DRY type; it must have a default value, and may
  # have constraints set
  @dry_type = Dry::Types["integer"].default(0)

  # as this is a dynamically sized type, let's set size to be the minimum size
  # for the type (1 byte), and ensure .fixed_size? returns false
  @size = 1
  def self.fixed_size?
    false
  end

  # provide a method for packing the ruby value into the binary representation
  def self.pack(value, endian: default_endian, validate: true)
    return "\x80" if value == 0
    buf = String.new
    while value != 0
      buf << (value & 0x7f)
      value >>= 7
    end
    buf[-1] = (buf[-1].ord | 0x80).chr
    buf
  end

  # provide a method for unpacking an instance of this type from a String, and
  # returning both the unpacked value, and any unused input
  def self.unpack_one(buf, endian: default_endian)
    value = 0
    shift = 0
    len = 0
    buf.each_byte do |b|
      len += 1
      value |= ((b & 0x7f) << shift)
      return value, buf[len...] if (b & 0x80) != 0
      shift += 7
    end
    raise TerminatorNotFoundError
  end
end

# now the type can be used like any other type
ULEB128.unpack_one("\x7f\x7f\x83XXX")       # => [0xffff, "XXX"]
ULEB128.unpack("\x7f\x7f\x83")              # => 0xffff
ULEB128.unpack("\x81XXX")                   # => 1
ULEB128.pack(0)                             # => "\x80"
ULEB128.pack(1)                             # => "\x81"
ULEB128.pack(0xffff)                        # => "\x7F\x7F\x83"

# use it in an array
list = array(ULEB128)
list.unpack("\x7f\x7f\x83\x81\x80")         # => [65535, 1, 0]

# or a struct
t = struct(id: uint32, value: ULEB128)
t.unpack("\1\0\0\0\x7f\x7f\x83XXX")         # => #<struct id=1, value=65535>
```

## Roadmap

See the [open issues](https://github.com/cisco-open/ruby-ctypes/issues) for a
list of proposed features (and known issues).

## Development

After checking out the repo, run `bundle install` to install dependencies.
Then, run `rake spec` to run the tests. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and the created tag, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Contributions are what make the open source community such an amazing place to
learn, inspire, and create. Any contributions you make are **greatly
appreciated**. For detailed contributing guidelines, please see
[CONTRIBUTING.md](CONTRIBUTING.md)

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
License. See [LICENSE.txt](LICENSE.txt) for more information.
