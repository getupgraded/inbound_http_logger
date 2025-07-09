# frozen_string_literal: true

require 'minitest/autorun'
require 'active_record'
require 'rails/generators'
require 'rails/generators/active_record'
require 'inbound_http_logger/generators/migration_generator'
require 'tmpdir'
require 'fileutils'

class MigrationGeneratorTest < InboundHTTPLoggerTestCase
  def setup
    @tmp = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@tmp, 'db/migrate'))
    InboundHTTPLogger::Generators::MigrationGenerator.start([], destination_root: @tmp)
    @migration_path = Dir.glob(File.join(@tmp, 'db/migrate/*.rb')).first
    load @migration_path
    ActiveRecord::Migration.verbose = false
  end

  def teardown
    FileUtils.remove_entry(@tmp)
    Object.send(:remove_const, :CreateInboundRequestLogs) if defined?(CreateInboundRequestLogs)
  end

  def run_migration(config)
    ActiveRecord::Base.establish_connection(config)

    # Ensure clean state - drop table if it exists from previous test runs
    connection = ActiveRecord::Base.connection
    connection.drop_table(:inbound_request_logs) if connection.table_exists?(:inbound_request_logs)

    migration = CreateInboundRequestLogs.new
    migration.migrate(:up)

    connection = ActiveRecord::Base.connection
    assert connection.table_exists?(:inbound_request_logs)

    json_column = connection.columns(:inbound_request_logs).find { |c| c.name == 'request_headers' }
    if connection.adapter_name == 'PostgreSQL'
      assert_equal 'jsonb', json_column.sql_type
    else
      assert_equal 'json', json_column.sql_type
    end

    index_names = connection.indexes(:inbound_request_logs).map(&:name)
    assert_includes index_names, 'index_inbound_request_logs_on_failed_requests'
    assert_includes index_names, 'index_inbound_request_logs_on_response_body_gin' if connection.adapter_name == 'PostgreSQL'

    migration.migrate(:down)
    refute connection.table_exists?(:inbound_request_logs)
  end

  def test_generates_a_migration_that_runs_on_sqlite
    run_migration(adapter: 'sqlite3', database: ':memory:')
  end

  def test_generates_a_migration_that_runs_on_postgresql
    skip 'PostgreSQL test database not available' unless postgresql_test_database_available?
    run_migration(adapter: 'postgresql', database: 'inbound_test', username: 'postgres', password: 'postgres', host: 'localhost')
  end

  private

    def postgresql_test_database_available?
      require 'pg'
      # Try to connect to the specific test database
      PG.connect(host: 'localhost', port: 5432, dbname: 'inbound_test', user: 'postgres', password: 'postgres').close
      true
    rescue LoadError, PG::Error, StandardError
      false
    end
end
