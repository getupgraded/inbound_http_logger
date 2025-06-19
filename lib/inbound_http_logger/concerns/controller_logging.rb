# frozen_string_literal: true

require 'active_support/concern'

module InboundHttpLogger
  module Concerns
    module ControllerLogging
      extend ActiveSupport::Concern

      included do
        # Add callbacks for automatic logging
        before_action :setup_inbound_logging, if: :should_log_inbound_request?
        after_action :finalize_inbound_logging, if: :should_log_inbound_request?
      end

      class_methods do
        # Skip logging for specific actions
        def skip_inbound_logging(*actions)
          skip_before_action :setup_inbound_logging, only: actions
          skip_after_action :finalize_inbound_logging, only: actions
        end

        # Log only specific actions
        def log_inbound_only(*actions)
          skip_before_action :setup_inbound_logging
          skip_after_action :finalize_inbound_logging

          before_action :setup_inbound_logging, only: actions, if: :should_log_inbound_request?
          after_action :finalize_inbound_logging, only: actions, if: :should_log_inbound_request?
        end
      end

      private

        # Check if we should log this request
        def should_log_inbound_request?
          InboundHttpLogger.enabled_for?(controller_name, action_name)
        end

        # Set up logging metadata before action
        def setup_inbound_logging
          # Set basic metadata
          metadata = {
            controller: controller_name,
            action: action_name,
            format: request.format.to_s
          }

          # Add user information if available
          if respond_to?(:current_user) && current_user
            metadata[:user_id] = current_user.id
            metadata[:user_type] = current_user.class.name
          end

          # Add session information if available
          if session && session.id
            metadata[:session_id] = session.id
          end

          # Add request ID
          if request.request_id
            metadata[:request_id] = request.request_id
          end

          # Set the metadata for this request
          InboundHttpLogger.set_metadata(metadata)
        end

        # Finalize logging after action (if needed for custom logic)
        def finalize_inbound_logging
          # This can be overridden in controllers for custom post-processing
          # The actual logging happens in the middleware
        end

        # Set a loggable object for this request
        def set_inbound_log_loggable(object)
          InboundHttpLogger.set_loggable(object)
        end

        # Add custom metadata to the current request log
        def add_inbound_log_metadata(metadata)
          current_metadata = Thread.current[:inbound_http_logger_metadata] || {}
          InboundHttpLogger.set_metadata(current_metadata.merge(metadata))
        end

        # Log a custom event within the request context
        def log_inbound_event(event_name, data = {})
          current_metadata = Thread.current[:inbound_http_logger_metadata] || {}
          events = current_metadata[:events] || []

          events << {
            event: event_name,
            data: data,
            timestamp: Time.current.iso8601
          }

          add_inbound_log_metadata(events: events)
        end
    end
  end
end
