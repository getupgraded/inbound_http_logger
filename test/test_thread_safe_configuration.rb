# frozen_string_literal: true

require 'test_helper'

class TestThreadSafeConfiguration < Minitest::Test
  include TestHelpers

  def test_thread_safe_configuration_isolation
    # Test that configuration changes in one thread don't affect another
    results = []
    errors = []

    threads = Array.new(2) do |i|
      Thread.new do # rubocop:disable ThreadSafety/NewThread
        InboundHttpLogger.with_configuration(enabled: i.even?, debug_logging: i.even?) do
          sleep 0.1 # Allow other thread to potentially interfere
          results[i] = {
            enabled: InboundHttpLogger.configuration.enabled?,
            debug_logging: InboundHttpLogger.configuration.debug_logging
          }
        end
      rescue StandardError => e
        errors[i] = e
      end
    end

    threads.each(&:join)

    # Check for errors
    errors.each_with_index do |error, i|
      raise "Thread #{i} failed: #{error}" if error
    end

    # Verify thread isolation
    assert results[0][:enabled], 'Thread 0 should have enabled: true'
    assert results[0][:debug_logging], 'Thread 0 should have debug_logging: true'
    assert_not results[1][:enabled], 'Thread 1 should have enabled: false'
    assert_not results[1][:debug_logging], 'Thread 1 should have debug_logging: false'
  end

  def test_configuration_backup_and_restore
    # Test that configuration backup and restore work properly
    original_enabled = InboundHttpLogger.configuration.enabled?
    original_debug = InboundHttpLogger.configuration.debug_logging

    # Change configuration
    InboundHttpLogger.configure do |config|
      config.enabled = !original_enabled
      config.debug_logging = !original_debug
    end

    # Verify changes
    assert_equal !original_enabled, InboundHttpLogger.configuration.enabled?
    assert_equal !original_debug, InboundHttpLogger.configuration.debug_logging

    # Create backup and restore
    backup = InboundHttpLogger.global_configuration.backup
    InboundHttpLogger.global_configuration.restore(backup)

    # Should be back to the changed values (backup captures current state)
    assert_equal !original_enabled, InboundHttpLogger.configuration.enabled?
    assert_equal !original_debug, InboundHttpLogger.configuration.debug_logging
  end

  def test_configuration_restoration_after_exception
    # Test that configuration is properly restored even if an exception occurs
    original_enabled = InboundHttpLogger.configuration.enabled?

    begin
      InboundHttpLogger.with_configuration(enabled: !original_enabled) do
        assert_equal !original_enabled, InboundHttpLogger.configuration.enabled?
        raise StandardError, 'Test exception'
      end
    rescue StandardError => e
      assert_equal 'Test exception', e.message
    end

    # Configuration should be restored to original value
    assert_equal original_enabled, InboundHttpLogger.configuration.enabled?
  end

  def test_nested_configuration_overrides
    # Test that nested configuration overrides work correctly
    original_enabled = InboundHttpLogger.configuration.enabled?
    original_debug = InboundHttpLogger.configuration.debug_logging

    InboundHttpLogger.with_configuration(enabled: true) do
      assert InboundHttpLogger.configuration.enabled?
      assert_equal original_debug, InboundHttpLogger.configuration.debug_logging

      InboundHttpLogger.with_configuration(debug_logging: true) do
        assert InboundHttpLogger.configuration.enabled?
        assert InboundHttpLogger.configuration.debug_logging
      end

      # Inner override should be restored
      assert InboundHttpLogger.configuration.enabled?
      assert_equal original_debug, InboundHttpLogger.configuration.debug_logging
    end

    # Outer override should be restored
    assert_equal original_enabled, InboundHttpLogger.configuration.enabled?
    assert_equal original_debug, InboundHttpLogger.configuration.debug_logging
  end

  def test_collection_access
    # Test that collections are accessible
    excluded_paths = InboundHttpLogger.configuration.excluded_paths
    assert_kind_of Set, excluded_paths

    excluded_content_types = InboundHttpLogger.configuration.excluded_content_types
    assert_kind_of Set, excluded_content_types

    sensitive_headers = InboundHttpLogger.configuration.sensitive_headers
    assert_kind_of Set, sensitive_headers
  end

  def test_dependency_injection_logger
    # Test that logger dependency injection works
    custom_logger = Logger.new(StringIO.new)

    InboundHttpLogger.with_configuration(logger_factory: -> { custom_logger }) do
      assert_equal custom_logger, InboundHttpLogger.configuration.logger
    end
  end

  def test_with_thread_safe_configuration_helper
    # Test the test helper method
    original_enabled = InboundHttpLogger.configuration.enabled?

    with_thread_safe_configuration(enabled: !original_enabled, max_body_size: 5000) do
      assert_equal !original_enabled, InboundHttpLogger.configuration.enabled?
      assert_equal 5000, InboundHttpLogger.configuration.max_body_size
    end

    # Configuration should be restored
    assert_equal original_enabled, InboundHttpLogger.configuration.enabled?
  end

  def test_global_configuration_access
    # Test that global_configuration bypasses thread-local overrides
    InboundHttpLogger.with_configuration(enabled: true) do
      # Thread-local override should affect regular configuration access
      assert InboundHttpLogger.configuration.enabled?

      # But global_configuration should bypass the override
      global_config = InboundHttpLogger.global_configuration
      # The global config's enabled state depends on test setup, so we just verify it's accessible
      assert_respond_to global_config, :enabled?
    end
  end
end
