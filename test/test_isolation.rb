# frozen_string_literal: true

require 'test_helper'

# Test to catch test isolation issues that could cause interference
describe 'Test Isolation' do
  before do
    # Reset global configuration to defaults
    InboundHTTPLogger.reset_configuration!

    # Clear all logs
    InboundHTTPLogger::Models::InboundRequestLog.delete_all
  end

  after do
    # Disable logging
    InboundHTTPLogger.disable!

    # Clear thread-local data
    InboundHTTPLogger.clear_thread_data
  end

  it 'starts each test with clean global state' do
    # Verify that global configuration is in expected default state
    config = InboundHTTPLogger.global_configuration

    _(config.enabled?).must_equal false
    _(config.max_body_size).must_equal 10_000
    _(config.debug_logging).must_equal false

    # Verify no thread-local overrides
    _(Thread.current[:inbound_http_logger_config_override]).must_be_nil
    _(Thread.current[:inbound_http_logger_loggable]).must_be_nil
    _(Thread.current[:inbound_http_logger_metadata]).must_be_nil
  end

  it 'starts each test with clean database state' do
    # Verify no logs exist
    _(InboundHTTPLogger::Models::InboundRequestLog.count).must_equal 0
  end

  it 'can modify configuration without affecting other tests' do
    # Modify configuration
    InboundHTTPLogger.configure do |config|
      config.enabled = true
      config.debug_logging = true
      config.max_body_size = 5000
    end

    # Verify changes took effect
    _(InboundHTTPLogger.enabled?).must_equal true
    _(InboundHTTPLogger.configuration.debug_logging).must_equal true
    _(InboundHTTPLogger.configuration.max_body_size).must_equal 5000
  end

  it 'can use thread-local configuration without affecting global state' do
    original_enabled = InboundHTTPLogger.configuration.enabled?

    InboundHTTPLogger.with_configuration(enabled: !original_enabled, max_body_size: 1000) do
      # Thread-local configuration should be active
      _(InboundHTTPLogger.configuration.enabled?).must_equal !original_enabled
      _(InboundHTTPLogger.configuration.max_body_size).must_equal 1000

      # Global configuration should be unchanged
      _(InboundHTTPLogger.global_configuration.enabled?).must_equal original_enabled
      _(InboundHTTPLogger.global_configuration.max_body_size).must_equal 10_000
    end

    # After block, configuration should be restored
    _(InboundHTTPLogger.configuration.enabled?).must_equal original_enabled
    _(InboundHTTPLogger.configuration.max_body_size).must_equal 10_000
  end

  it 'can set thread-local metadata without affecting other threads' do
    metadata = { user_id: 123, request_id: 'test-123' }
    InboundHTTPLogger.set_metadata(metadata)

    _(Thread.current[:inbound_http_logger_metadata]).must_equal metadata

    # Simulate another thread (in same test for simplicity)
    other_thread_metadata = nil
    thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
      other_thread_metadata = Thread.current[:inbound_http_logger_metadata]
    end
    thread.join

    # Other thread should not see our metadata
    _(other_thread_metadata).must_be_nil
  end

  it 'can set thread-local loggable without affecting other threads' do
    loggable = Object.new
    InboundHTTPLogger.set_loggable(loggable)

    _(Thread.current[:inbound_http_logger_loggable]).must_equal loggable

    # Simulate another thread
    other_thread_loggable = nil
    thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
      other_thread_loggable = Thread.current[:inbound_http_logger_loggable]
    end
    thread.join

    # Other thread should not see our loggable
    _(other_thread_loggable).must_be_nil
  end

  it 'clears thread-local data properly' do
    # Set some thread-local data
    InboundHTTPLogger.set_metadata({ test: 'data' })
    InboundHTTPLogger.set_loggable(Object.new)

    # Verify data is set
    _(Thread.current[:inbound_http_logger_metadata]).wont_be_nil
    _(Thread.current[:inbound_http_logger_loggable]).wont_be_nil

    # Clear data
    InboundHTTPLogger.clear_thread_data

    # Verify data is cleared
    _(Thread.current[:inbound_http_logger_config_override]).must_be_nil
    _(Thread.current[:inbound_http_logger_metadata]).must_be_nil
    _(Thread.current[:inbound_http_logger_loggable]).must_be_nil
  end

  it 'resets configuration properly' do
    # Modify configuration
    InboundHTTPLogger.configure do |config|
      config.enabled = true
      config.debug_logging = true
      config.max_body_size = 5000
      config.exclude_controller('test_controller')
    end

    # Verify changes
    _(InboundHTTPLogger.enabled?).must_equal true
    _(InboundHTTPLogger.configuration.debug_logging).must_equal true
    _(InboundHTTPLogger.configuration.max_body_size).must_equal 5000

    # Reset configuration
    InboundHTTPLogger.reset_configuration!

    # Verify reset to defaults
    config = InboundHTTPLogger.global_configuration
    _(config.enabled?).must_equal false
    _(config.debug_logging).must_equal false
    _(config.max_body_size).must_equal 10_000

    # Verify excluded controllers are reset to defaults
    _(config.excluded_controllers).must_include 'rails/health'
    _(config.excluded_controllers).wont_include 'test_controller'
  end
end
