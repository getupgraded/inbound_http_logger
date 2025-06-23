# frozen_string_literal: true

require 'set'

module InboundHttpLogger
  class Configuration
    attr_accessor :enabled, :debug_logging, :max_body_size, :log_level
    attr_accessor :secondary_database_url, :secondary_database_adapter
    attr_reader :excluded_paths, :excluded_content_types, :sensitive_headers, :sensitive_body_keys
    attr_reader :excluded_controllers, :excluded_actions

    def initialize
      @enabled = false
      @debug_logging = false
      @max_body_size = 10_000 # 10KB default
      @log_level = :info

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
                                  %r{\.css$},
                                  %r{\.js$},
                                  %r{\.map$},
                                  %r{\.ico$},
                                  %r{\.png$},
                                  %r{\.jpg$},
                                  %r{\.jpeg$},
                                  %r{\.gif$},
                                  %r{\.svg$},
                                  %r{\.woff$},
                                  %r{\.woff2$},
                                  %r{\.ttf$},
                                  %r{\.eot$}
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
      @sensitive_headers = Set.new([
                                     'authorization',
                                     'cookie',
                                     'set-cookie',
                                     'x-api-key',
                                     'x-auth-token',
                                     'x-access-token',
                                     'bearer',
                                     'x-csrf-token',
                                     'x-session-id'
                                   ])

      # Default sensitive body keys to filter
      @sensitive_body_keys = Set.new([
                                       'password',
                                       'secret',
                                       'token',
                                       'key',
                                       'auth',
                                       'credential',
                                       'private',
                                       'ssn',
                                       'social_security_number',
                                       'credit_card',
                                       'card_number',
                                       'cvv',
                                       'pin'
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

      !@excluded_paths.any? { |pattern| pattern.match?(path) }
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

      if action_name && @excluded_actions[controller_name.to_s]
        return false if @excluded_actions[controller_name.to_s].include?(action_name.to_s)
      end

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
    def filter_headers(headers)
      return {} unless headers.is_a?(Hash)

      filtered = {}
      headers.each do |key, value|
        header_key = key.to_s.downcase
        if @sensitive_headers.any? { |sensitive| header_key.include?(sensitive) }
          filtered[key] = '[FILTERED]'
        else
          filtered[key] = value
        end
      end
      filtered
    end

    # Filter sensitive body data
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

    # Expose filter_sensitive_data for use by models
    def filter_sensitive_data(data)
      filter_sensitive_data_internal(data)
    end

    # Get the logger instance
    def logger
      @logger ||= begin
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger
        else
          require 'logger'
          Logger.new(STDOUT)
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

      @secondary_adapter ||= create_secondary_adapter
    end

    # Configure secondary database
    def configure_secondary_database(url, adapter: :sqlite)
      @secondary_database_url = url
      @secondary_database_adapter = adapter
      @secondary_adapter = nil # Reset cached adapter
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
            if @sensitive_body_keys.any? { |sensitive| key_str.include?(sensitive) }
              filtered[key] = '[FILTERED]'
            else
              filtered[key] = filter_sensitive_data_internal(value)
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
