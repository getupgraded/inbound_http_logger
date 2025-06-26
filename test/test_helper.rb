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

require 'inbound_http_logger'

# Set up in-memory SQLite database for testing
# Note: We use establish_connection here only for the main test suite
# This is acceptable in test helpers but should not be done in production gem code
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

# Configure the gem to use the default connection in tests
# This ensures all tests use the same in-memory database with the table
module InboundHTTPLogger
  module Test
    def self.configure(adapter:, connection_string: nil)
      # In test mode, explicitly configure the gem to use the default connection
      # This ensures all tests use the same in-memory database with the table
      case adapter
      when :sqlite
        InboundHTTPLogger.configure do |config|
          config.enabled = true
          config.adapter = :sqlite
          # Don't set database_url - this will make the adapter use the default connection
          config.database_url = nil
        end
      when :postgresql
        InboundHTTPLogger.configure do |config|
          config.enabled = true
          config.adapter = :postgresql
          # Don't set database_url - this will make the adapter use the default connection
          config.database_url = nil
        end
      end
    end
  end
end

# Test helper methods for gem internal tests
module TestHelpers
  def setup
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

    # Clear all logs (only if table exists)
    InboundHTTPLogger::Models::InboundRequestLog.delete_all if ActiveRecord::Base.connection.table_exists?(:inbound_request_logs)

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
    InboundHTTPLogger.clear_all_thread_data
  end

  def with_logging_enabled
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
end

# Include test helpers in all test classes
Minitest::Test.include(TestHelpers)
Minitest::Spec.include(TestHelpers)
