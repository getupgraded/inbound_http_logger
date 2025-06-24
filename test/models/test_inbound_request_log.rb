# frozen_string_literal: true

require 'test_helper'

describe InboundHttpLogger::Models::InboundRequestLog do
  let(:model) { InboundHttpLogger::Models::InboundRequestLog }

  describe 'validations' do
    it 'requires http_method' do
      log = model.new(url: '/test', status_code: 200)
      _(log.valid?).must_equal false
      _(log.errors[:http_method]).must_include "can't be blank"
    end

    it 'requires url' do
      log = model.new(http_method: 'GET', status_code: 200)
      _(log.valid?).must_equal false
      _(log.errors[:url]).must_include "can't be blank"
    end

    it 'requires status_code' do
      log = model.new(http_method: 'GET', url: '/test')
      _(log.valid?).must_equal false
      _(log.errors[:status_code]).must_include "can't be blank"
    end

    it 'requires status_code to be an integer' do
      log = model.new(http_method: 'GET', url: '/test', status_code: 'not_a_number')
      _(log.valid?).must_equal false
      _(log.errors[:status_code]).must_include 'is not a number'
    end
  end

  describe 'scopes' do
    before do
      # Create test data
      @success_log = model.create!(
        http_method: 'GET',
        url: '/users',
        status_code: 200,
        duration_ms: 150,
        ip_address: '127.0.0.1'
      )

      @error_log = model.create!(
        http_method: 'POST',
        url: '/orders',
        status_code: 500,
        duration_ms: 2500,
        ip_address: '192.168.1.1'
      )

      @slow_log = model.create!(
        http_method: 'PUT',
        url: '/slow',
        status_code: 200,
        duration_ms: 1500,
        ip_address: '127.0.0.1'
      )
    end

    it 'filters by status code' do
      logs = model.with_status(200)
      _(logs.count).must_equal 2
      _(logs).must_include @success_log
      _(logs).must_include @slow_log
    end

    it 'filters by HTTP method' do
      logs = model.with_method('GET')
      _(logs.count).must_equal 1
      _(logs.first).must_equal @success_log
    end

    it 'finds successful requests' do
      logs = model.successful
      _(logs.count).must_equal 2
      _(logs).must_include @success_log
      _(logs).must_include @slow_log
    end

    it 'finds failed requests' do
      logs = model.failed
      _(logs.count).must_equal 1
      _(logs.first).must_equal @error_log
    end

    it 'finds slow requests' do
      logs = model.slow(1000)
      _(logs.count).must_equal 2
      _(logs).must_include @error_log
      _(logs).must_include @slow_log
    end

    it 'orders by recent' do
      logs = model.recent
      _(logs.first).must_equal @slow_log # Most recent
    end
  end

  describe '.log_request' do
    before do
      InboundHttpLogger.enable!
    end

    it 'creates a log entry with all data' do
      request = create_rack_request(
        method: 'POST',
        path: '/users',
        headers: { 'Content-Type' => 'application/json', 'Authorization' => 'Bearer token' },
        body: '{"name":"test"}'
      )

      headers = { 'Content-Type' => 'application/json' }
      response_body = '{"id":1,"name":"test"}'

      log = model.log_request(request, '{"name":"test"}', 201, headers, response_body, 0.25)

      _(log).wont_be_nil
      _(log.http_method).must_equal 'POST'
      _(log.url).must_equal '/users'
      _(log.status_code).must_equal 201
      _(log.duration_seconds).must_equal 0.25
      _(log.duration_ms).must_equal 250.0
      _(log.request_headers['Authorization']).must_equal '[FILTERED]'
      _(log.request_headers['Content-Type']).must_equal 'application/json'
      _(log.response_body).must_equal '{"id":1,"name":"test"}'
    end

    it 'returns nil when logging is disabled' do
      InboundHttpLogger.disable!

      request = create_rack_request(method: 'GET', path: '/users')
      log = model.log_request(request, nil, 200, {}, nil, 0.1)
      _(log).must_be_nil
    end

    it 'returns nil for excluded paths' do
      request = create_rack_request(method: 'GET', path: '/assets/application.js')
      log = model.log_request(request, nil, 200, {}, nil, 0.1)
      _(log).must_be_nil
    end

    it 'logs excluded content types when called directly' do
      # NOTE: Content type filtering is handled by middleware, not the model
      # When calling log_request directly, it will log everything
      request = create_rack_request(method: 'GET', path: '/page')
      headers = { 'Content-Type' => 'text/html' }

      log = model.log_request(request, nil, 200, headers, '<html></html>', 0.1)
      _(log).wont_be_nil
      _(log.response_headers['Content-Type']).must_equal 'text/html'
    end

    it 'handles errors gracefully' do
      # Mock the create! method to raise an error
      model.stubs(:create!).raises(StandardError, 'Database error')

      request = create_rack_request(method: 'GET', path: '/users')
      log = model.log_request(request, nil, 200, {}, nil, 0.1)
      _(log).must_be_nil
    end

    it 'includes metadata from thread-local storage' do
      InboundHttpLogger.set_metadata({ user_id: 123 })

      request = create_rack_request(method: 'GET', path: '/users')
      log = model.log_request(request, nil, 200, {}, nil, 0.1)

      _(log.metadata['user_id']).must_equal 123
    end
  end

  describe 'instance methods' do
    let(:log) do
      model.create!(
        http_method: 'POST',
        url: '/users',
        status_code: 201,
        duration_ms: 150.5,
        duration_seconds: 0.1505,
        request_headers: { 'Content-Type' => 'application/json' },
        request_body: '{"name":"John"}',
        response_headers: { 'Content-Type' => 'application/json' },
        response_body: '{"id":1,"name":"John"}',
        ip_address: '127.0.0.1',
        user_agent: 'Test Agent'
      )
    end

    it 'formats duration correctly' do
      _(log.formatted_duration).must_equal '150.5ms'

      slow_log = model.create!(
        http_method: 'GET',
        url: '/slow',
        status_code: 200,
        duration_ms: 2500,
        duration_seconds: 2.5
      )

      _(slow_log.formatted_duration).must_equal '2.5s'
    end

    it 'determines success status' do
      _(log.success?).must_equal true
      _(log.failure?).must_equal false

      error_log = model.create!(
        http_method: 'GET',
        url: '/error',
        status_code: 500
      )

      _(error_log.success?).must_equal false
      _(error_log.failure?).must_equal true
    end

    it 'determines if request is slow' do
      _(log.slow?).must_equal false
      _(log.slow?(100)).must_equal true
    end

    it 'provides status text' do
      _(log.status_text).must_equal 'Created'

      not_found_log = model.create!(
        http_method: 'GET',
        url: '/notfound',
        status_code: 404
      )

      _(not_found_log.status_text).must_equal 'Not Found'
    end

    it 'formats request and response' do
      request_format = log.formatted_request
      _(request_format).must_include 'POST /users'
      _(request_format).must_include 'Content-Type: application/json'
      _(request_format).must_include '{"name":"John"}'

      response_format = log.formatted_response
      _(response_format).must_include 'HTTP 201 Created'
      _(response_format).must_include 'Content-Type: application/json'
      _(response_format).must_include '{"id":1,"name":"John"}'
    end
  end

  describe 'search functionality' do
    before do
      @user_log = model.create!(
        http_method: 'GET',
        url: '/users',
        status_code: 200,
        request_body: '{"filter":"active"}',
        response_body: '{"users":[{"name":"John"}]}',
        ip_address: '127.0.0.1'
      )

      @order_log = model.create!(
        http_method: 'POST',
        url: '/orders',
        status_code: 201,
        request_body: '{"product":"widget"}',
        response_body: '{"order_id":123}',
        ip_address: '192.168.1.1'
      )
    end

    it 'searches by general query' do
      results = model.search(q: 'users')
      _(results.count).must_equal 1
      _(results.first).must_equal @user_log

      results = model.search(q: 'widget')
      _(results.count).must_equal 1
      _(results.first).must_equal @order_log
    end

    it 'filters by status' do
      results = model.search(status: 200)
      _(results.count).must_equal 1
      _(results.first).must_equal @user_log
    end

    it 'filters by method' do
      results = model.search(method: 'POST')
      _(results.count).must_equal 1
      _(results.first).must_equal @order_log
    end

    it 'filters by IP address' do
      results = model.search(ip_address: '127.0.0.1')
      _(results.count).must_equal 1
      _(results.first).must_equal @user_log
    end
  end

  describe 'cleanup' do
    it 'removes old logs' do
      # Create old log
      old_log = model.create!(
        http_method: 'GET',
        url: '/old',
        status_code: 200,
        created_at: 100.days.ago
      )

      # Create recent log
      recent_log = model.create!(
        http_method: 'GET',
        url: '/recent',
        status_code: 200
      )

      deleted_count = model.cleanup(90)

      _(deleted_count).must_equal 1
      _(model.exists?(old_log.id)).must_equal false
      _(model.exists?(recent_log.id)).must_equal true
    end
  end

  describe 'JSONB functionality' do
    before do
      InboundHttpLogger.enable!
    end

    it 'detects JSONB usage correctly' do
      # This will depend on the database adapter being used in tests
      if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
        # Skip if we don't have the actual table yet (migration not run)
        skip 'JSONB test requires PostgreSQL with migrated table' unless model.table_exists?
      else
        _(model.using_jsonb?).must_equal false
      end
    end

    it 'stores JSON response as parsed object for JSONB' do
      skip 'JSONB test requires PostgreSQL' unless model.using_jsonb?

      request = create_rack_request(method: 'POST', path: '/api/test')
      json_response = '{"status":"success","data":{"id":123,"name":"test"}}'

      log = model.log_request(request, nil, 200, {}, json_response, 0.1)

      _(log).wont_be_nil
      # For JSONB, response_body should be stored as a parsed hash, not a string
      _(log.response_body).must_be_kind_of Hash
      _(log.response_body['status']).must_equal 'success'
      _(log.response_body['data']['id']).must_equal 123
    end

    it 'stores non-JSON response as string for JSONB' do
      skip 'JSONB test requires PostgreSQL' unless model.using_jsonb?

      request = create_rack_request(method: 'GET', path: '/api/test')
      text_response = 'plain text response'

      log = model.log_request(request, nil, 200, {}, text_response, 0.1)

      _(log).wont_be_nil
      # For non-JSON content, should remain as string
      _(log.response_body).must_be_kind_of String
      _(log.response_body).must_equal 'plain text response'
    end

    it 'uses JSONB operators for search when available' do
      skip 'JSONB test requires PostgreSQL' unless model.using_jsonb?

      # Create test logs with JSON data
      json_log = model.create!(
        http_method: 'POST',
        url: '/api/users',
        status_code: 200,
        response_body: { 'users' => [{ 'name' => 'John', 'role' => 'admin' }] }
      )

      text_log = model.create!(
        http_method: 'GET',
        url: '/api/status',
        status_code: 200,
        response_body: 'OK'
      )

      # Search should find the JSON log
      results = model.search(q: 'John')
      _(results).must_include json_log
      _(results).wont_include text_log
    end
  end
end
