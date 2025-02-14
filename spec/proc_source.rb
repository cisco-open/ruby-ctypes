# SPDX-FileCopyrightText: 2025 Cisco
# SPDX-License-Identifier: MIT

require "dry/core/cache"
require "parser/current"

module ProcSource
  extend Dry::Core::Cache
  extend AST::Sexp

  class SourceNotFound < StandardError; end

  # parse a ruby source file and return the AST; result is cached
  def self.parse(path)
    fetch_or_store(path) do
      source_buffer = Parser::Source::Buffer.new(path).read
      parser = Parser::CurrentRuby.new
      parser.diagnostics.all_errors_are_fatal = true
      parser.diagnostics.ignore_warnings = true
      parser.parse(source_buffer)
    end
  end

  PROC_NODES = [
    s(:send, nil, :lambda),
    s(:send, nil, :proc),
    s(:send, s(:const, nil, :Proc), :new)
  ]

  module Helpers
    def source
      file, line = source_location
      root = ProcSource.parse(file)

      queue = [root]
      until queue.empty?
        node = queue.shift
        next unless node.is_a?(Parser::AST::Node)
        queue.unshift(*node.children)

        next unless node.type == :block
        next unless node.loc.line == line

        # verify this is lambda, proc, or Proc.new
        next unless ProcSource::PROC_NODES.include?(node.children.first)

        return node.loc.expression.source
      end

      raise SourceNotFound, "unable to find source for %p" % self
    end
  end

  Proc.prepend(Helpers)
end
