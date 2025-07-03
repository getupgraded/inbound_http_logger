# frozen_string_literal: true

require 'rails/railtie'

module InboundHTTPLogger
  class Railtie < Rails::Railtie
    # Add middleware to Rails stack (always add, but check enabled status in middleware)
    initializer 'inbound_http_logger.middleware' do |app|
      app.middleware.use InboundHTTPLogger::Middleware::LoggingMiddleware
    end

    # Add controller concern to ActionController::Base
    initializer 'inbound_http_logger.controller_concern' do
      ActiveSupport.on_load(:action_controller) do
        include InboundHTTPLogger::Concerns::ControllerLogging
      end
    end

    # Add rake tasks
    rake_tasks do
      load File.expand_path('tasks/inbound_http_logger.rake', __dir__)
    end

    # Add generators
    generators do
      require_relative 'generators/migration_generator'
    end
  end
end
