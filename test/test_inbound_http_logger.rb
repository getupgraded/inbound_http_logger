# frozen_string_literal: true

require 'test_helper'

describe InboundHTTPLogger do
  it 'has a version number' do
    _(::InboundHTTPLogger::VERSION).wont_be_nil
  end

  describe 'configuration' do
    it 'starts disabled by default' do
      _(InboundHTTPLogger.enabled?).must_equal false
    end

    it 'can be enabled and disabled' do
      InboundHTTPLogger.enable!
      _(InboundHTTPLogger.enabled?).must_equal true

      InboundHTTPLogger.disable!
      _(InboundHTTPLogger.enabled?).must_equal false
    end

    it 'can be configured with a block' do
      InboundHTTPLogger.configure do |config|
        config.enabled = true
        config.debug_logging = true
      end

      _(InboundHTTPLogger.enabled?).must_equal true
      _(InboundHTTPLogger.configuration.debug_logging).must_equal true
    end
  end

  describe 'controller filtering' do
    before do
      InboundHTTPLogger.enable!
    end

    it 'allows normal controllers by default' do
      _(InboundHTTPLogger.enabled_for?('users')).must_equal true
      _(InboundHTTPLogger.enabled_for?('users', 'show')).must_equal true
    end

    it 'excludes Rails internal controllers by default' do
      _(InboundHTTPLogger.enabled_for?('rails/health')).must_equal false
      _(InboundHTTPLogger.enabled_for?('action_cable/internal')).must_equal false
    end

    it 'can exclude custom controllers' do
      InboundHTTPLogger.configuration.exclude_controller('admin')
      _(InboundHTTPLogger.enabled_for?('admin')).must_equal false
      _(InboundHTTPLogger.enabled_for?('admin', 'index')).must_equal false
    end

    it 'can exclude specific actions' do
      InboundHTTPLogger.configuration.exclude_action('users', 'internal')
      _(InboundHTTPLogger.enabled_for?('users', 'show')).must_equal true
      _(InboundHTTPLogger.enabled_for?('users', 'internal')).must_equal false
    end
  end

  describe 'thread-local data management' do
    it 'can set and clear metadata' do
      metadata = { user_id: 123 }
      InboundHTTPLogger.set_metadata(metadata)

      _(Thread.current[:inbound_http_logger_metadata]).must_equal metadata

      InboundHTTPLogger.clear_thread_data
      _(Thread.current[:inbound_http_logger_metadata]).must_be_nil
    end

    it 'can set and clear loggable' do
      loggable = Object.new
      InboundHTTPLogger.set_loggable(loggable)

      _(Thread.current[:inbound_http_logger_loggable]).must_equal loggable

      InboundHTTPLogger.clear_thread_data
      _(Thread.current[:inbound_http_logger_loggable]).must_be_nil
    end
  end
end
