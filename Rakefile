# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  # Run middleware tests first, then other tests (exclude test_helper.rb)
  t.test_files = FileList["test/middleware/test_*.rb", "test/models/test_*.rb", "test/concerns/test_*.rb", "test/test_inbound_http_logger.rb"]
  t.verbose    = true
end

task default: :test
