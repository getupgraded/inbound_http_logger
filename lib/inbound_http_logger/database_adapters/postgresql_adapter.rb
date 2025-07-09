# frozen_string_literal: true

require_relative 'base_adapter'
require_relative '../models/inbound_request_log'

module InboundHTTPLogger
  module DatabaseAdapters
    class PostgresqlAdapter < BaseAdapter
      # Check if PostgreSQL gem is available
      def adapter_available?
        @adapter_available ||= begin
          require 'pg'
          true
        rescue LoadError
          InboundHTTPLogger.configuration.logger.warn('pg gem not available. PostgreSQL logging disabled.') if @database_url.present?
          false
        end
      end

      # Establish connection to PostgreSQL database
      def establish_connection
        return unless adapter_available?

        # If no database_url is provided, use the default connection
        if @database_url.blank?
          # Use default connection - no need to establish a separate connection
          return true
        end

        # Parse the database URL
        config = parse_database_url

        # Configure the connection for Rails multiple database support
        # This adds the configuration but doesn't establish as primary connection
        ActiveRecord::Base.configurations.configurations << ActiveRecord::DatabaseConfigurations::HashConfig.new(
          Rails.env,
          connection_name.to_s,
          config
        )
      end

      # Get the model class for PostgreSQL
      def model_class
        @model_class ||= create_model_class
      end

      private

        def parse_database_url
          uri = URI.parse(@database_url)

          {
            'adapter' => 'postgresql',
            'host' => uri.host,
            'port' => uri.port || 5432,
            'database' => uri.path[1..], # Remove leading slash
            'username' => uri.user,
            'password' => uri.password,
            'pool' => 5,
            'timeout' => 5000,
            'encoding' => 'unicode'
          }.compact
        end

        def create_model_class
          adapter_connection_name = connection_name
          use_default_connection = @database_url.blank?

          # If using default connection, just return the main model class
          return InboundHTTPLogger::Models::InboundRequestLog if use_default_connection

          # Create a named class to avoid "Anonymous class is not allowed" error
          class_name = "PostgresqlRequestLog#{adapter_connection_name.to_s.camelize}"

          # Remove existing class if it exists
          InboundHTTPLogger::DatabaseAdapters.send(:remove_const, class_name) if InboundHTTPLogger::DatabaseAdapters.const_defined?(class_name)

          # Create the new class that inherits from the main model
          klass = Class.new(InboundHTTPLogger::Models::InboundRequestLog) do
            self.table_name = 'inbound_request_logs'

            # Store the connection name for use in connection method
            @adapter_connection_name = adapter_connection_name

            # Override connection to use the secondary database
            def self.connection
              if @adapter_connection_name
                # Use configured named connection - fail explicitly if not available
                ActiveRecord::Base.connection_handler.retrieve_connection(@adapter_connection_name.to_s)
              else
                # Use default connection when explicitly configured to do so
                ActiveRecord::Base.connection
              end
            rescue ActiveRecord::ConnectionNotEstablished => e
              # Don't fall back silently - log the specific issue and re-raise
              Rails.logger&.error "InboundHTTPLogger: Cannot retrieve connection '#{@adapter_connection_name}': #{e.message}"
              raise
            end

            class << self
              def log_request(request, request_body, status, headers, response_body, duration_seconds, options = {})
                log_data = InboundHTTPLogger::Models::InboundRequestLog.build_log_data(
                  request, request_body, status, headers, response_body, duration_seconds, options
                )
                return nil unless log_data

                # For PostgreSQL, we can store JSON objects directly in JSONB columns
                log_data = prepare_json_data_for_postgresql(log_data)

                create!(log_data)
              end

              # PostgreSQL-specific text search with JSONB support
              def apply_text_search(scope, q, original_query)
                scope.where(
                  'LOWER(url) LIKE ? OR request_body::text ILIKE ? OR response_body::text ILIKE ?',
                  q, "%#{original_query}%", "%#{original_query}%"
                )
              end

              # PostgreSQL JSONB-specific scopes
              def with_response_containing(key, value)
                where('response_body @> ?', { key => value }.to_json)
              end

              def with_request_containing(key, value)
                where('request_body @> ?', { key => value }.to_json)
              end

              private

                def prepare_json_data_for_postgresql(log_data)
                  # Convert JSON strings back to objects for JSONB storage
                  %i[request_headers request_body response_headers response_body metadata].each do |field|
                    next unless log_data[field].is_a?(String) && log_data[field].present?

                    begin
                      log_data[field] = JSON.parse(log_data[field])
                    rescue JSON::ParserError
                      # Keep as string if not valid JSON
                    end
                  end

                  log_data
                end
            end
          end

          # Assign the class to a constant to give it a name
          InboundHTTPLogger::DatabaseAdapters.const_set(class_name, klass)

          klass
        end

        def build_create_table_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS inbound_request_logs (
              id BIGSERIAL PRIMARY KEY,
              request_id VARCHAR(255),
              http_method VARCHAR(10) NOT NULL,
              url TEXT NOT NULL,
              ip_address INET,
              user_agent TEXT,
              referrer TEXT,
              request_headers JSONB DEFAULT '{}',
              request_body JSONB,
              status_code INTEGER NOT NULL,
              response_headers JSONB DEFAULT '{}',
              response_body JSONB,
              duration_ms DECIMAL(10,2),
              loggable_type VARCHAR(255),
              loggable_id BIGINT,
              metadata JSONB DEFAULT '{}',
              created_at TIMESTAMP WITH TIME ZONE,
              updated_at TIMESTAMP WITH TIME ZONE
            )
          SQL
        end

        def create_indexes_sql
          [
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_request_id ON inbound_request_logs(request_id)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_http_method ON inbound_request_logs(http_method)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_status_code ON inbound_request_logs(status_code)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_created_at ON inbound_request_logs(created_at)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_ip_address ON inbound_request_logs(ip_address)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_duration_ms ON inbound_request_logs(duration_ms)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_loggable ON inbound_request_logs(loggable_type, loggable_id)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_failed_requests ON inbound_request_logs(status_code) WHERE status_code >= 400',
            # JSONB GIN indexes for fast JSON queries
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_request_headers_gin ON inbound_request_logs USING GIN (request_headers)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_request_body_gin ON inbound_request_logs USING GIN (request_body)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_response_headers_gin ON inbound_request_logs USING GIN (response_headers)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_response_body_gin ON inbound_request_logs USING GIN (response_body)',
            'CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_metadata_gin ON inbound_request_logs USING GIN (metadata)'
          ]
        end
    end
  end
end
