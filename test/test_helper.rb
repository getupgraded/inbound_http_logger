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
require 'rack/mock'

# Load Rails test framework for better test isolation and parallelization control
require 'active_support/test_case'

require 'inbound_http_logger'

# Set up in-memory SQLite database for testing
# Note: We use establish_connection here only for the main test suite
# This is acceptable in test helpers but should not be done in production gem code
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

# Configure ActiveSupport::TestCase for better test isolation
# Disable parallelization by default - individual test classes can override this
ActiveSupport::TestCase.parallelize(workers: 0)

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

# Configure the gem to use the default connection in tests
# This ensures all tests use the same in-memory database with the table
# Note: The actual InboundHTTPLogger::Test.configure method now handles
# enabling the main configuration automatically

# Test helper methods for gem internal tests
module TestHelpers
  def setup
    # Disable logging completely first to prevent infinite recursion during setup
    InboundHTTPLogger.disable!

    # Ensure table exists (for tests that might run in isolation)
    ensure_test_table_exists!

    # Reset configuration to defaults
    InboundHTTPLogger.reset_configuration!

    # Reset database adapter cache
    InboundHTTPLogger::Models::InboundRequestLog.reset_adapter_cache!

    # Reset global configuration to defaults but don't nil it
    config = InboundHTTPLogger.global_configuration
    config.enabled = false
    config.debug_logging = false
    config.max_body_size = 10_000

    # Reset excluded paths to defaults (these are Sets, so we need to clear and add)
    config.excluded_paths.clear
    config.excluded_paths.merge([
                                  %r{^/assets/},
                                  %r{^/packs/},
                                  %r{^/health$},
                                  %r{^/ping$},
                                  %r{^/favicon\.ico$},
                                  %r{^/robots\.txt$},
                                  %r{^/sitemap\.xml$},
                                  /\.css$/,
                                  /\.js$/,
                                  /\.map$/,
                                  /\.ico$/,
                                  /\.png$/,
                                  /\.jpg$/,
                                  /\.jpeg$/,
                                  /\.gif$/,
                                  /\.svg$/,
                                  /\.woff$/,
                                  /\.woff2$/,
                                  /\.ttf$/,
                                  /\.eot$/
                                ])

    # Reset excluded content types to defaults
    config.excluded_content_types.clear
    config.excluded_content_types.merge([
                                          'text/html',
                                          'text/css',
                                          'text/javascript',
                                          'application/javascript',
                                          'application/x-javascript',
                                          'image/png',
                                          'image/jpeg',
                                          'image/gif',
                                          'image/svg+xml',
                                          'image/webp',
                                          'image/x-icon',
                                          'video/mp4',
                                          'video/webm',
                                          'audio/mpeg',
                                          'audio/wav',
                                          'font/woff',
                                          'font/woff2',
                                          'application/font-woff',
                                          'application/font-woff2'
                                        ])

    # Reset sensitive headers to defaults
    config.sensitive_headers.clear
    config.sensitive_headers.merge(%w[
                                     authorization
                                     cookie
                                     set-cookie
                                     x-api-key
                                     x-auth-token
                                     x-access-token
                                     bearer
                                     x-csrf-token
                                     x-session-id
                                   ])

    # Reset sensitive body keys to defaults
    config.sensitive_body_keys.clear
    config.sensitive_body_keys.merge(%w[
                                       password
                                       secret
                                       token
                                       key
                                       auth
                                       credential
                                       private
                                       ssn
                                       social_security_number
                                       credit_card
                                       card_number
                                       cvv
                                       pin
                                     ])

    # Reset excluded controllers to defaults
    config.excluded_controllers.clear
    config.excluded_controllers.merge([
                                        'rails/health',
                                        'rails/info',
                                        'action_cable/internal'
                                      ])

    # Disable logging first to prevent any middleware interference
    InboundHTTPLogger.disable!

    # Clear all logs (only if table exists)
    if ActiveRecord::Base.connection.table_exists?(:inbound_request_logs)
      # Use direct SQL to avoid any potential ActiveRecord callbacks or instrumentation issues
      ActiveRecord::Base.connection.execute('DELETE FROM inbound_request_logs')
    end

    # Enable logging by default for tests (individual tests can disable if needed)
    InboundHTTPLogger.enable!

    # Reset WebMock
    WebMock.reset!
    WebMock.disable_net_connect!
  end

  def teardown
    # Optional: Check for leftover thread-local data before cleanup
    # This helps identify tests that don't clean up properly
    # Enable with: STRICT_TEST_ISOLATION=true
    if ENV['STRICT_TEST_ISOLATION'] == 'true'
      begin
        assert_no_leftover_thread_data!
      rescue StandardError => e
        # Log the error but don't fail the test - just warn
        puts "\n⚠️  #{e.message}"
      end
    end

    # Disable logging
    InboundHTTPLogger.disable!

    # Clear thread-local data (use comprehensive cleanup in teardown)
    InboundHTTPLogger.clear_thread_data

    # Reset database adapter cache to ensure test isolation
    InboundHTTPLogger::Models::InboundRequestLog.reset_adapter_cache!
  end

  # Ensure compatibility with both Test::Unit and Spec styles
  # Test::Unit style aliases for before/after blocks
  alias before setup
  alias after teardown

  # Add proper Minitest::Spec hooks support
  def self.included(base)
    # Only add hooks for Minitest::Spec classes
    return unless base.respond_to?(:before) && base.respond_to?(:after)

    base.before { setup }
    base.after { teardown }
  end

  def with_inbound_http_logging_enabled
    InboundHTTPLogger.enable!
    yield
  ensure
    InboundHTTPLogger.disable!
  end

  # Thread-safe configuration override for simple attribute changes
  # This is the recommended method for parallel testing
  def with_thread_safe_configuration(**overrides, &block)
    InboundHTTPLogger.with_configuration(**overrides, &block)
  end

  def assert_request_logged(method, url, status_code = nil)
    logs = InboundHTTPLogger::Models::InboundRequestLog.where(
      http_method: method.to_s.upcase,
      url: url
    )

    logs = logs.where(status_code: status_code) if status_code

    assert_predicate logs, :exists?, "Expected request to be logged: #{method.upcase} #{url}"
    logs.first
  end

  def assert_no_request_logged(method = nil, url = nil)
    scope = InboundHTTPLogger::Models::InboundRequestLog.all
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

  private

    def ensure_test_table_exists!
      return if ActiveRecord::Base.connection.table_exists?(:inbound_request_logs)

      # Create the table if it doesn't exist
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
    end
end

# Base test class using ActiveSupport::TestCase for better Rails integration
# This provides better test isolation and parallelization control
class InboundHTTPLoggerTestCase < ActiveSupport::TestCase
  include TestHelpers

  # Disable parallelization for this base class - individual test classes can override
  parallelize(workers: 0)
end

# Include test helpers in all test classes
Minitest::Test.include(TestHelpers)
Minitest::Spec.include(TestHelpers)

# Check for leftover thread-local data and raise descriptive errors
# This helps identify tests that don't clean up properly
def assert_no_leftover_thread_data!
  leftover_data = {}

  # Check all known InboundHTTPLogger thread-local variables
  thread_vars = {
    inbound_http_logger_config_override: Thread.current[:inbound_http_logger_config_override],
    inbound_http_logger_metadata: Thread.current[:inbound_http_logger_metadata],
    inbound_http_logger_loggable: Thread.current[:inbound_http_logger_loggable]
  }

  thread_vars.each do |key, value|
    leftover_data[key] = value unless value.nil?
  end

  return if leftover_data.empty?

  raise "Thread-local data not cleaned up: #{leftover_data.keys.join(', ')}"
end
