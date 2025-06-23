# frozen_string_literal: true

require_relative 'base_adapter'

module InboundHttpLogger
  module DatabaseAdapters
    class SqliteAdapter < BaseAdapter
      # Check if SQLite3 gem is available
      def adapter_available?
        @adapter_available ||= begin
          require 'sqlite3'
          true
        rescue LoadError
          InboundHttpLogger.configuration.logger.warn("SQLite3 gem not available. SQLite logging disabled.") if @database_url.present?
          false
        end
      end

      # Establish connection to SQLite database
      def establish_connection
        return unless adapter_available?

        # Parse database URL or use as file path
        db_path = parse_database_path

        # Ensure directory exists
        FileUtils.mkdir_p(File.dirname(db_path))

        # Configure the connection for Rails multiple database support
        config = {
          'adapter' => 'sqlite3',
          'database' => db_path,
          'pool' => 5,
          'timeout' => 5000
        }

        # Add to Rails configurations (but don't establish as primary connection)
        ActiveRecord::Base.configurations.configurations << ActiveRecord::DatabaseConfigurations::HashConfig.new(
          Rails.env,
          connection_name.to_s,
          config
        )

        # Ensure the database file is writable
        File.chmod(0o644, db_path) if File.exist?(db_path)
      end

      # Get the model class for SQLite
      def model_class
        @model_class ||= create_model_class
      end

      private

        def parse_database_path
          if @database_url.start_with?('sqlite3://')
            # Handle sqlite3://path/to/db.sqlite3 format
            @database_url.sub('sqlite3://', '')
          elsif @database_url.start_with?('sqlite://')
            # Handle sqlite://path/to/db.sqlite3 format
            @database_url.sub('sqlite://', '')
          else
            # Treat as direct file path
            @database_url
          end
        end

        def create_model_class
          adapter_connection_name = self.connection_name

          # Create a named class to avoid "Anonymous class is not allowed" error
          class_name = "SqliteRequestLog#{adapter_connection_name.to_s.camelize}"

          # Remove existing class if it exists
          if InboundHttpLogger::DatabaseAdapters.const_defined?(class_name)
            InboundHttpLogger::DatabaseAdapters.send(:remove_const, class_name)
          end

          # Create the new class
          klass = Class.new(InboundHttpLogger::Models::BaseRequestLog) do
            self.table_name = 'inbound_request_logs'

            class << self
              def log_request(request, request_body, status, headers, response_body, duration_seconds, options = {})
                log_data = build_log_data(request, request_body, status, headers, response_body, duration_seconds, options)
                return nil unless log_data

                create!(log_data)
              end

              # SQLite-specific text search
              def apply_text_search(scope, q, original_query)
                scope.where(
                  'LOWER(url) LIKE ? OR LOWER(request_body) LIKE ? OR LOWER(response_body) LIKE ?',
                  q, q, q
                )
              end

              # SQLite-specific JSON scopes
              def with_response_containing(key, value)
                where("JSON_EXTRACT(response_body, ?) = ?", "$.#{key}", value.to_s)
              end

              def with_request_containing(key, value)
                where("JSON_EXTRACT(request_body, ?) = ?", "$.#{key}", value.to_s)
              end
            end
          end

          # Assign the class to a constant to give it a name
          InboundHttpLogger::DatabaseAdapters.const_set(class_name, klass)

          # Establish connection to the specific database
          klass.establish_connection(adapter_connection_name)

          klass
        end

        def build_create_table_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS inbound_request_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              request_id TEXT,
              http_method TEXT NOT NULL,
              url TEXT NOT NULL,
              ip_address TEXT,
              user_agent TEXT,
              referrer TEXT,
              request_headers TEXT DEFAULT '{}',
              request_body TEXT,
              status_code INTEGER NOT NULL,
              response_headers TEXT DEFAULT '{}',
              response_body TEXT,
              duration_seconds REAL,
              duration_ms REAL,
              loggable_type TEXT,
              loggable_id INTEGER,
              metadata TEXT DEFAULT '{}',
              created_at TEXT,
              updated_at TEXT
            )
          SQL
        end

        def create_indexes_sql
          [
            "CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_request_id ON inbound_request_logs(request_id)",
            "CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_http_method ON inbound_request_logs(http_method)",
            "CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_status_code ON inbound_request_logs(status_code)",
            "CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_created_at ON inbound_request_logs(created_at)",
            "CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_ip_address ON inbound_request_logs(ip_address)",
            "CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_duration_ms ON inbound_request_logs(duration_ms)",
            "CREATE INDEX IF NOT EXISTS idx_inbound_request_logs_failed_requests ON inbound_request_logs(status_code) WHERE status_code >= 400"
          ]
        end
    end
  end
end
