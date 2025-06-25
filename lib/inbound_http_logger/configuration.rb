# frozen_string_literal: true

module InboundHttpLogger
  class Configuration
    attr_accessor :enabled, :debug_logging, :max_body_size, :log_level, :secondary_database_url,
                  :secondary_database_adapter, :logger_factory, :cache_adapter
    attr_reader :excluded_paths, :excluded_content_types, :sensitive_headers, :sensitive_body_keys,
                :excluded_controllers, :excluded_actions

    def initialize
      @enabled = false
      @debug_logging = false
      @max_body_size = 10_000 # 10KB default
      @log_level = :info

      # Dependency injection for Rails integration
      @logger_factory = nil
      @cache_adapter = nil

      # Secondary database configuration
      @secondary_database_url = nil
      @secondary_database_adapter = :sqlite

      # Default exclusions for paths
      @excluded_paths = Set.new([
                                  %r{^/assets/},
                                  %r{^/packs/},
                                  %r{^/health$},
                                  %r{^/ping$},
                                  %r{^/favicon\.ico$},
                                  %r{^/robots\.txt$},
                                  %r{^/sitemap\.xml$},
                                  /\.css$/,
                                  /\.js$/,
                                  /\.map$/,
                                  /\.ico$/,
                                  /\.png$/,
                                  /\.jpg$/,
                                  /\.jpeg$/,
                                  /\.gif$/,
                                  /\.svg$/,
                                  /\.woff$/,
                                  /\.woff2$/,
                                  /\.ttf$/,
                                  /\.eot$/
                                ])

      # Default exclusions for content types
      @excluded_content_types = Set.new([
                                          'text/html',
                                          'text/css',
                                          'text/javascript',
                                          'application/javascript',
                                          'application/x-javascript',
                                          'image/png',
                                          'image/jpeg',
                                          'image/gif',
                                          'image/svg+xml',
                                          'image/webp',
                                          'image/x-icon',
                                          'video/mp4',
                                          'video/webm',
                                          'audio/mpeg',
                                          'audio/wav',
                                          'font/woff',
                                          'font/woff2',
                                          'application/font-woff',
                                          'application/font-woff2'
                                        ])

      # Default sensitive headers to filter
      @sensitive_headers = Set.new(%w[
                                     authorization
                                     cookie
                                     set-cookie
                                     x-api-key
                                     x-auth-token
                                     x-access-token
                                     bearer
                                     x-csrf-token
                                     x-session-id
                                   ])

      # Default sensitive body keys to filter
      @sensitive_body_keys = Set.new(%w[
                                       password
                                       secret
                                       token
                                       key
                                       auth
                                       credential
                                       private
                                       ssn
                                       social_security_number
                                       credit_card
                                       card_number
                                       cvv
                                       pin
                                     ])

      # Controller/action exclusions
      @excluded_controllers = Set.new([
                                        'rails/health',
                                        'rails/info',
                                        'action_cable/internal'
                                      ])

      @excluded_actions = {}
    end

    def enabled?
      @enabled
    end

    # Check if we should log a specific path
    def should_log_path?(path)
      return false unless path

      @excluded_paths.none? { |pattern| pattern.match?(path) }
    end

    # Check if we should log a specific content type
    def should_log_content_type?(content_type)
      return true unless content_type

      # Extract the main content type (before semicolon)
      main_type = content_type.split(';').first&.strip&.downcase
      return true unless main_type

      !@excluded_content_types.include?(main_type)
    end

    # Check if we should log for a specific controller/action
    def enabled_for_controller?(controller_name, action_name = nil)
      return false if @excluded_controllers.include?(controller_name.to_s)

      return false if action_name && @excluded_actions[controller_name.to_s]&.include?(action_name.to_s)

      true
    end

    # Add controller exclusion
    def exclude_controller(controller_name)
      @excluded_controllers << controller_name.to_s
    end

    # Add action exclusion for a specific controller
    def exclude_action(controller_name, action_name)
      controller_key = controller_name.to_s
      @excluded_actions[controller_key] ||= Set.new
      @excluded_actions[controller_key] << action_name.to_s
    end

    # Filter sensitive headers
    #
    # NOTE: Filter methods are placed on the Configuration class (rather than a separate
    # service object) because the filtering logic is entirely driven by configuration data
    # (sensitive_headers, sensitive_body_keys, max_body_size). This encapsulates both the
    # filtering rules and their application in one place, ensuring thread-safe access to
    # configuration overrides and providing a clean API without additional objects.
    def filter_headers(headers)
      return {} unless headers.is_a?(Hash)

      filtered = {}
      headers.each do |key, value|
        header_key = key.to_s.downcase
        filtered[key] = if @sensitive_headers.any? { |sensitive| header_key.include?(sensitive) }
                          '[FILTERED]'
                        else
                          value
                        end
      end
      filtered
    end

    # Filter sensitive body data (for JSON columns - re-serializes filtered data)
    def filter_body(body)
      return body unless body.is_a?(String) && body.present?
      return body if body.bytesize > @max_body_size

      begin
        # Try to parse as JSON
        parsed = JSON.parse(body)
        filtered = filter_sensitive_data_internal(parsed)
        JSON.generate(filtered)
      rescue JSON::ParserError
        # If not JSON, return as-is
        body
      end
    end

    # Filter sensitive data from parsed objects (for JSONB columns - returns filtered object)
    # Exposed for use by models that need to filter already-parsed data
    def filter_sensitive_data(data)
      filter_sensitive_data_internal(data)
    end

    # Get the logger instance (with dependency injection support)
    def logger
      if @logger_factory
        @logger_factory.call
      else
        @logger ||= if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
                      Rails.logger
                    else
                      require 'logger'
                      Logger.new($stdout)
                    end
      end
    end

    # Check if secondary database logging is enabled
    def secondary_database_enabled?
      @secondary_database_url.present?
    end

    # Get the secondary database adapter instance
    def secondary_database_adapter_instance
      return nil unless secondary_database_enabled?

      @secondary_database_adapter_instance ||= create_secondary_adapter
    end

    # Configure secondary database
    def configure_secondary_database(url, adapter: :sqlite)
      @secondary_database_url = url
      @secondary_database_adapter = adapter
      @secondary_database_adapter_instance = nil # Reset cached adapter
    end

    # Create a backup of the current configuration state
    def backup
      {
        enabled: @enabled,
        debug_logging: @debug_logging,
        max_body_size: @max_body_size,
        log_level: @log_level,
        secondary_database_url: @secondary_database_url,
        secondary_database_adapter: @secondary_database_adapter,
        logger_factory: @logger_factory,
        cache_adapter: @cache_adapter,
        excluded_paths: @excluded_paths.dup,
        excluded_content_types: @excluded_content_types.dup,
        sensitive_headers: @sensitive_headers.dup,
        sensitive_body_keys: @sensitive_body_keys.dup,
        excluded_controllers: @excluded_controllers.dup,
        excluded_actions: @excluded_actions.dup
      }
    end

    # Restore configuration from a backup
    def restore(backup)
      @enabled = backup[:enabled]
      @debug_logging = backup[:debug_logging]
      @max_body_size = backup[:max_body_size]
      @log_level = backup[:log_level]
      @secondary_database_url = backup[:secondary_database_url]
      @secondary_database_adapter = backup[:secondary_database_adapter]
      @logger_factory = backup[:logger_factory]
      @cache_adapter = backup[:cache_adapter]
      @excluded_paths = backup[:excluded_paths]
      @excluded_content_types = backup[:excluded_content_types]
      @sensitive_headers = backup[:sensitive_headers]
      @sensitive_body_keys = backup[:sensitive_body_keys]
      @excluded_controllers = backup[:excluded_controllers]
      @excluded_actions = backup[:excluded_actions]

      # Reset cached instances
      @logger = nil
      @secondary_database_adapter_instance = nil
    end

    private

      def create_secondary_adapter
        case @secondary_database_adapter.to_sym
        when :sqlite
          require_relative 'database_adapters/sqlite_adapter'
          DatabaseAdapters::SqliteAdapter.new(@secondary_database_url)
        when :postgresql
          require_relative 'database_adapters/postgresql_adapter'
          DatabaseAdapters::PostgresqlAdapter.new(@secondary_database_url)
        else
          logger.error("Unsupported secondary database adapter: #{@secondary_database_adapter}")
          nil
        end
      end

      # Recursively filter sensitive data from hashes and arrays
      def filter_sensitive_data_internal(data)
        case data
        when Hash
          filtered = {}
          data.each do |key, value|
            key_str = key.to_s.downcase
            filtered[key] = if @sensitive_body_keys.any? { |sensitive| key_str.include?(sensitive) }
                              '[FILTERED]'
                            else
                              filter_sensitive_data_internal(value)
                            end
          end
          filtered
        when Array
          data.map { |item| filter_sensitive_data_internal(item) }
        else
          data
        end
      end
  end
end
