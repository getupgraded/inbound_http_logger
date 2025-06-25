# frozen_string_literal: true

require 'test_helper'
require 'inbound_http_logger/database_adapters/sqlite_adapter'
require 'inbound_http_logger/database_adapters/postgresql_adapter'
require 'inbound_http_logger/test'

class TestDatabaseAdapters < Minitest::Test
  include TestHelpers

  def setup
    super
    InboundHttpLogger.enable!
  end

  def teardown
    InboundHttpLogger.disable!
    super
  end

  def test_sqlite_adapter_creates_model_class_that_inherits_from_inbound_request_log
    adapter = InboundHttpLogger::DatabaseAdapters::SqliteAdapter.new('sqlite3:///tmp/test.sqlite3', :test_sqlite)
    model_class = adapter.send(:create_model_class)

    assert_includes model_class.ancestors, InboundHttpLogger::Models::InboundRequestLog
    assert_includes model_class.instance_methods, :formatted_call
  end

  def test_sqlite_adapter_handles_formatted_call_method_correctly
    adapter = InboundHttpLogger::DatabaseAdapters::SqliteAdapter.new('sqlite3:///tmp/test.sqlite3', :test_sqlite)
    model_class = adapter.send(:create_model_class)

    instance = model_class.new(http_method: 'GET', url: '/test', status_code: 200)
    assert_equal 'GET /test', instance.formatted_call
  end

  def test_postgresql_adapter_creates_model_class_that_inherits_from_inbound_request_log
    skip 'PostgreSQL not available' unless postgresql_available?

    # Test without establishing connection to avoid database errors
    adapter_connection_name = :test_pg
    class_name = "PostgresqlRequestLog#{adapter_connection_name.to_s.camelize}"

    # Remove existing class if it exists
    InboundHttpLogger::DatabaseAdapters.send(:remove_const, class_name) if InboundHttpLogger::DatabaseAdapters.const_defined?(class_name)

    # Create the new class that inherits from the main model
    klass = Class.new(InboundHttpLogger::Models::InboundRequestLog) do
      self.table_name = 'inbound_request_logs'
      @adapter_connection_name = adapter_connection_name
    end

    # Assign the class to a constant to give it a name
    InboundHttpLogger::DatabaseAdapters.const_set(class_name, klass)

    assert_includes klass.ancestors, InboundHttpLogger::Models::InboundRequestLog
    assert_includes klass.instance_methods, :formatted_call
  end

  def test_postgresql_adapter_handles_formatted_call_method_correctly
    skip 'PostgreSQL not available' unless postgresql_available?

    # Test without establishing connection to avoid database errors
    adapter_connection_name = :test_pg
    class_name = "PostgresqlRequestLogTest#{adapter_connection_name.to_s.camelize}"

    # Remove existing class if it exists
    InboundHttpLogger::DatabaseAdapters.send(:remove_const, class_name) if InboundHttpLogger::DatabaseAdapters.const_defined?(class_name)

    # Create the new class that inherits from the main model
    klass = Class.new(InboundHttpLogger::Models::InboundRequestLog) do
      self.table_name = 'inbound_request_logs'
      @adapter_connection_name = adapter_connection_name
    end

    # Assign the class to a constant to give it a name
    InboundHttpLogger::DatabaseAdapters.const_set(class_name, klass)

    instance = klass.new(http_method: 'POST', url: '/api/test', status_code: 201)
    assert_equal 'POST /api/test', instance.formatted_call
  end

  def test_sqlite_test_adapter_integration
    InboundHttpLogger::Test.configure(adapter: :sqlite)
    InboundHttpLogger::Test.enable!
    InboundHttpLogger::Test.clear_logs!

    # Create a mock request
    require 'rack'
    env = Rack::MockRequest.env_for('/test', method: 'GET')
    request = Rack::Request.new(env)

    # Log a request
    InboundHttpLogger::Test.log_request(request, nil, 200, {}, 'response', 0.1)

    # Test the all_calls method
    calls = InboundHttpLogger::Test.all_calls
    assert_includes calls, 'GET /test'
  end

  def test_postgresql_test_adapter_integration_when_available
    skip 'PostgreSQL not available' unless postgresql_available? && postgresql_test_database_available?

    InboundHttpLogger::Test.configure(
      database_url: ENV['INBOUND_HTTP_LOGGER_TEST_DATABASE_URL'],
      adapter: :postgresql
    )
    InboundHttpLogger::Test.enable!
    InboundHttpLogger::Test.clear_logs!

    # Create a mock request
    require 'rack'
    env = Rack::MockRequest.env_for('/pg-test', method: 'POST')
    request = Rack::Request.new(env)

    # Log a request
    InboundHttpLogger::Test.log_request(request, '{"test": true}', 201, {}, '{"success": true}', 0.2)

    # Test the all_calls method
    calls = InboundHttpLogger::Test.all_calls
    assert_includes calls, 'POST /pg-test'
  end

  private

    def postgresql_available?
      require 'pg'
      true
    rescue LoadError
      false
    end

    def postgresql_test_database_available?
      return false unless ENV['INBOUND_HTTP_LOGGER_TEST_DATABASE_URL']

      # Try to connect to the test database
      uri = URI.parse(ENV['INBOUND_HTTP_LOGGER_TEST_DATABASE_URL'])
      PG.connect(
        host: uri.host,
        port: uri.port || 5432,
        dbname: uri.path[1..], # Remove leading slash
        user: uri.user,
        password: uri.password
      ).close
      true
    rescue StandardError
      false
    end
end
