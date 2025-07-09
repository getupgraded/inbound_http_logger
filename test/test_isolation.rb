# frozen_string_literal: true

require 'test_helper'

# Test to catch test isolation issues that could cause interference
class TestIsolationTest < InboundHTTPLoggerTestCase
  # This test class tests isolation between tests
  # Disable parallelization to ensure proper isolation testing
  parallelize(workers: 0)
  def setup
    super
    # Reset global configuration to defaults
    InboundHTTPLogger.reset_configuration!

    # Clear all logs
    InboundHTTPLogger::Models::InboundRequestLog.delete_all
  end

  def teardown
    # Disable logging
    InboundHTTPLogger.disable!

    # Clear thread-local data
    InboundHTTPLogger.clear_thread_data
    super
  end

  def test_starts_each_test_with_clean_global_state
    # Verify that global configuration is in expected default state
    config = InboundHTTPLogger.global_configuration

    refute config.enabled?
    assert_equal 10_000, config.max_body_size
    refute config.debug_logging

    # Verify no thread-local overrides
    assert_nil Thread.current[:inbound_http_logger_config_override]
    assert_nil Thread.current[:inbound_http_logger_loggable]
    assert_nil Thread.current[:inbound_http_logger_metadata]
  end

  def test_starts_each_test_with_clean_database_state
    # Verify no logs exist
    assert_equal 0, InboundHTTPLogger::Models::InboundRequestLog.count
  end

  def test_can_modify_configuration_without_affecting_other_tests
    # Modify configuration
    InboundHTTPLogger.configure do |config|
      config.enabled = true
      config.debug_logging = true
      config.max_body_size = 5000
    end

    # Verify changes took effect
    assert InboundHTTPLogger.enabled?
    assert InboundHTTPLogger.configuration.debug_logging
    assert_equal 5000, InboundHTTPLogger.configuration.max_body_size
  end

  def test_can_use_temporary_configuration_with_restoration
    original_enabled = InboundHTTPLogger.configuration.enabled?
    original_max_body_size = InboundHTTPLogger.configuration.max_body_size

    InboundHTTPLogger.with_configuration(enabled: !original_enabled, max_body_size: 1000) do
      # Configuration should be temporarily modified
      assert_equal !original_enabled, InboundHTTPLogger.configuration.enabled?
      assert_equal 1000, InboundHTTPLogger.configuration.max_body_size
    end

    # After block, configuration should be restored
    assert_equal original_enabled, InboundHTTPLogger.configuration.enabled?
    assert_equal original_max_body_size, InboundHTTPLogger.configuration.max_body_size
  end

  def test_can_set_thread_local_metadata_without_affecting_other_threads
    metadata = { user_id: 123, request_id: 'test-123' }
    InboundHTTPLogger.set_metadata(metadata)

    assert_equal metadata, Thread.current[:inbound_http_logger_metadata]

    # Simulate another thread (in same test for simplicity)
    other_thread_metadata = nil
    thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
      other_thread_metadata = Thread.current[:inbound_http_logger_metadata]
    end
    thread.join

    # Other thread should not see our metadata
    assert_nil other_thread_metadata
  end

  def test_can_set_thread_local_loggable_without_affecting_other_threads
    loggable = Object.new
    InboundHTTPLogger.set_loggable(loggable)

    assert_equal loggable, Thread.current[:inbound_http_logger_loggable]

    # Simulate another thread
    other_thread_loggable = nil
    thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
      other_thread_loggable = Thread.current[:inbound_http_logger_loggable]
    end
    thread.join

    # Other thread should not see our loggable
    assert_nil other_thread_loggable
  end

  def test_clears_thread_local_data_properly
    # Set some thread-local data
    InboundHTTPLogger.set_metadata({ test: 'data' })
    InboundHTTPLogger.set_loggable(Object.new)

    # Verify data is set
    refute_nil Thread.current[:inbound_http_logger_metadata]
    refute_nil Thread.current[:inbound_http_logger_loggable]

    # Clear data
    InboundHTTPLogger.clear_thread_data

    # Verify data is cleared
    assert_nil Thread.current[:inbound_http_logger_config_override]
    assert_nil Thread.current[:inbound_http_logger_metadata]
    assert_nil Thread.current[:inbound_http_logger_loggable]
  end

  def test_resets_configuration_properly
    # Modify configuration
    InboundHTTPLogger.configure do |config|
      config.enabled = true
      config.debug_logging = true
      config.max_body_size = 5000
      config.exclude_controller('test_controller')
    end

    # Verify changes
    assert InboundHTTPLogger.enabled?
    assert InboundHTTPLogger.configuration.debug_logging
    assert_equal 5000, InboundHTTPLogger.configuration.max_body_size

    # Reset configuration
    InboundHTTPLogger.reset_configuration!

    # Verify reset to defaults
    config = InboundHTTPLogger.global_configuration
    refute config.enabled?
    refute config.debug_logging
    assert_equal 10_000, config.max_body_size

    # Verify excluded controllers are reset to defaults
    assert_includes config.excluded_controllers, 'rails/health'
    refute_includes config.excluded_controllers, 'test_controller'
  end
end
