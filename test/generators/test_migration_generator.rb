# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'active_record'
require 'rails/generators'
require 'rails/generators/active_record'
require 'inbound_http_logger/generators/migration_generator'
require 'tmpdir'
require 'fileutils'

describe InboundHttpLogger::Generators::MigrationGenerator do
  before do
    @tmp = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@tmp, 'db/migrate'))
    InboundHttpLogger::Generators::MigrationGenerator.start([], destination_root: @tmp)
    @migration_path = Dir.glob(File.join(@tmp, 'db/migrate/*.rb')).first
    load @migration_path
    ActiveRecord::Migration.verbose = false
  end

  after do
    FileUtils.remove_entry(@tmp)
    Object.send(:remove_const, :CreateInboundRequestLogs) if defined?(CreateInboundRequestLogs)
  end

  def run_migration(config)
    ActiveRecord::Base.establish_connection(config)
    migration = CreateInboundRequestLogs.new
    migration.migrate(:up)

    connection = ActiveRecord::Base.connection
    assert connection.table_exists?(:inbound_request_logs)

    json_column = connection.columns(:inbound_request_logs).find { |c| c.name == 'request_headers' }
    if connection.adapter_name == 'PostgreSQL'
      _(json_column.sql_type).must_equal 'jsonb'
    else
      _(json_column.sql_type).must_equal 'json'
    end

    index_names = connection.indexes(:inbound_request_logs).map(&:name)
    _(index_names).must_include 'index_inbound_request_logs_on_failed_requests'
    _(index_names).must_include 'index_inbound_request_logs_on_response_body_gin' if connection.adapter_name == 'PostgreSQL'

    migration.migrate(:down)
    assert_not connection.table_exists?(:inbound_request_logs)
  end

  it 'generates a migration that runs on SQLite' do
    run_migration(adapter: 'sqlite3', database: ':memory:')
  end

  it 'generates a migration that runs on PostgreSQL' do
    run_migration(adapter: 'postgresql', database: 'inbound_test', username: 'postgres', password: 'postgres', host: 'localhost')
  end
end
