# frozen_string_literal: true

module InboundHttpLogger
  # Test utilities for request logging
  module Test
    class << self
      # Configure test logging with a separate database
      def configure(database_url: nil, adapter: :sqlite)
        @test_adapter = create_adapter(database_url, adapter)
        @test_adapter.establish_connection if @test_adapter
      end

      # Enable test logging
      def enable!
        configure unless @test_adapter
        @enabled = true
      end

      # Disable test logging
      def disable!
        @enabled = false
      end

      # Check if test logging is enabled
      def enabled?
        @enabled && @test_adapter&.enabled?
      end

      # Log a request in test mode
      def log_request(request, request_body, status, headers, response_body, duration_seconds, options = {})
        return unless enabled?
        
        @test_adapter.log_request(request, request_body, status, headers, response_body, duration_seconds, options)
      end

      # Count all logged requests
      def logs_count
        return 0 unless enabled?
        @test_adapter.count_logs
      end

      # Count logs with specific status
      def logs_with_status(status)
        return 0 unless enabled?
        @test_adapter.count_logs_with_status(status)
      end

      # Count logs for specific path
      def logs_for_path(path)
        return 0 unless enabled?
        @test_adapter.count_logs_for_path(path)
      end

      # Get all logs
      def all_logs
        return [] unless enabled?
        @test_adapter.all_logs
      end

      # Clear all test logs
      def clear_logs!
        return unless enabled?
        @test_adapter.clear_logs
      end

      # Get logs matching criteria
      def logs_matching(criteria = {})
        return [] unless enabled?
        
        scope = @test_adapter.model_class.all
        
        if criteria[:status]
          scope = scope.where(status_code: criteria[:status])
        end
        
        if criteria[:method]
          scope = scope.where(http_method: criteria[:method].to_s.upcase)
        end
        
        if criteria[:path]
          scope = scope.where("url LIKE ?", "%#{criteria[:path]}%")
        end
        
        if criteria[:ip_address]
          scope = scope.where(ip_address: criteria[:ip_address])
        end
        
        scope.order(created_at: :desc)
      end

      # Analyze request patterns
      def analyze
        return {} unless enabled?
        
        total_requests = logs_count
        return { total_requests: 0 } if total_requests.zero?
        
        successful_requests = logs_with_status_range(200..299)
        client_error_requests = logs_with_status_range(400..499)
        server_error_requests = logs_with_status_range(500..599)
        
        {
          total_requests: total_requests,
          successful_requests: successful_requests,
          client_error_requests: client_error_requests,
          server_error_requests: server_error_requests,
          success_rate: (successful_requests.to_f / total_requests * 100).round(2),
          error_rate: ((client_error_requests + server_error_requests).to_f / total_requests * 100).round(2)
        }
      end

      # Reset test environment
      def reset!
        clear_logs!
        @enabled = false
      end

      private

        def create_adapter(database_url, adapter_type)
          database_url ||= default_test_database_url(adapter_type)
          
          case adapter_type.to_sym
          when :sqlite
            require_relative 'database_adapters/sqlite_adapter'
            DatabaseAdapters::SqliteAdapter.new(database_url, :inbound_http_logger_test)
          when :postgresql
            require_relative 'database_adapters/postgresql_adapter'
            DatabaseAdapters::PostgresqlAdapter.new(database_url, :inbound_http_logger_test)
          else
            raise ArgumentError, "Unsupported adapter: #{adapter_type}"
          end
        end

        def default_test_database_url(adapter_type)
          case adapter_type.to_sym
          when :sqlite
            'tmp/test_inbound_http_requests.sqlite3'
          when :postgresql
            ENV['INBOUND_HTTP_LOGGER_TEST_DATABASE_URL'] || 'postgresql://localhost/inbound_http_logger_test'
          else
            raise ArgumentError, "No default URL for adapter: #{adapter_type}"
          end
        end

        def logs_with_status_range(range)
          return 0 unless enabled?
          
          @test_adapter.model_class.where(status_code: range).count
        end
    end

    # Test helper methods for RSpec/Minitest integration
    module Helpers
      # Setup test logging
      def setup_inbound_http_logger_test(database_url: nil, adapter: :sqlite)
        InboundHttpLogger::Test.configure(database_url: database_url, adapter: adapter)
        InboundHttpLogger::Test.enable!
      end

      # Teardown test logging
      def teardown_inbound_http_logger_test
        InboundHttpLogger::Test.disable!
      end

      # Assert request was logged
      def assert_request_logged(method, path, status: nil)
        criteria = { method: method, path: path }
        criteria[:status] = status if status
        
        logs = InboundHttpLogger::Test.logs_matching(criteria)
        
        if defined?(assert) # Minitest
          assert logs.any?, "Expected request to be logged: #{method.upcase} #{path}"
        elsif defined?(expect) # RSpec
          expect(logs).not_to be_empty, "Expected request to be logged: #{method.upcase} #{path}"
        else
          raise "No test framework detected"
        end
        
        logs.first
      end

      # Assert request count
      def assert_request_count(expected_count, criteria = {})
        actual_count = if criteria.empty?
                        InboundHttpLogger::Test.logs_count
                      else
                        InboundHttpLogger::Test.logs_matching(criteria).count
                      end
        
        if defined?(assert_equal) # Minitest
          assert_equal expected_count, actual_count
        elsif defined?(expect) # RSpec
          expect(actual_count).to eq(expected_count)
        else
          raise "No test framework detected"
        end
      end

      # Assert success rate
      def assert_success_rate(expected_rate, tolerance: 0.1)
        analysis = InboundHttpLogger::Test.analyze
        actual_rate = analysis[:success_rate]
        
        if defined?(assert_in_delta) # Minitest
          assert_in_delta expected_rate, actual_rate, tolerance
        elsif defined?(expect) # RSpec
          expect(actual_rate).to be_within(tolerance).of(expected_rate)
        else
          raise "No test framework detected"
        end
      end
    end
  end
end
