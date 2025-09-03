# frozen_string_literal: true

require 'test_helper'

class LoggingMiddlewareEnabledTest < InboundHTTPLoggerTestCase
  def setup
    super
    InboundHTTPLogger.enable!
    @app = ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{"success": true}']] }
    @middleware = InboundHTTPLogger::Middleware::LoggingMiddleware.new(@app)
  end

  def test_logs_successful_requests
    # Mock timing to ensure duration > 0
    start_time = 1000.0
    end_time = 1000.1
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(start_time, end_time)

    env = Rack::MockRequest.env_for('/users', method: 'GET')

    status, headers, = @middleware.call(env)

    assert_equal 200, status
    assert_equal 'application/json', headers['Content-Type']

    log = assert_request_logged(:get, '/users', 200)
    assert_equal 100.0, log.duration_ms
    assert_equal '{"success":true}', log.response_body
  end

  def test_logs_post_requests_with_request_body
    body = '{"name": "John"}'
    env = Rack::MockRequest.env_for('/users',
                                    method: 'POST',
                                    input: body,
                                    'CONTENT_TYPE' => 'application/json',
                                    'CONTENT_LENGTH' => body.bytesize.to_s)

    status, = @middleware.call(env)

    assert_equal 200, status

    log = assert_request_logged(:post, '/users', 200)
    assert_equal({ 'name' => 'John' }, log.request_body)
    assert_equal 'application/json', log.request_headers['Content-Type']
  end

  def test_logs_requests_with_headers
    env = Rack::MockRequest.env_for('/protected',
                                    method: 'GET',
                                    'HTTP_AUTHORIZATION' => 'Bearer token123',
                                    'HTTP_USER_AGENT' => 'Test Agent')

    status, = @middleware.call(env)

    assert_equal 200, status

    log = assert_request_logged(:get, '/protected', 200)
    assert_equal '[FILTERED]', log.request_headers['Authorization']
    assert_equal 'Test Agent', log.request_headers['User-Agent']
    assert_equal 'Test Agent', log.user_agent
  end

  def test_logs_failed_requests
    error_app = ->(_env) { [500, { 'Content-Type' => 'application/json' }, ['{"error": "Internal Server Error"}']] }
    error_middleware = InboundHTTPLogger::Middleware::LoggingMiddleware.new(error_app)

    env = Rack::MockRequest.env_for('/error', method: 'GET')

    status, = error_middleware.call(env)

    assert_equal 500, status

    log = assert_request_logged(:get, '/error', 500)
    assert_equal '{"error":"Internal Server Error"}', log.response_body
  end

  def test_skips_excluded_paths
    # Test that health check paths are excluded by default
    env = Rack::MockRequest.env_for('/health', method: 'GET')

    status, = @middleware.call(env)

    assert_equal 200, status
    # Health paths should NOT be logged (excluded by default)
    assert_no_request_logged
  end

  def test_skips_excluded_content_types
    # Test that CSS files are excluded by default
    env = Rack::MockRequest.env_for('/styles.css',
                                    method: 'GET',
                                    'HTTP_ACCEPT' => 'text/css')

    status, = @middleware.call(env)

    assert_equal 200, status
    # CSS files should NOT be logged (excluded by default)
    assert_no_request_logged
  end

  def test_handles_large_request_bodies
    # Create a large request body (over max_body_size)
    max_size = InboundHTTPLogger.configuration.max_body_size
    large_body = 'x' * (max_size + 1)
    env = Rack::MockRequest.env_for('/upload',
                                    method: 'POST',
                                    input: large_body,
                                    'CONTENT_TYPE' => 'text/plain',
                                    'CONTENT_LENGTH' => large_body.bytesize.to_s)

    status, = @middleware.call(env)

    assert_equal 200, status

    log = assert_request_logged(:post, '/upload', 200)
    # Large bodies should be nil (not logged)
    assert_nil log.request_body
  end

  def test_includes_metadata_from_thread_local_storage
    metadata = { user_id: 123, session_id: 'abc123' }
    InboundHTTPLogger.set_metadata(metadata)

    env = Rack::MockRequest.env_for('/users', method: 'GET')

    status, = @middleware.call(env)

    assert_equal 200, status

    log = assert_request_logged(:get, '/users', 200)
    assert_equal metadata.stringify_keys, log.metadata
  end

  def test_includes_controller_information_when_available
    # Mock controller
    controller = Object.new
    controller.stubs(:controller_name).returns('users')
    controller.stubs(:action_name).returns('show')

    env = Rack::MockRequest.env_for('/users/1', method: 'GET')
    env['action_controller.instance'] = controller

    status, = @middleware.call(env)

    assert_equal 200, status

    log = assert_request_logged(:get, '/users/1', 200)
    expected_metadata = {
      'controller' => 'users',
      'action' => 'show'
    }
    assert_equal expected_metadata, log.metadata
  end

  def test_handles_middleware_errors_gracefully
    error_app = ->(_env) { raise StandardError, 'Something went wrong' }
    error_middleware = InboundHTTPLogger::Middleware::LoggingMiddleware.new(error_app)

    env = Rack::MockRequest.env_for('/error', method: 'GET')

    assert_raises(StandardError) do
      error_middleware.call(env)
    end

    # When an error occurs before response, no request is logged
    # This is expected behavior since the error occurs before logging
    assert_no_request_logged
  end

  def test_application_errors_pass_through_without_middleware_logging
    # Create an app that raises an error
    error_app = ->(_env) { raise ArgumentError, 'Application error' }
    error_middleware = InboundHTTPLogger::Middleware::LoggingMiddleware.new(error_app)

    env = Rack::MockRequest.env_for('/error', method: 'GET')

    # The error should be re-raised as-is, not caught and logged by middleware
    error = assert_raises(ArgumentError) do
      error_middleware.call(env)
    end

    assert_equal 'Application error', error.message
    assert_no_request_logged
  end

  def test_thread_cleanup_happens_even_with_application_errors
    # Set some thread-local data
    InboundHTTPLogger.set_metadata({ user_id: 123 })
    InboundHTTPLogger.set_loggable(Object.new)

    # Verify data is set
    assert_equal({ user_id: 123 }, Thread.current[:inbound_http_logger_metadata])
    refute_nil Thread.current[:inbound_http_logger_loggable]

    # Create an app that raises an error
    error_app = ->(_env) { raise StandardError, 'Something went wrong' }
    error_middleware = InboundHTTPLogger::Middleware::LoggingMiddleware.new(error_app)

    env = Rack::MockRequest.env_for('/error', method: 'GET')

    assert_raises(StandardError) do
      error_middleware.call(env)
    end

    # Thread-local data should be cleared even when errors occur
    assert_nil Thread.current[:inbound_http_logger_metadata]
    assert_nil Thread.current[:inbound_http_logger_loggable]
  end

  def test_logging_errors_are_handled_gracefully
    # Mock the log_request method to raise an error
    original_method = InboundHTTPLogger::Models::InboundRequestLog.method(:log_request)
    InboundHTTPLogger::Models::InboundRequestLog.define_singleton_method(:log_request) do |*_args|
      raise StandardError, 'Database connection failed'
    end

    # Capture log output to verify error is logged
    log_output = StringIO.new
    logger = Logger.new(log_output)

    with_thread_safe_configuration(logger_factory: -> { logger }) do
      env = Rack::MockRequest.env_for('/users', method: 'GET')

      # The request should still succeed despite logging error
      status, headers, = @middleware.call(env)

      assert_equal 200, status
      assert_equal 'application/json', headers['Content-Type']

      # No request should be logged due to the error
      assert_no_request_logged

      # Error should be logged
      log_content = log_output.string
      assert_includes log_content, 'Error logging inbound request'
      assert_includes log_content, 'Database connection failed'
    end
  ensure
    # Restore original method
    InboundHTTPLogger::Models::InboundRequestLog.define_singleton_method(:log_request, original_method)
  end

  def test_clears_thread_local_data_after_request
    metadata = { user_id: 123 }
    InboundHTTPLogger.set_metadata(metadata)

    env = Rack::MockRequest.env_for('/users', method: 'GET')

    status, = @middleware.call(env)

    assert_equal 200, status

    # Thread-local data should be cleared after request
    assert_nil Thread.current[:inbound_http_logger_metadata]
    assert_nil Thread.current[:inbound_http_logger_loggable]
  end

  def test_handles_form_data_requests
    form_data = 'name=John&email=john@example.com'
    env = Rack::MockRequest.env_for('/users',
                                    method: 'POST',
                                    input: form_data,
                                    'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
                                    'CONTENT_LENGTH' => form_data.bytesize.to_s)

    status, = @middleware.call(env)

    assert_equal 200, status

    log = assert_request_logged(:post, '/users', 200)
    expected_body = { 'name' => 'John', 'email' => 'john@example.com' }
    assert_equal expected_body, log.request_body
  end

  def test_handles_json_parsing_errors_gracefully
    invalid_json = '{"name": "John", invalid}'
    env = Rack::MockRequest.env_for('/users',
                                    method: 'POST',
                                    input: invalid_json,
                                    'CONTENT_TYPE' => 'application/json',
                                    'CONTENT_LENGTH' => invalid_json.bytesize.to_s)

    status, = @middleware.call(env)

    assert_equal 200, status

    log = assert_request_logged(:post, '/users', 200)
    # Should store raw body when JSON parsing fails
    assert_equal invalid_json, log.request_body
  end
end

class LoggingMiddlewareDisabledTest < InboundHTTPLoggerTestCase
  def setup
    super
    InboundHTTPLogger.disable!
    @app = ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{"success": true}']] }
    @middleware = InboundHTTPLogger::Middleware::LoggingMiddleware.new(@app)
  end

  def test_does_not_log_requests_when_disabled
    env = Rack::MockRequest.env_for('/users', method: 'GET')

    status, = @middleware.call(env)

    assert_equal 200, status
    assert_no_request_logged
  end

  def test_still_processes_requests_normally
    env = Rack::MockRequest.env_for('/users', method: 'GET')

    status, headers, response = @middleware.call(env)

    assert_equal 200, status
    assert_equal 'application/json', headers['Content-Type']

    response_body = []
    response.each { |chunk| response_body << chunk }
    assert_equal '{"success": true}', response_body.join
  end
end

class LoggingMiddlewareControllerExclusionsTest < InboundHTTPLoggerTestCase
  def setup
    super
    InboundHTTPLogger.enable!
    @app = ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{"success": true}']] }
    @middleware = InboundHTTPLogger::Middleware::LoggingMiddleware.new(@app)
  end

  def test_skips_excluded_controllers
    # Mock excluded controller
    controller = Object.new
    controller.stubs(:controller_name).returns('rails/health')
    controller.stubs(:action_name).returns('show')

    env = Rack::MockRequest.env_for('/health', method: 'GET')
    env['action_controller.instance'] = controller

    status, = @middleware.call(env)

    assert_equal 200, status
    assert_no_request_logged
  end
end
