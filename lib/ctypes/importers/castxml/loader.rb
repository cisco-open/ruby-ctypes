# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

require "nokogiri"

module CTypes
  class Importers::CastXML::Loader
    include CTypes::Helpers

    def initialize(io)
      @doc = Nokogiri.parse(io)
      @xml = @doc.xpath("//castxml[1]")&.first or
        raise Error, "<castxml> node not found"
      @nodes = @xml.xpath("./*[@id]").each_with_object({}) { |n, o|
        o[n[:id]] = n
      }
      @ctypes = {}
    end
    attr_reader :xml

    def load
      m = Module.new
      load_into(m)
    end

    def load_into(namespace)
      @xml.children.each do |node|
        next unless node.element?

        case node.name
        when "typedef", "struct", "union", "array", "enumeration"
          # skip builtin types
          next if node[:file] == "f0"

          name, type = ctype(node[:id])
          next if name.empty?

          namespace.define_singleton_method(name) { type }
        end
      end

      namespace
    end

    private

    def ctype(id)
      return @ctypes[id] if @ctypes.has_key?(id)
      node = @nodes[id] or raise Error, "node not found: id=\"#{id}\""

      return node[:name], nil if node[:incomplete] == "1"

      type = case node.name
      when "fundamentaltype"
        unsigned = node[:name].include?("unsigned")
        case node[:size]
        when "0"
          nil
        when "128"
          array(unsigned ? uint64 : int64, 2)
        when "64"
          unsigned ? uint64 : int64
        when "32"
          unsigned ? uint32 : int32
        when "16"
          unsigned ? uint16 : int16
        when "8"
          unsigned ? uint8 : int8
        else
          raise Error, "unknown FundamentalType: %s" % node.pretty_inspect
        end
      when "typedef", "field", "elaboratedtype", "cvqualifiedtype"
        _, t = ctype(node[:type])
        t
      when "struct"
        if node.has_attribute?("members")
          pos = 0
          members = node[:members].split.each_with_object({}) do |mid, o|
            # to support member alignment, we need to do some extra work here
            # to add padding members to structures when there are gaps.  Note
            # that for some reason, anonymous structs are not counted towards
            # the offset of following struct fields; this may be a bug in llvm,
            # as castxml just prints what was provided.
            mem = @nodes[mid] or raise Error, "node not found: id=\"#{mid}\""
            if mem.has_attribute?("offset")

              # add a padding member to the struct if needed
              offset = mem[:offset].to_i
              if pos < offset
                o[:"__pad_#{pos / 8}"] =
                  string((offset - pos) / 8, trim: false)
              end

              # always set pos to the current offset; this handles the case
              # where we added the size of a nested anonymous struct, but llvm
              # does not appear to.
              pos = offset
            end

            name, mtype = ctype(mid)
            o[name.to_sym] = mtype unless name.empty?
            pos += mtype.size * 8
          end
        else
          members = {unknown: array(uint8, node[:size].to_i)}
        end
        struct(members)
      when "union"
        members = node[:members].split.each_with_object({}) do |mid, o|
          name, mtype = ctype(mid)
          o[name.to_sym] = mtype
        end
        union(members)
      when "arraytype"
        n, t = ctype(node[:type])
        if n == "char"
          string(node[:max].to_i + 1)
        else
          array(t, node[:max].to_i + 1)
        end
      when "enumeration"
        values = node.children.each_with_object({}) do |v, o|
          o[v[:name].downcase] = v[:init].to_i if v.name == "enumvalue"
        end
        type = if node[:type]
          _, t = ctype(node[:type])
          t
        elsif node[:size] == "32"
          uint32
        else
          raise Error, "unsupported enum node: %p" % node
        end
        enum(type, values)
      when "pointertype"
        case node[:size]
        when "64"
          uint64
        when "32"
          uint32
        else
          raise Error, "unknown PointerType size: %s" % node.pretty_inspect
        end
      else
        raise "unsupported node: %s" % node.pretty_inspect
      end

      @ctypes[id] = [node[:name], type]
    end
  end
end
