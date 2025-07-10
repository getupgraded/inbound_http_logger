# frozen_string_literal: true

require 'rails/railtie'

module InboundHTTPLogger
  class Railtie < Rails::Railtie
    # Only register components if the gem is enabled
    # This is a safety net in case the Railtie was loaded despite environment variable check

    # Add middleware to Rails stack only if gem is enabled
    initializer 'inbound_http_logger.middleware' do |app|
      app.middleware.use InboundHTTPLogger::Middleware::LoggingMiddleware if InboundHTTPLogger.gem_enabled?
    end

    # Add controller concern to ActionController::Base only if gem is enabled
    initializer 'inbound_http_logger.controller_concern' do
      if InboundHTTPLogger.gem_enabled?
        ActiveSupport.on_load(:action_controller) do
          include InboundHTTPLogger::Concerns::ControllerLogging
        end
      end
    end

    # Add rake tasks
    rake_tasks do
      load File.expand_path('tasks/inbound_http_logger.rake', __dir__) if InboundHTTPLogger.gem_enabled?
    end

    # Add generators
    generators do
      require_relative 'generators/migration_generator' if InboundHTTPLogger.gem_enabled?
    end
  end
end
