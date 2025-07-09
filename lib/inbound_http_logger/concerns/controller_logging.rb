# frozen_string_literal: true

require 'active_support/concern'

module InboundHTTPLogger
  module Concerns
    module ControllerLogging
      extend ActiveSupport::Concern

      included do
        # Add callbacks for automatic logging
        after_action :setup_inbound_logging, if: :should_log_inbound_request?
      end

      class_methods do
        # Skip logging for specific actions
        def skip_inbound_logging(*actions)
          skip_after_action :setup_inbound_logging, only: actions
        end

        # Configure request logging with Rails-standard filter options
        # Examples:
        #   log_requests only: [:show, :index]
        #   log_requests except: [:internal, :debug]
        #   log_requests only: [:show, :index], context: :set_log_context
        #   log_requests except: [:internal], context: ->(log) { log.loggable = current_user }
        def log_requests(only: nil, except: nil, context: nil)
          # Validate mutually exclusive options
          raise ArgumentError, "Cannot specify both 'only' and 'except' options" if only && except

          # Store the context callback for later use
          context_callbacks[name] = context if context

          if only
            # Skip all actions, then enable only specified ones
            skip_after_action :setup_inbound_logging

            after_action :setup_inbound_logging, only: only, if: :should_log_inbound_request?
          elsif except
            # Enable all actions (default), then skip specified ones
            skip_after_action :setup_inbound_logging, only: except
          end
          # If neither only nor except is specified, use default behavior (log all actions)
        end

        # Set context callback for all actions (when using default logging)
        # Examples:
        #   inbound_logging_context :set_log_context
        #   inbound_logging_context ->(log) { log.loggable = current_user }
        def inbound_logging_context(callback)
          context_callbacks[name] = callback
        end

        # Get the context callback for this controller class
        # Walks up the inheritance chain to find the first registered callback
        def inbound_logging_context_callback
          # Check current class first
          return context_callbacks[name] if context_callbacks[name]

          # Walk up the inheritance chain
          current_class = self
          while current_class.superclass && current_class.superclass != Object
            current_class = current_class.superclass
            callback = context_callbacks[current_class.name]
            return callback if callback
          end

          nil
        end

        private

          # Class-level private methods for internal configuration management
          def context_callbacks
            @@context_callbacks ||= {}
          end
      end

      # Public API methods for controllers to use

      # Set a loggable object for this request
      def set_inbound_log_loggable(object)
        InboundHTTPLogger.set_loggable(object)
      end

      # Add custom metadata to the current request log
      def add_inbound_log_metadata(metadata)
        current_metadata = Thread.current[:inbound_http_logger_metadata] || {}
        InboundHTTPLogger.set_metadata(current_metadata.merge(metadata))
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

      private

        # Internal callback and helper methods for automatic logging functionality

        # Check if we should log this request
        def should_log_inbound_request?
          InboundHTTPLogger.enabled_for?(controller_name, action_name)
        end

        # Set up logging metadata before action
        def setup_inbound_logging
          # Set basic metadata
          metadata = build_basic_metadata

          # Add user information if available
          add_user_metadata(metadata)

          # Add session and request information
          add_session_metadata(metadata)

          # Set the metadata for this request
          InboundHTTPLogger.set_metadata(metadata)

          # Execute custom context callback if defined
          execute_context_callback
        end

        # Build basic metadata for the request
        def build_basic_metadata
          {
            controller: controller_name,
            action: action_name,
            format: request.format.to_s
          }
        end

        # Add user information to metadata if available
        def add_user_metadata(metadata)
          return unless respond_to?(:current_user) && current_user

          metadata[:user_id] = current_user.id
          metadata[:user_type] = current_user.class.name
        end

        # Add session and request information to metadata
        def add_session_metadata(metadata)
          metadata[:session_id] = session.id if session&.id
          metadata[:request_id] = request.request_id if request.request_id
        end

        # Execute the custom context callback if defined
        def execute_context_callback
          callback = self.class.inbound_logging_context_callback
          return unless callback

          # Create a simple log context object
          log_context = LogContext.new

          case callback
          when Symbol
            # Call method by name if it exists
            method(callback).call(log_context) if respond_to?(callback, true)
          when Proc
            # Call lambda/proc
            instance_exec(log_context, &callback)
          end

          # Apply any metadata or loggable set by the callback
          InboundHTTPLogger.set_loggable(log_context.loggable) if log_context.loggable
          add_inbound_log_metadata(log_context.metadata) if log_context.metadata.any?
        end

        # Private, simple context object for the callback
        class LogContext
          attr_accessor :loggable, :metadata

          def initialize
            @metadata = {}
          end
        end
    end
  end
end
