# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

task default: %i[spec standard]

task :debug do
  puts <<~END % [`ls`, `cat .rspec`]
    files:
    %s

    .rspec:
    %s
  END
end
