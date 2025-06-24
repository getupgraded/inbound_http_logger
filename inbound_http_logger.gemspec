# frozen_string_literal: true

require_relative "lib/inbound_http_logger/version"

Gem::Specification.new do |spec|
  spec.name = "inbound_http_logger"
  spec.version = InboundHttpLogger::VERSION
  spec.authors = ["Ziad Sawalha"]
  spec.email = ["ziad@getupgraded.com"]

  spec.summary = "Comprehensive inbound HTTP request logging for Rails applications"
  spec.description = "A gem for logging inbound HTTP requests with Rack middleware, controller-level filtering, and configurable security features."
  spec.homepage = "https://github.com/getupgraded/inbound_http_logger"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob("lib/**/*") + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ["lib"]
  spec.extra_rdoc_files = ["LICENSE.txt"]

  # Runtime dependencies
  spec.add_dependency "activerecord", ">= 7.2.0"
  spec.add_dependency "activesupport", ">= 7.2.0"
  spec.add_dependency "rack", ">= 2.0"
  spec.add_dependency "railties", ">= 7.2.0"

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "mocha", "~> 2.0"
  spec.add_development_dependency "rails", ">= 7.2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.75"
  spec.add_development_dependency "rubocop-md", "~> 2.0"
  spec.add_development_dependency "rubocop-minitest", "~> 0.38"
  spec.add_development_dependency "rubocop-packaging", "~> 0.6"
  spec.add_development_dependency "rubocop-performance", "~> 1.18"
  spec.add_development_dependency "rubocop-rails", "~> 2.31"
  spec.add_development_dependency "rubocop-rake", "~> 0.7"
  spec.add_development_dependency "rubocop-thread_safety", "~> 0.7"
  spec.add_development_dependency "sqlite3", ">= 2.1"
  spec.add_development_dependency 'webmock', '~> 3.0'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
