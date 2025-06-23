# frozen_string_literal: true

require 'rack'

module InboundHttpLogger
  module Middleware
    class LoggingMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless should_log_request?(env)

        # Capture start time for duration calculation
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Create request object and read body
        request = Rack::Request.new(env)
        request_body = read_request_body(request)

        # Process the request
        status, headers, response = @app.call(env)

        # Check if we should log based on response content type
        return [status, headers, response] unless should_log_response?(request, status, headers)

        # Capture response body if needed
        response_body = should_capture_response_body?(request, status, headers) ?
                       read_response_body(response) : nil

        # Calculate duration
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_seconds = end_time - start_time

        # Log the request and response (with error handling)
        begin
          log_request(request, request_body, status, headers, response_body, duration_seconds)
        rescue => log_error
          # Log the error but don't let it affect the application
          InboundHttpLogger.configuration.logger.error("Error logging inbound request: #{log_error.class}: #{log_error.message}")
          InboundHttpLogger.configuration.logger.error(log_error.backtrace.join("\n")) if InboundHttpLogger.configuration.debug_logging
        end

        # Return the response
        [status, headers, response]
      rescue => e
        # Log the error but don't let it affect the application
        InboundHttpLogger.configuration.logger.error("Error in InboundHttpLogger::LoggingMiddleware: #{e.class}: #{e.message}")
        InboundHttpLogger.configuration.logger.error(e.backtrace.join("\n")) if InboundHttpLogger.configuration.debug_logging

        # Re-raise to allow other error handlers to process it
        raise e
      ensure
        # Clear thread-local data after request
        InboundHttpLogger.clear_thread_data
      end

      private

        # Check if we should log this request (basic checks)
        def should_log_request?(env)
          return false unless InboundHttpLogger.enabled?

          request = Rack::Request.new(env)
          return false unless InboundHttpLogger.configuration.should_log_path?(request.path)

          # Check controller-level exclusions if available
          if env['action_controller.instance']
            controller = env['action_controller.instance']
            return false unless InboundHttpLogger.enabled_for?(controller.controller_name, controller.action_name)
          end

          true
        end

        # Check if we should log based on response
        def should_log_response?(request, status, headers)
          content_type = headers['Content-Type']&.split(';')&.first
          InboundHttpLogger.configuration.should_log_content_type?(content_type)
        end

        # Check if we should capture response body
        def should_capture_response_body?(request, status, headers)
          return false if status == 204 # No Content
          return false if status >= 300 && status < 400 # Redirects typically don't have meaningful bodies

          content_type = headers['Content-Type']&.split(';')&.first
          InboundHttpLogger.configuration.should_log_content_type?(content_type)
        end

        # Read and parse request body
        def read_request_body(request)
          return nil unless request.body

          body = request.body.read
          request.body.rewind # Rewind for downstream middleware

          return nil if body.blank?
          return nil if body.bytesize > InboundHttpLogger.configuration.max_body_size

          parse_body(body, request.content_type)
        rescue => e
          InboundHttpLogger.configuration.logger.error("Error reading request body: #{e.message}")
          body&.first(1000) # Return first 1000 chars if parsing fails
        end

        # Read response body from response array
        def read_response_body(response)
          return nil unless response.respond_to?(:each)

          body_parts = []
          response.each { |part| body_parts << part }
          body = body_parts.join

          return nil if body.blank?
          return nil if body.bytesize > InboundHttpLogger.configuration.max_body_size

          body
        rescue => e
          InboundHttpLogger.configuration.logger.error("Error reading response body: #{e.message}")
          nil
        end

        # Parse body based on content type
        def parse_body(body, content_type)
          return body unless content_type

          case content_type.split(';').first&.downcase
          when 'application/json'
            begin
              JSON.parse(body)
            rescue JSON::ParserError
              body
            end
          when 'application/x-www-form-urlencoded'
            begin
              Rack::Utils.parse_nested_query(body)
            rescue => e
              InboundHttpLogger.configuration.logger.error("Error parsing form data: #{e.message}")
              body
            end
          else
            body
          end
        end

        # Log the request
        def log_request(request, request_body, status, headers, response_body, duration_seconds)
          # Log to main database
          InboundHttpLogger::Models::InboundRequestLog.log_request(
            request,
            request_body,
            status,
            headers,
            response_body,
            duration_seconds
          )

          # Also log to secondary database if enabled
          if InboundHttpLogger.configuration.secondary_database_enabled?
            adapter = InboundHttpLogger.configuration.secondary_database_adapter_instance
            adapter&.log_request(request, request_body, status, headers, response_body, duration_seconds)
          end

          # Also log to test database if test module is enabled
          if InboundHttpLogger::Test.enabled?
            InboundHttpLogger::Test.log_request(request, request_body, status, headers, response_body, duration_seconds)
          end
        end
    end
  end
end
