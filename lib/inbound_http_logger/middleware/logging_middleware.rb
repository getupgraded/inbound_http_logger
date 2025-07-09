# frozen_string_literal: true

require 'rack'

module InboundHTTPLogger
  module Middleware
    class LoggingMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        # Get configuration once and reuse throughout the request
        config = InboundHTTPLogger.configuration
        return @app.call(env) unless should_log_request?(env, config)

        # Capture start time for duration calculation
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Create request object and read body
        request = Rack::Request.new(env)
        request_body = read_request_body(request)

        # Process the request
        status, headers, response = @app.call(env)

        # Check if we should log based on response content type
        return [status, headers, response] unless should_log_response?(request, status, headers, config)

        # Capture response body if needed
        response_body = (read_response_body(response) if should_capture_response_body?(request, status, headers, config))

        # Calculate duration
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_seconds = end_time - start_time

        # Log the request and response (with error handling)
        begin
          log_request(request, request_body, status, headers, response_body, duration_seconds, config)
        rescue StandardError => e
          # Log the error but don't let it affect the application
          config.logger.error("Error logging inbound request: #{e.class}: #{e.message}")
          config.logger.error(e.backtrace.join("\n")) if config.debug_logging
        end

        # Return the response
        [status, headers, response]
      rescue StandardError => e
        # Log the error but don't let it affect the application
        # Use a fresh config reference in case the error was related to config access
        begin
          logger = InboundHTTPLogger.configuration.logger
          logger.error("Error in InboundHTTPLogger::LoggingMiddleware: #{e.class}: #{e.message}")
          logger.error(e.backtrace.join("\n")) if InboundHTTPLogger.configuration.debug_logging
        rescue StandardError
          # If even logging fails, silently continue to avoid breaking the application
        end

        # Re-raise to allow other error handlers to process it
        raise e
      ensure
        # Clear thread-local data after request
        InboundHTTPLogger.clear_thread_data
      end

      private

        # Check if we should log this request (basic checks)
        def should_log_request?(env, config = InboundHTTPLogger.configuration)
          return false unless config.enabled?

          request = Rack::Request.new(env)
          return false unless config.should_log_path?(request.path)

          # Check controller-level exclusions if available
          if env['action_controller.instance']
            controller = env['action_controller.instance']
            return false unless config.enabled_for_controller?(controller.controller_name, controller.action_name)
          end

          true
        end

        # Check if we should log based on response
        def should_log_response?(_request, _status, headers, config = InboundHTTPLogger.configuration)
          content_type = headers['Content-Type']&.split(';')&.first
          config.should_log_content_type?(content_type)
        end

        # Check if we should capture response body
        def should_capture_response_body?(_request, status, headers, config = InboundHTTPLogger.configuration)
          return false if status == 204 # No Content
          return false if status >= 300 && status < 400 # Redirects typically don't have meaningful bodies

          content_type = headers['Content-Type']&.split(';')&.first
          config.should_log_content_type?(content_type)
        end

        # Read and parse request body
        def read_request_body(request)
          return nil unless request.body

          body = request.body.read
          request.body.rewind # Rewind for downstream middleware

          return nil if body.blank?
          return nil if body.bytesize > InboundHTTPLogger.configuration.max_body_size

          parse_body(body, request.content_type)
        rescue StandardError => e
          InboundHTTPLogger.configuration.logger.error("Error reading request body: #{e.message}")
          body&.first(1000) # Return first 1000 chars if parsing fails
        end

        # Read response body from response array
        def read_response_body(response)
          return nil unless response.respond_to?(:each)

          body_parts = []
          response.each { |part| body_parts << part }
          body = body_parts.join

          return nil if body.blank?
          return nil if body.bytesize > InboundHTTPLogger.configuration.max_body_size

          body
        rescue StandardError => e
          InboundHTTPLogger.configuration.logger.error("Error reading response body: #{e.message}")
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
            rescue StandardError => e
              InboundHTTPLogger.configuration.logger.error("Error parsing form data: #{e.message}")
              body
            end
          else
            body
          end
        end

        # Log the request
        def log_request(request, request_body, status, headers, response_body, duration_seconds, config = InboundHTTPLogger.configuration)
          # Log to main database
          InboundHTTPLogger::Models::InboundRequestLog.log_request(
            request,
            request_body,
            status,
            headers,
            response_body,
            duration_seconds
          )

          # Also log to secondary database if enabled
          if config.secondary_database_enabled?
            adapter = config.secondary_database_adapter_instance
            adapter&.log_request(request, request_body, status, headers, response_body, duration_seconds)
          end

          # Also log to test database if test module is enabled
          return unless defined?(InboundHTTPLogger::Test) && InboundHTTPLogger::Test.enabled?

          InboundHTTPLogger::Test.log_request(request, request_body, status, headers, response_body, duration_seconds)
        end
    end
  end
end
