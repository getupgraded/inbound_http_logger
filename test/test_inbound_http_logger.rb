# frozen_string_literal: true

require 'test_helper'

describe InboundHttpLogger do
  it 'has a version number' do
    _(::InboundHttpLogger::VERSION).wont_be_nil
  end

  describe 'configuration' do
    it 'starts disabled by default' do
      _(InboundHttpLogger.enabled?).must_equal false
    end

    it 'can be enabled and disabled' do
      InboundHttpLogger.enable!
      _(InboundHttpLogger.enabled?).must_equal true

      InboundHttpLogger.disable!
      _(InboundHttpLogger.enabled?).must_equal false
    end

    it 'can be configured with a block' do
      InboundHttpLogger.configure do |config|
        config.enabled = true
        config.debug_logging = true
      end

      _(InboundHttpLogger.enabled?).must_equal true
      _(InboundHttpLogger.configuration.debug_logging).must_equal true
    end
  end

  describe 'controller filtering' do
    before do
      InboundHttpLogger.enable!
    end

    it 'allows normal controllers by default' do
      _(InboundHttpLogger.enabled_for?('users')).must_equal true
      _(InboundHttpLogger.enabled_for?('users', 'show')).must_equal true
    end

    it 'excludes Rails internal controllers by default' do
      _(InboundHttpLogger.enabled_for?('rails/health')).must_equal false
      _(InboundHttpLogger.enabled_for?('action_cable/internal')).must_equal false
    end

    it 'can exclude custom controllers' do
      InboundHttpLogger.configuration.exclude_controller('admin')
      _(InboundHttpLogger.enabled_for?('admin')).must_equal false
      _(InboundHttpLogger.enabled_for?('admin', 'index')).must_equal false
    end

    it 'can exclude specific actions' do
      InboundHttpLogger.configuration.exclude_action('users', 'internal')
      _(InboundHttpLogger.enabled_for?('users', 'show')).must_equal true
      _(InboundHttpLogger.enabled_for?('users', 'internal')).must_equal false
    end
  end

  describe 'thread-local data management' do
    it 'can set and clear metadata' do
      metadata = { user_id: 123 }
      InboundHttpLogger.set_metadata(metadata)

      _(Thread.current[:inbound_http_logger_metadata]).must_equal metadata

      InboundHttpLogger.clear_thread_data
      _(Thread.current[:inbound_http_logger_metadata]).must_be_nil
    end

    it 'can set and clear loggable' do
      loggable = Object.new
      InboundHttpLogger.set_loggable(loggable)

      _(Thread.current[:inbound_http_logger_loggable]).must_equal loggable

      InboundHttpLogger.clear_thread_data
      _(Thread.current[:inbound_http_logger_loggable]).must_be_nil
    end
  end
end
