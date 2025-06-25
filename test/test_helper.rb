# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'minitest/spec'
require 'mocha/minitest'
require 'webmock/minitest'
require 'active_record'
require 'sqlite3'
require 'rails'
require 'action_controller'

require 'inbound_http_logger'

# Set up in-memory SQLite database for testing
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

# Create the inbound_request_logs table
ActiveRecord::Schema.define do
  create_table :inbound_request_logs do |t|
    # Request information
    t.string :request_id, index: true
    t.string :http_method, null: false
    t.text :url, null: false
    t.string :ip_address
    t.string :user_agent
    t.string :referrer

    # Request details
    t.json :request_headers, default: {}
    t.json :request_body

    # Response details
    t.integer :status_code, null: false
    t.json :response_headers, default: {}
    t.json :response_body

    # Performance metrics
    t.decimal :duration_seconds, precision: 10, scale: 6
    t.decimal :duration_ms, precision: 10, scale: 2

    # Polymorphic association
    t.references :loggable, polymorphic: true, type: :bigint

    # Metadata and timestamps
    t.json :metadata, default: {}
    t.timestamps

    # Indexes for common queries
    t.index :http_method
    t.index :status_code
    t.index :created_at
    t.index :ip_address
    t.index :duration_ms

    # Add a partial index for failed requests
    t.index :status_code, where: 'status_code >= 400', name: 'index_inbound_request_logs_on_failed_requests'
  end
end

# JSON columns are automatically handled in Rails 8.0+

# Test helper methods
module TestHelpers
  def setup
    # Clear thread-local configuration override first
    InboundHttpLogger.clear_configuration_override

    # Reset global configuration to defaults by creating a fresh one
    InboundHttpLogger.instance_variable_set(:@global_configuration, InboundHttpLogger::Configuration.new)

    # Configure with test defaults
    config = InboundHttpLogger.configuration
    config.enabled = false
    config.max_body_size = 10_000
    config.debug_logging = false

    # Clear all logs
    InboundHttpLogger::Models::InboundRequestLog.delete_all

    # Clear thread-local data
    InboundHttpLogger.clear_thread_data

    # Reset WebMock
    WebMock.reset!
    WebMock.disable_net_connect!
  end

  def teardown
    # Disable logging
    InboundHttpLogger.disable!

    # Clear thread-local data
    InboundHttpLogger.clear_thread_data
  end

  def with_logging_enabled
    InboundHttpLogger.enable!
    yield
  ensure
    InboundHttpLogger.disable!
  end

  # Thread-safe configuration override for simple attribute changes
  # This is the recommended method for parallel testing
  def with_thread_safe_configuration(**overrides, &block)
    InboundHttpLogger.with_configuration(**overrides, &block)
  end

  def assert_request_logged(method, url, status_code = nil)
    logs = InboundHttpLogger::Models::InboundRequestLog.where(
      http_method: method.to_s.upcase,
      url: url
    )

    logs = logs.where(status_code: status_code) if status_code

    assert logs.exists?, "Expected request to be logged: #{method.upcase} #{url}"
    logs.first
  end

  def assert_no_request_logged(method = nil, url = nil)
    scope = InboundHttpLogger::Models::InboundRequestLog.all
    scope = scope.where(http_method: method.to_s.upcase) if method
    scope = scope.where(url: url) if url

    assert_equal 0, scope.count, 'Expected no requests to be logged'
  end

  def create_rack_request(method: 'GET', path: '/', headers: {}, body: nil)
    env = Rack::MockRequest.env_for(path, method: method)

    # Add headers
    headers.each do |key, value|
      env["HTTP_#{key.upcase.tr('-', '_')}"] = value
    end

    # Add body and content type
    if body
      env['rack.input'] = StringIO.new(body)
      env['CONTENT_LENGTH'] = body.bytesize.to_s
      env['CONTENT_TYPE'] = headers['Content-Type'] if headers['Content-Type']
    end

    Rack::Request.new(env)
  end
end

# Include test helpers in all test classes
Minitest::Test.include(TestHelpers)
