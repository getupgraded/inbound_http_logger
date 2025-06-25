# frozen_string_literal: true

require 'active_record'
require 'active_support'
require 'rack'

begin
  require 'railties'
rescue LoadError
  # Railties not available, skip Rails integration
end

require_relative 'inbound_http_logger/version'
require_relative 'inbound_http_logger/configuration'
require_relative 'inbound_http_logger/models/inbound_request_log'
require_relative 'inbound_http_logger/middleware/logging_middleware'
require_relative 'inbound_http_logger/concerns/controller_logging'
require_relative 'inbound_http_logger/railtie' if defined?(Rails)

module InboundHttpLogger
  class Error < StandardError; end

  class << self
    # Configuration instance (checks for thread-local override first)
    def configuration
      Thread.current[:inbound_http_logger_config_override] || global_configuration
    end

    # Global configuration instance
    def global_configuration
      @global_configuration ||= Configuration.new
    end

    # Configure the gem with a block
    def configure
      yield(configuration) if block_given?
    end

    # Thread-safe temporary configuration override for testing
    def with_configuration(**overrides)
      return yield if overrides.empty?

      # Create a copy of the current configuration (which may already be an override)
      current_config = configuration
      backup = current_config.backup
      temp_config = Configuration.new
      temp_config.restore(backup)

      # Apply overrides
      overrides.each { |key, value| temp_config.public_send("#{key}=", value) }

      # Set thread-local override
      previous_override = Thread.current[:inbound_http_logger_config_override]
      Thread.current[:inbound_http_logger_config_override] = temp_config
      yield
    ensure
      Thread.current[:inbound_http_logger_config_override] = previous_override
    end

    # Enable logging (can be called without a block)
    def enable!
      configuration.enabled = true
    end

    # Disable logging
    def disable!
      configuration.enabled = false
    end

    # Check if logging is enabled
    delegate :enabled?, to: :configuration

    # Check if logging is enabled for a specific controller/action
    def enabled_for?(controller_name, action_name = nil)
      return false unless enabled?

      configuration.enabled_for_controller?(controller_name, action_name)
    end

    # Set metadata for the current request
    def set_metadata(metadata)
      Thread.current[:inbound_http_logger_metadata] = metadata
    end

    # Set loggable for the current request
    def set_loggable(loggable)
      Thread.current[:inbound_http_logger_loggable] = loggable
    end

    # Clear thread-local data
    def clear_thread_data
      Thread.current[:inbound_http_logger_metadata] = nil
      Thread.current[:inbound_http_logger_loggable] = nil
    end

    # Secondary database logging methods

    # Enable secondary database logging
    def enable_secondary_logging!(database_url = nil, adapter: :sqlite)
      database_url ||= default_secondary_database_url(adapter)
      configuration.configure_secondary_database(database_url, adapter: adapter)
    end

    # Disable secondary database logging
    def disable_secondary_logging!
      configuration.configure_secondary_database(nil)
    end

    # Check if secondary database logging is enabled
    def secondary_logging_enabled?
      configuration.secondary_database_enabled?
    end

    # Reset configuration to defaults (useful for testing)
    # WARNING: This will lose all customizations from initializers
    def reset_configuration!
      @configuration = nil
      # Also clear any thread-local overrides
      Thread.current[:inbound_http_logger_config_override] = nil
    end

    # Create a new configuration instance with defaults
    def create_fresh_configuration
      Configuration.new
    end

    # Clear thread-local configuration override
    def clear_configuration_override
      Thread.current[:inbound_http_logger_config_override] = nil
    end

    private

      def default_secondary_database_url(adapter)
        case adapter.to_sym
        when :sqlite
          'log/inbound_http_requests.sqlite3'
        when :postgresql
          ENV['INBOUND_HTTP_LOGGER_DATABASE_URL'] || 'postgresql://localhost/inbound_http_logger'
        else
          raise ArgumentError, "No default URL for adapter: #{adapter}"
        end
      end
  end
end
