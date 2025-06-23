# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module InboundHttpLogger
  module Generators
    class MigrationGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)
      desc 'Generate migration for InboundHttpLogger'

      def create_migration_file
        migration_template(
          'create_inbound_request_logs.rb.erb',
          'db/migrate/create_inbound_request_logs.rb'
        )
      end

      private

        def migration_class_name
          'CreateInboundRequestLogs'
        end

        def table_name
          'inbound_request_logs'
        end
    end
  end
end
