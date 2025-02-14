# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

require "open3"
begin
  require "nokogiri"
rescue LoadError
  puts <<~ERR
    WARNING: Failed to require `nokogiri` gem.
    
    `nokogiri` is required to parse CastXML output.  To use the CastXML
    importer, please install the gem.
  ERR
end

module CTypes
  module Importers
    module CastXML
      class CompilerError < CTypes::Error; end

      def self.load_xml(xml)
        io = case xml
        when IO
          xml
        when ::String
          StringIO.new(xml)
        else
          raise Error, "arg must be IO or String: %p" % xml
        end

        l = Loader.new(io)
        l.load
      end

      def self.load_xml_file(path)
        File.open(path) do |f|
          load_xml(f)
        end
      end

      def self.load_source(src)
        Tempfile.open(["", ".c"]) do |f|
          f.write(src)
          f.flush
          load_source_file(f.path)
        end
      end

      def self.load_source_file(path)
        stdout, stderr, status = Open3
          .capture3("castxml --castxml-output=1 #{path} -o -")
        raise CompilerError, stderr unless status.success?
        load_xml(stdout)
      end
    end
  end
end

require_relative "castxml/loader"
