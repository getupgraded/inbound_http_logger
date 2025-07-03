# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  # Run all test files (exclude test_helper.rb)
  t.test_files = FileList['test/**/*test*.rb'].exclude('test/test_helper.rb')
  t.verbose    = true
end

desc 'Run RuboCop'
task rubocop: :environment do
  sh 'bundle exec rubocop --config .rubocop.yml'
end

desc 'Run all quality checks'
task quality: %i[rubocop]

desc 'Run tests and quality checks'
task ci: %i[test quality]

desc 'Dummy environment task for gems'
task :environment

task default: :ci
