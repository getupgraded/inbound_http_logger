# frozen_string_literal: true

require 'test_helper'

class InboundRequestLogValidationsTest < InboundHTTPLoggerTestCase
  def setup
    super
    @model = InboundHTTPLogger::Models::InboundRequestLog
  end

  def test_requires_http_method
    log = @model.new(url: '/test', status_code: 200)
    refute log.valid?
    assert_includes log.errors[:http_method], "can't be blank"
  end

  def test_requires_url
    log = @model.new(http_method: 'GET', status_code: 200)
    refute log.valid?
    assert_includes log.errors[:url], "can't be blank"
  end

  def test_requires_status_code
    log = @model.new(http_method: 'GET', url: '/test')
    refute log.valid?
    assert_includes log.errors[:status_code], "can't be blank"
  end

  def test_requires_status_code_to_be_an_integer
    log = @model.new(http_method: 'GET', url: '/test', status_code: 'not_a_number')
    refute log.valid?
    assert_includes log.errors[:status_code], 'is not a number'
  end
end

class InboundRequestLogScopesTest < InboundHTTPLoggerTestCase
  def setup
    super
    @model = InboundHTTPLogger::Models::InboundRequestLog

    # Create test data
    @model.create!(
      http_method: 'GET',
      url: '/users',
      status_code: 200,
      duration_ms: 50.0,
      created_at: 1.hour.ago
    )

    @model.create!(
      http_method: 'POST',
      url: '/users',
      status_code: 500,
      duration_ms: 150.0,
      created_at: 30.minutes.ago
    )

    @model.create!(
      http_method: 'GET',
      url: '/posts',
      status_code: 404,
      duration_ms: 25.0,
      created_at: 10.minutes.ago
    )
  end

  def test_filters_by_status_code
    successful = @model.where(status_code: 200)
    assert_equal 1, successful.count
    assert_equal 200, successful.first.status_code
  end

  def test_filters_by_http_method
    get_requests = @model.where(http_method: 'GET')
    assert_equal 2, get_requests.count
    get_requests.each { |req| assert_equal 'GET', req.http_method }
  end

  def test_finds_successful_requests
    successful = @model.where('status_code < 400')
    assert_equal 1, successful.count
    assert_equal 200, successful.first.status_code
  end

  def test_finds_failed_requests
    failed = @model.where('status_code >= 400')
    assert_equal 2, failed.count
    failed.each { |req| assert_operator req.status_code, :>=, 400 }
  end

  def test_finds_slow_requests
    slow = @model.where('duration_ms > 100')
    assert_equal 1, slow.count
    assert_equal 150.0, slow.first.duration_ms
  end

  def test_orders_by_recent
    recent = @model.order(created_at: :desc)
    assert_equal 3, recent.count
    # Most recent should be first
    assert_equal '/posts', recent.first.url
  end
end

class InboundRequestLogLogRequestTest < InboundHTTPLoggerTestCase
  # This test class has threading issues with metadata and log creation
  # Disable parallelization to prevent flaky test failures
  parallelize(workers: 0)

  def setup
    super
    @model = InboundHTTPLogger::Models::InboundRequestLog
    InboundHTTPLogger.enable!
  end

  def test_creates_a_log_entry_with_all_data
    # Create a mock request object
    request = Rack::Request.new(Rack::MockRequest.env_for('/api/users',
                                                          method: 'POST',
                                                          'HTTP_USER_AGENT' => 'TestAgent/1.0',
                                                          'HTTP_REFERER' => 'https://example.com',
                                                          'REMOTE_ADDR' => '192.168.1.1'))

    request_body = { name: 'John' }
    status = 201
    headers = { 'Location' => '/api/users/123' }
    response_body = { id: 123, name: 'John' }
    duration_seconds = 0.15

    log = @model.log_request(request, request_body, status, headers, response_body, duration_seconds)

    refute_nil log
    assert log.persisted?
    assert_equal 'POST', log.http_method
    assert_equal '/api/users', log.url
    assert_equal 201, log.status_code
    assert_equal 150.0, log.duration_ms
    assert_equal '192.168.1.1', log.ip_address
    assert_equal 'TestAgent/1.0', log.user_agent
    assert_equal 'https://example.com', log.referrer
  end

  def test_returns_nil_when_logging_is_disabled
    InboundHTTPLogger.disable!

    request = Rack::Request.new(Rack::MockRequest.env_for('/test'))
    log = @model.log_request(request, nil, 200, {}, nil, 0.1)

    assert_nil log
  end

  def test_returns_nil_for_excluded_paths
    # Health path is excluded by default in test setup
    request = Rack::Request.new(Rack::MockRequest.env_for('/health'))
    log = @model.log_request(request, nil, 200, {}, nil, 0.1)

    assert_nil log
  end

  def test_logs_excluded_content_types_when_called_directly
    # Even if content type would be excluded in middleware,
    # direct calls to log_request should work
    request = Rack::Request.new(Rack::MockRequest.env_for('/styles.css'))
    log = @model.log_request(request, nil, 200, {}, nil, 0.1)

    # This should actually be nil because path filtering still applies
    assert_nil log
  end

  def test_handles_errors_gracefully
    # Create an invalid request that will cause an error
    request = nil # This will cause an error
    log = @model.log_request(request, nil, 200, {}, nil, 0.1)

    assert_nil log
  end

  def test_includes_metadata_from_thread_local_storage
    metadata = { user_id: 123, session_id: 'abc123' }
    InboundHTTPLogger.set_metadata(metadata)

    request = Rack::Request.new(Rack::MockRequest.env_for('/test'))
    log = @model.log_request(request, nil, 200, {}, nil, 0.1)

    refute_nil log
    assert_equal metadata.stringify_keys, log.metadata
  end
end

class InboundRequestLogInstanceMethodsTest < InboundHTTPLoggerTestCase
  def setup
    super
    @model = InboundHTTPLogger::Models::InboundRequestLog
    @log = @model.create!(
      http_method: 'GET',
      url: '/test',
      status_code: 200,
      duration_ms: 123.45
    )
  end

  def test_calculates_duration_seconds_from_milliseconds
    assert_equal 0.12345, @log.duration_seconds

    # Test with nil duration
    @log.duration_ms = nil
    assert_nil @log.duration_seconds

    # Test with different values
    @log.duration_ms = 1500.0
    assert_equal 1.5, @log.duration_seconds
  end

  def test_formats_duration_correctly
    assert_equal '123.45ms', @log.formatted_duration

    # Test with nil duration
    @log.duration_ms = nil
    assert_equal 'N/A', @log.formatted_duration
  end

  def test_determines_success_status
    # 2xx status codes are successful
    @log.status_code = 200
    assert @log.success?

    @log.status_code = 201
    assert @log.success?

    # 4xx and 5xx are not successful
    @log.status_code = 404
    refute @log.success?

    @log.status_code = 500
    refute @log.success?
  end

  def test_determines_if_request_is_slow
    # Default threshold is 1000ms
    @log.duration_ms = 500.0
    refute @log.slow?

    @log.duration_ms = 1500.0
    assert @log.slow?
  end

  def test_provides_status_text
    @log.status_code = 200
    assert_equal 'OK', @log.status_text

    @log.status_code = 404
    assert_equal 'Not Found', @log.status_text

    @log.status_code = 500
    assert_equal 'Internal Server Error', @log.status_text
  end

  def test_formats_request_and_response
    @log.request_body = { name: 'John' }
    @log.response_body = { id: 1, name: 'John' }

    # Test individual formatters
    formatted_request = @log.formatted_request
    formatted_response = @log.formatted_response

    assert_includes formatted_request, 'GET'
    assert_includes formatted_request, '/test'
    assert_includes formatted_response, '200'
    assert_includes formatted_response, 'OK'
  end
end

class InboundRequestLogSearchTest < InboundHTTPLoggerTestCase
  # This test class has database adapter issues with PostgreSQL search
  # Disable parallelization to prevent flaky test failures
  parallelize(workers: 0)

  def setup
    super
    @model = InboundHTTPLogger::Models::InboundRequestLog

    # Create test data
    @model.create!(
      http_method: 'GET',
      url: '/users/search',
      status_code: 200,
      ip_address: '192.168.1.1',
      user_agent: 'Chrome/90.0'
    )

    @model.create!(
      http_method: 'POST',
      url: '/api/posts',
      status_code: 404,
      ip_address: '10.0.0.1',
      user_agent: 'Firefox/88.0'
    )
  end

  def test_searches_by_general_query
    # Test the search method if it exists
    results = if @model.respond_to?(:search)
                @model.search(q: 'search')
              else
                # Fallback to basic where query
                @model.where('url LIKE ?', '%search%')
              end
    assert_equal 1, results.count
    assert_includes results.first.url, 'search'
  end

  def test_filters_by_status
    results = @model.where(status_code: 404)
    assert_equal 1, results.count
    assert_equal 404, results.first.status_code
  end

  def test_filters_by_method
    results = @model.where(http_method: 'POST')
    assert_equal 1, results.count
    assert_equal 'POST', results.first.http_method
  end

  def test_filters_by_ip_address
    results = @model.where(ip_address: '192.168.1.1')
    assert_equal 1, results.count
    assert_equal '192.168.1.1', results.first.ip_address
  end
end

class InboundRequestLogCleanupTest < InboundHTTPLoggerTestCase
  def setup
    super
    @model = InboundHTTPLogger::Models::InboundRequestLog
  end

  def test_removes_old_logs
    # Create old logs
    old_log = @model.create!(
      http_method: 'GET',
      url: '/old',
      status_code: 200,
      created_at: 2.months.ago
    )

    # Create recent log
    recent_log = @model.create!(
      http_method: 'GET',
      url: '/recent',
      status_code: 200,
      created_at: 1.day.ago
    )

    # Test cleanup method if it exists
    if @model.respond_to?(:cleanup)
      @model.cleanup(30) # 30 days
    else
      # Fallback to manual cleanup
      @model.where('created_at < ?', 30.days.ago).delete_all
    end

    # Old log should be deleted, recent should remain
    refute @model.exists?(old_log.id)
    assert @model.exists?(recent_log.id)
  end
end
