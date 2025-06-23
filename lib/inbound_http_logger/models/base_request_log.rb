# frozen_string_literal: true

require 'active_record'

module InboundHttpLogger
  module Models
    # Shared base class for request logging functionality
    class BaseRequestLog < ActiveRecord::Base
      self.abstract_class = true

      # Associations
      belongs_to :loggable, polymorphic: true, optional: true

      # Validations
      validates :http_method, presence: true
      validates :url, presence: true
      validates :status_code, presence: true, numericality: { only_integer: true }

      # Scopes
      scope :recent, -> { order(created_at: :desc) }
      scope :with_status, ->(status) { where(status_code: status) }
      scope :with_method, ->(method) { where(http_method: method.to_s.upcase) }
      scope :for_loggable, ->(loggable) { where(loggable: loggable) }
      scope :with_error, -> { where('status_code >= ?', 400) }
      scope :successful, -> { where(status_code: 200..399) }
      scope :failed, -> { where('status_code >= 400') }
      scope :slow, ->(threshold_ms = 1000) { where('duration_ms > ?', threshold_ms) }

      class << self
        # Main logging method - to be implemented by subclasses
        def log_request(request, request_body, status, headers, response_body, duration_seconds, options = {})
          raise NotImplementedError, "Subclasses must implement log_request"
        end

        # Shared logging logic
        def build_log_data(request, request_body, status, headers, response_body, duration_seconds, options = {})
          return nil unless request&.path
          return nil unless InboundHttpLogger.configuration.should_log_path?(request.path)

          # Calculate duration in milliseconds
          duration_ms = (duration_seconds * 1000).round(2)

          # Get metadata and loggable from thread-local or options
          metadata = Thread.current[:inbound_http_logger_metadata] || options[:metadata] || {}
          loggable = Thread.current[:inbound_http_logger_loggable] || options[:loggable]

          # Add controller/action to metadata if available
          if request.env['action_controller.instance']
            controller = request.env['action_controller.instance']
            metadata = metadata.merge(
              controller: controller.controller_name,
              action: controller.action_name
            )
          end

          # Filter sensitive data
          filtered_request_headers = InboundHttpLogger.configuration.filter_headers(extract_request_headers(request))
          filtered_response_headers = InboundHttpLogger.configuration.filter_headers(headers)
          filtered_request_body = filter_body_for_storage(request_body)
          filtered_response_body = filter_body_for_storage(response_body)

          {
            request_id: request.env['action_dispatch.request_id'] || SecureRandom.uuid,
            http_method: request.request_method,
            url: request.fullpath,
            ip_address: request.ip,
            user_agent: request.user_agent || request.env['HTTP_USER_AGENT'],
            referrer: request.referer || request.env['HTTP_REFERER'],
            request_headers: filtered_request_headers,
            request_body: filtered_request_body,
            status_code: status,
            response_headers: filtered_response_headers,
            response_body: filtered_response_body,
            duration_seconds: duration_seconds,
            duration_ms: duration_ms,
            loggable_type: loggable&.class&.name,
            loggable_id: loggable&.id,
            metadata: metadata,
            created_at: Time.current.utc,
            updated_at: Time.current.utc
          }
        end

        # Search logs by various criteria
        def search(params = {})
          scope = all

          # General search
          if params[:q].present?
            q = "%#{params[:q].downcase}%"
            scope = apply_text_search(scope, q, params[:q])
          end

          # Filter by status
          if params[:status].present?
            statuses = Array(params[:status]).map(&:to_i)
            scope = scope.where(status_code: statuses)
          end

          # Filter by HTTP method
          if params[:method].present?
            methods = Array(params[:method]).map(&:upcase)
            scope = scope.where(http_method: methods)
          end

          # Filter by IP address
          if params[:ip_address].present?
            scope = scope.where(ip_address: params[:ip_address])
          end

          # Filter by loggable
          if params[:loggable_id].present? && params[:loggable_type].present?
            scope = scope.where(
              loggable_id: params[:loggable_id],
              loggable_type: params[:loggable_type]
            )
          end

          # Filter by date range
          if params[:start_date].present?
            start_date = Time.zone.parse(params[:start_date]).beginning_of_day rescue nil
            scope = scope.where('created_at >= ?', start_date) if start_date
          end

          if params[:end_date].present?
            end_date = Time.zone.parse(params[:end_date]).end_of_day rescue nil
            scope = scope.where('created_at <= ?', end_date) if end_date
          end

          scope
        end

        # Clean up old logs
        def cleanup(older_than_days = 90)
          where('created_at < ?', older_than_days.days.ago).delete_all
        end

        private

          # Database-specific text search - to be overridden by subclasses
          def apply_text_search(scope, q, original_query)
            scope.where(
              'LOWER(url) LIKE ? OR LOWER(request_body) LIKE ? OR LOWER(response_body) LIKE ?',
              q, q, q
            )
          end

          # Filter body for storage - to be overridden by subclasses if needed
          def filter_body_for_storage(body)
            return body unless body.is_a?(String) && body.present?
            return body if body.bytesize > InboundHttpLogger.configuration.max_body_size

            InboundHttpLogger.configuration.filter_body(body)
          end

          # Extract request headers from Rack env
          def extract_request_headers(request)
            headers = {}
            request.env.each do |key, value|
              if key.start_with?('HTTP_')
                header_name = key[5..].split('_').map(&:capitalize).join('-')
                headers[header_name] = value
              elsif %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
                header_name = key.split('_').map(&:capitalize).join('-')
                headers[header_name] = value
              end
            end
            headers
          end
      end

      # Instance methods

      # Get a formatted string of the request method and URL
      def formatted_call
        "#{http_method} #{url}"
      end

      # Get a formatted string of the request
      def formatted_request
        "#{http_method} #{url}\n#{formatted_headers(request_headers)}\n\n#{formatted_body(request_body)}"
      end

      # Get a formatted string of the response
      def formatted_response
        "HTTP #{status_code} #{status_text}\n#{formatted_headers(response_headers)}\n\n#{formatted_body(response_body)}"
      end

      # Check if the request was successful
      def success?
        status_code.between?(200, 399)
      end

      # Check if the request failed
      def failure?
        !success?
      end

      # Check if the request was slow
      def slow?(threshold_ms = 1000)
        duration_ms && duration_ms > threshold_ms
      end

      # Get the duration in a human-readable format
      def formatted_duration
        return 'N/A' unless duration_ms

        if duration_ms < 1000
          "#{duration_ms.round(2)}ms"
        else
          "#{duration_seconds.round(2)}s"
        end
      end

      # Get status text
      def status_text
        Rack::Utils::HTTP_STATUS_CODES[status_code] || status_code.to_s
      end

      private

        # Format headers for display
        def formatted_headers(headers)
          return '' unless headers.is_a?(Hash)

          headers.map { |key, value| "#{key}: #{value}" }.join("\n")
        end

        # Format body for display
        def formatted_body(body)
          return '' unless body

          case body
          when String
            body
          when Hash, Array
            JSON.pretty_generate(body)
          else
            body.to_s
          end
        end
    end
  end
end
