# frozen_string_literal: true

require 'test_helper'

class InboundHTTPLoggerTest < InboundHTTPLoggerTestCase
  def test_has_a_version_number
    refute_nil ::InboundHTTPLogger::VERSION
  end
end

class InboundHTTPLoggerConfigurationTest < InboundHTTPLoggerTestCase
  def test_starts_disabled_by_default
    # Reset to default state (disabled)
    InboundHTTPLogger.disable!
    refute InboundHTTPLogger.enabled?
  end

  def test_can_be_enabled_and_disabled
    InboundHTTPLogger.enable!
    assert InboundHTTPLogger.enabled?

    InboundHTTPLogger.disable!
    refute InboundHTTPLogger.enabled?
  end

  def test_can_be_configured_with_a_block
    InboundHTTPLogger.configure do |config|
      config.enabled = true
      config.debug_logging = true
    end

    assert InboundHTTPLogger.enabled?
    assert InboundHTTPLogger.configuration.debug_logging
  end
end

class InboundHTTPLoggerControllerFilteringTest < InboundHTTPLoggerTestCase
  def setup
    super
    InboundHTTPLogger.enable!
  end

  def test_allows_normal_controllers_by_default
    assert InboundHTTPLogger.enabled_for?('users')
    assert InboundHTTPLogger.enabled_for?('users', 'show')
  end

  def test_excludes_rails_internal_controllers_by_default
    refute InboundHTTPLogger.enabled_for?('rails/health')
    refute InboundHTTPLogger.enabled_for?('action_cable/internal')
  end

  def test_can_exclude_custom_controllers
    InboundHTTPLogger.configuration.exclude_controller('admin')
    refute InboundHTTPLogger.enabled_for?('admin')
    refute InboundHTTPLogger.enabled_for?('admin', 'index')
  end

  def test_can_exclude_specific_actions
    InboundHTTPLogger.configuration.exclude_action('users', 'internal')
    assert InboundHTTPLogger.enabled_for?('users', 'show')
    refute InboundHTTPLogger.enabled_for?('users', 'internal')
  end
end

class InboundHTTPLoggerThreadLocalDataTest < InboundHTTPLoggerTestCase
  # This test class specifically tests thread-local data
  # Disable parallelization to prevent thread interference
  parallelize(workers: 0)
  def test_can_set_and_clear_metadata
    metadata = { user_id: 123 }
    InboundHTTPLogger.set_metadata(metadata)

    assert_equal metadata, Thread.current[:inbound_http_logger_metadata]

    InboundHTTPLogger.clear_thread_data
    assert_nil Thread.current[:inbound_http_logger_metadata]
  end

  def test_can_set_and_clear_loggable
    loggable = Object.new
    InboundHTTPLogger.set_loggable(loggable)

    assert_equal loggable, Thread.current[:inbound_http_logger_loggable]

    InboundHTTPLogger.clear_thread_data
    assert_nil Thread.current[:inbound_http_logger_loggable]
  end
end
