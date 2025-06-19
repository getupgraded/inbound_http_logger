# frozen_string_literal: true

require "test_helper"

describe InboundHttpLogger::Middleware::LoggingMiddleware do
  let(:app) { ->(env) { [200, { 'Content-Type' => 'application/json' }, ['{"success": true}']] } }
  let(:middleware) { InboundHttpLogger::Middleware::LoggingMiddleware.new(app) }

  describe "when logging is enabled" do
    before do
      InboundHttpLogger.enable!
    end

    it "logs successful requests" do
      # Mock timing to ensure duration > 0
      start_time = 1000.0
      end_time = 1000.1
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(start_time, end_time)

      env = Rack::MockRequest.env_for('/users', method: 'GET')

      status, headers, response = middleware.call(env)

      _(status).must_equal 200
      _(headers['Content-Type']).must_equal 'application/json'

      log = assert_request_logged(:get, "/users", 200)
      _(log.duration_ms).must_equal 100.0
      _(log.response_body).must_equal '{"success":true}'
    end

    it "logs POST requests with request body" do
      body = '{"name": "John"}'
      env = Rack::MockRequest.env_for('/users',
                                      method: 'POST',
                                      input: body,
                                      'CONTENT_TYPE' => 'application/json',
                                      'CONTENT_LENGTH' => body.bytesize.to_s)

      status, headers, response = middleware.call(env)

      _(status).must_equal 200

      log = assert_request_logged(:post, "/users", 200)
      _(log.request_body).must_equal({ "name" => "John" })
      _(log.request_headers['Content-Type']).must_equal 'application/json'
    end

    it "logs requests with headers" do
      env = Rack::MockRequest.env_for('/protected',
                                      method: 'GET',
                                      'HTTP_AUTHORIZATION' => 'Bearer token123',
                                      'HTTP_USER_AGENT' => 'Test Agent')

      status, headers, response = middleware.call(env)

      _(status).must_equal 200

      log = assert_request_logged(:get, "/protected", 200)
      _(log.request_headers['Authorization']).must_equal '[FILTERED]'
      _(log.request_headers['User-Agent']).must_equal 'Test Agent'
      _(log.user_agent).must_equal 'Test Agent'
    end

    it "logs failed requests" do
      error_app = ->(env) { [500, { 'Content-Type' => 'application/json' }, ['{"error": "Internal Server Error"}']] }
      error_middleware = InboundHttpLogger::Middleware::LoggingMiddleware.new(error_app)

      env = Rack::MockRequest.env_for('/error', method: 'GET')

      status, headers, response = error_middleware.call(env)

      _(status).must_equal 500

      log = assert_request_logged(:get, "/error", 500)
      _(log.response_body).must_equal '{"error":"Internal Server Error"}'
    end

    it "skips excluded paths" do
      env = Rack::MockRequest.env_for('/assets/application.js', method: 'GET')

      status, headers, response = middleware.call(env)

      _(status).must_equal 200
      assert_no_request_logged
    end

    it "skips excluded content types" do
      html_app = ->(env) { [200, { 'Content-Type' => 'text/html' }, ['<html></html>']] }
      html_middleware = InboundHttpLogger::Middleware::LoggingMiddleware.new(html_app)

      env = Rack::MockRequest.env_for('/page', method: 'GET')

      status, headers, response = html_middleware.call(env)

      _(status).must_equal 200
      assert_no_request_logged
    end

    it "handles large request bodies" do
      large_body = 'x' * (InboundHttpLogger.configuration.max_body_size + 1000)
      env = Rack::MockRequest.env_for('/large',
                                      method: 'POST',
                                      input: large_body,
                                      'CONTENT_TYPE' => 'text/plain',
                                      'CONTENT_LENGTH' => large_body.bytesize.to_s)

      status, headers, response = middleware.call(env)

      _(status).must_equal 200

      log = assert_request_logged(:post, "/large", 200)
      _(log.request_body).must_be_nil # Should be nil due to size limit
    end

    it "includes metadata from thread-local storage" do
      InboundHttpLogger.set_metadata({ user_id: 123, action: 'test' })

      env = Rack::MockRequest.env_for('/users', method: 'GET')

      status, headers, response = middleware.call(env)

      log = assert_request_logged(:get, "/users", 200)
      _(log.metadata['user_id']).must_equal 123
      _(log.metadata['action']).must_equal 'test'
    end

    it "includes controller information when available" do
      # Mock controller instance
      controller = Object.new
      controller.stubs(:controller_name).returns('users')
      controller.stubs(:action_name).returns('index')

      env = Rack::MockRequest.env_for('/users', method: 'GET')
      env['action_controller.instance'] = controller

      status, headers, response = middleware.call(env)

      log = assert_request_logged(:get, "/users", 200)
      _(log.metadata['controller']).must_equal 'users'
      _(log.metadata['action']).must_equal 'index'
    end

    it "handles middleware errors gracefully" do
      # Mock the log_request method to raise an error
      InboundHttpLogger::Models::InboundRequestLog.stubs(:log_request).raises(StandardError, "Database error")

      env = Rack::MockRequest.env_for('/users', method: 'GET')

      # Should not raise an error, should handle it gracefully
      status, headers, response = middleware.call(env)
      _(status).must_equal 200

      # Should not have logged anything due to the error
      assert_no_request_logged
    end

    it "clears thread-local data after request" do
      InboundHttpLogger.set_metadata({ user_id: 123 })
      InboundHttpLogger.set_loggable(Object.new)

      env = Rack::MockRequest.env_for('/users', method: 'GET')

      status, headers, response = middleware.call(env)

      # Thread-local data should be cleared
      _(Thread.current[:inbound_http_logger_metadata]).must_be_nil
      _(Thread.current[:inbound_http_logger_loggable]).must_be_nil
    end

    it "handles form data requests" do
      form_data = 'name=John&email=john@example.com'
      env = Rack::MockRequest.env_for('/submit',
                                      method: 'POST',
                                      input: form_data,
                                      'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
                                      'CONTENT_LENGTH' => form_data.bytesize.to_s)

      status, headers, response = middleware.call(env)

      log = assert_request_logged(:post, "/submit", 200)
      _(log.request_body).must_be_kind_of Hash
      _(log.request_body['name']).must_equal 'John'
      _(log.request_body['email']).must_equal 'john@example.com'
    end

    it "handles JSON parsing errors gracefully" do
      invalid_json = '{"invalid": json}'
      env = Rack::MockRequest.env_for('/json',
                                      method: 'POST',
                                      input: invalid_json,
                                      'CONTENT_TYPE' => 'application/json',
                                      'CONTENT_LENGTH' => invalid_json.bytesize.to_s)

      status, headers, response = middleware.call(env)

      log = assert_request_logged(:post, "/json", 200)
      _(log.request_body).must_equal invalid_json # Should store as string when JSON parsing fails
    end
  end

  describe "when logging is disabled" do
    before do
      InboundHttpLogger.disable!
    end

    it "does not log requests when disabled" do
      env = Rack::MockRequest.env_for('/users', method: 'GET')

      status, headers, response = middleware.call(env)

      _(status).must_equal 200
      assert_no_request_logged
    end

    it "still processes requests normally" do
      env = Rack::MockRequest.env_for('/users', method: 'GET')

      status, headers, response = middleware.call(env)

      _(status).must_equal 200
      _(headers['Content-Type']).must_equal 'application/json'

      response_body = []
      response.each { |chunk| response_body << chunk }
      _(response_body.join).must_equal '{"success": true}'
    end
  end

  describe "controller exclusions" do
    before do
      InboundHttpLogger.enable!
    end

    it "skips excluded controllers" do
      # Mock excluded controller
      controller = Object.new
      controller.stubs(:controller_name).returns('rails/health')
      controller.stubs(:action_name).returns('show')

      env = Rack::MockRequest.env_for('/health', method: 'GET')
      env['action_controller.instance'] = controller

      status, headers, response = middleware.call(env)

      _(status).must_equal 200
      assert_no_request_logged
    end
  end
end
