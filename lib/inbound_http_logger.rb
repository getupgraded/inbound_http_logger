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

module InboundHTTPLogger
  class Error < StandardError; end

  @config_mutex = Mutex.new

  class << self
    # Check if the gem is enabled via environment variable
    # @return [Boolean] true if the gem should be loaded and active
    def gem_enabled?
      env_value = ENV['ENABLE_INBOUND_HTTP_LOGGER']
      return true if env_value.blank? # Default to enabled

      # Treat 'false', 'FALSE', '0', 'no', 'off' as disabled
      !%w[false FALSE 0 no off].include?(env_value.to_s.strip)
    end

    # Configuration instance (with thread-local override support)
    def configuration
      # Check for thread-local configuration override
      override = Thread.current[:inbound_http_logger_config_override]
      return override if override

      # Fall back to global configuration
      global_configuration
    end

    # Global configuration instance (thread-safe)
    def global_configuration
      @config_mutex.synchronize do
        @global_configuration ||= Configuration.new
      end
    end

    # Configure the gem with a block
    def configure
      yield(configuration) if block_given?
    end

    # Thread-safe configuration override
    def with_configuration(**overrides)
      return yield if overrides.empty?

      # Create a copy of the current configuration (global or existing thread-local)
      current_config = configuration
      override_config = current_config.class.new

      # Use backup/restore to copy all settings
      backup = current_config.backup
      override_config.restore(backup)

      # Apply overrides
      overrides.each { |key, value| override_config.public_send("#{key}=", value) }

      # Store previous thread-local override (if any)
      previous_override = Thread.current[:inbound_http_logger_config_override]

      # Set thread-local override
      Thread.current[:inbound_http_logger_config_override] = override_config

      yield
    ensure
      # Restore previous thread-local override (or clear if none)
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

    # Clear thread-local data (for test cleanup)
    def clear_thread_data
      # Thread.current[:inbound_http_logger_config_override] = nil  # Disabled
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
      @config_mutex.synchronize do
        @global_configuration = nil
      end
      # Also clear any thread-local overrides
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

# Only load Railtie if Rails is defined AND the gem is enabled via environment variable
require_relative 'inbound_http_logger/railtie' if defined?(Rails) && !%w[false FALSE 0 no off].include?(ENV['ENABLE_INBOUND_HTTP_LOGGER'].to_s.strip)
