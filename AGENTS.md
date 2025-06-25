# AI Agent Contributor Guidelines

This document provides essential guidance for AI agents contributing to the `inbound_http_logger` gem. It constrains the range of possible approaches and ensures consistency with established patterns.

## Core Architecture Principles

### 1. Modular Design Pattern
The gem follows a strict modular architecture:

```
lib/inbound_http_logger/
├── configuration.rb           # Centralized configuration
├── models/                    # ActiveRecord models with inheritance
├── database_adapters/         # Database-specific implementations
├── middleware/                # Rack middleware
├── concerns/                  # Rails controller concerns
├── generators/                # Rails generators for migrations
├── test.rb                    # Isolated test utilities
└── railtie.rb                # Rails integration
```

**Rule**: Always place new functionality in the appropriate module. Never mix concerns across modules.

## Technology Stack and Dependencies

### 1. Testing Framework: Minitest
The gem uses **Minitest** with standard `Test::Unit` syntax (not RSpec or minitest/spec):

```ruby
class TestDatabaseAdapters < Minitest::Test
  def setup
    # Setup code
  end

  def test_sqlite_adapter_creates_model_class
    assert_equal expected, actual
    assert_includes collection, item
    refute_nil object
  end
end
```

**Key Points**:
- **Use `assert_equal`, `assert_includes`, `refute_nil`** - Standard Minitest assertions
- **Do NOT use `_(value).must_equal expected`** - That's minitest/spec syntax
- **Do NOT use RSpec syntax** - No `expect().to eq()` or `describe/it` blocks
- **Use `setup` and `teardown` methods** - Not `before` and `after`

**Rule**: Always use standard Minitest Test::Unit syntax. This ensures consistency and avoids confusion between different testing DSLs.

### 2. Database Support
**Primary**: SQLite3 (for development, testing, and simple deployments)
**Secondary**: PostgreSQL (for production with advanced features)

```ruby
# Required gems
gem 'sqlite3', '~> 1.4'
gem 'pg', '~> 1.1', optional: true
```

**Design Philosophy**:
- **SQLite as default**: Works out of the box, no setup required
- **PostgreSQL as upgrade path**: JSONB columns, GIN indexes, better performance
- **Graceful fallback**: PostgreSQL features disabled if `pg` gem not available

**Rule**: Always support both databases. Implement features in SQLite first, then add PostgreSQL optimizations.

### 3. Rails Integration
**Approach**: Railtie-based integration with optional middleware

```ruby
# Core dependencies
gem 'activerecord', '>= 7.0'
gem 'activesupport', '>= 7.0'
gem 'railties', '>= 7.0'
```

**Integration Points**:
- **Railtie**: Automatic middleware registration and configuration
- **Generators**: Rails-style migration generators
- **Concerns**: Controller mixins for manual logging
- **Middleware**: Rack middleware for automatic request logging

**Rule**: Follow Rails conventions. Use Railties for integration, generators for setup, concerns for controller features.

### 4. Code Quality and CI/CD
**Linting**: RuboCop with standard Ruby style guide
**CI/CD**: GitHub Actions with matrix testing
**Testing**: Multi-version testing (Ruby 3.2+, Rails 7.2+)

```yaml
# GitHub Actions matrix
strategy:
  matrix:
    ruby-version: ['3.2', '3.3', '3.4']
    rails-version: ['7.2.0', '8.0.1']
```

**Quality Gates**:
- **RuboCop**: Code style and quality checks
- **Test Coverage**: Comprehensive test suite with multiple databases
- **Multi-version**: Compatibility testing across Ruby and Rails versions

**Rule**: All code must pass RuboCop checks and comprehensive test suite before merging.

### 5. Key Dependencies and Their Purposes

| Gem | Purpose | Required |
|-----|---------|----------|
| `activerecord` | Database ORM and migrations | Yes |
| `activesupport` | Rails utilities and core extensions | Yes |
| `railties` | Rails integration and generators | Yes |
| `sqlite3` | Default database adapter | Yes |
| `pg` | PostgreSQL adapter for production | Optional |
| `rack` | HTTP middleware interface | Yes |
| `minitest` | Testing framework | Development |
| `rubocop` | Code quality and style checking | Development |

**Dependency Philosophy**:
- **Minimal required dependencies**: Only essential Rails components
- **Optional production dependencies**: PostgreSQL support when needed
- **Development dependencies**: Testing and quality tools
- **No unnecessary gems**: Avoid dependencies that add complexity

**Rule**: Keep dependencies minimal. Add new dependencies only when they provide significant value and cannot be easily implemented internally.

### 2. Database Adapter Pattern
The gem uses a base adapter pattern with database-specific implementations:

- `BaseAdapter` - Common interface and shared functionality
- `PostgresqlAdapter` - JSONB columns, GIN indexes, advanced queries
- `SqliteAdapter` - JSON columns, SQLite-specific optimizations

**Rule**: When adding database features, implement in the base adapter first, then override in specific adapters for optimizations.

### 3. Model Inheritance Pattern
Models follow a strict inheritance hierarchy:

```
BaseRequestLog (abstract)
└── InboundRequestLog (concrete, main database)
```

**Rule**: All logging models must inherit from `BaseRequestLog` and implement the `log_request` class method.

## Database Schema Conventions

### 1. Append-Only Logging Tables
```ruby
# ✅ Correct - Only created_at for append-only logs
t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

# ❌ Wrong - No updated_at for logging tables
t.timestamps # Don't use this for logging tables
```

**Rule**: Logging tables are append-only. Never add `updated_at` columns or use `t.timestamps`.

### 2. Database-Specific Column Types
```ruby
# Migration template pattern
if connection.adapter_name == 'PostgreSQL'
  t.jsonb :request_headers, default: {}
  t.jsonb :response_body
else
  t.json :request_headers, default: {}
  t.json :response_body
end
```

**Rule**: Always detect database adapter in migrations and use appropriate column types (JSONB for PostgreSQL, JSON for others).

### 3. Polymorphic Associations
```ruby
t.references :loggable, polymorphic: true, type: :bigint, index: true
```

**Rule**: Use polymorphic associations for linking logs to application models. Always use `bigint` type.

## Configuration System

### 1. Centralized Configuration
All configuration goes through `InboundHttpLogger::Configuration`:

```ruby
InboundHttpLogger.configure do |config|
  config.enabled = true
  config.max_body_size = 50_000
  config.excluded_paths << %r{/internal-api}
end
```

**Rule**: Never add configuration options outside the main configuration class.

### 2. Environment-Specific Defaults
```ruby
# Sensible defaults based on environment
@debug_logging = Rails.env.development?
@enabled = false # Explicit opt-in required
```

**Rule**: Configuration must have sensible defaults and be environment-aware.

## Error Handling Philosophy

### 1. Failsafe Operations
```ruby
begin
  log_request(...)
rescue StandardError => e
  # Log error but never break the main application
  logger.error("Error logging request: #{e.class}: #{e.message}")
  nil
end
```

**Rule**: Logging failures must NEVER break the main application. Always wrap in failsafe error handling.

### 2. Graceful Degradation
```ruby
def adapter_available?
  require 'pg'
  true
rescue LoadError
  logger.warn('pg gem not available. PostgreSQL logging disabled.')
  false
end
```

**Rule**: If optional dependencies are missing, disable features gracefully with appropriate warnings.

## Thread Safety Requirements

### 1. Thread-Safe Configuration System
The gem implements a simple thread-safe configuration system for parallel testing:

```ruby
# Thread-safe temporary configuration override
InboundHttpLogger.with_configuration(enabled: true, debug_logging: true) do
  # Configuration changes only affect current thread
  # Automatically restored when block exits
  # Safe for parallel testing
end
```

**Rule**: Use `with_configuration` for temporary configuration changes in tests. This creates a complete configuration copy for the current thread.

### 2. Thread-Local Storage
```ruby
Thread.current[:inbound_http_logger_metadata] = metadata
Thread.current[:inbound_http_logger_loggable] = object
```

**Rule**: Use thread-local variables for request-specific data. Always clear thread data after requests.

### 3. Configuration Backup and Restore
```ruby
# Configuration class handles its own serialization
backup = InboundHttpLogger.global_configuration.backup
# ... make changes ...
InboundHttpLogger.global_configuration.restore(backup)
```

**Rule**: The Configuration class encapsulates backup/restore logic. Use these methods instead of manually copying configuration attributes.

### 4. Dependency Injection for Rails Integration
```ruby
# Avoid direct Rails calls by injecting dependencies
InboundHttpLogger.configure do |config|
  config.logger_factory = -> { MyCustomLogger.new }
  config.cache_adapter = MyCustomCache.new
end
```

**Rule**: Use dependency injection instead of direct `Rails.application` calls to avoid tight coupling and improve testability.

### 6. Database Connection Management for Secondary Databases

The gem implements a careful approach to database connections that respects Rails' multi-database architecture:

```ruby
# ✅ Correct - Add configuration without establishing primary connection
ActiveRecord::Base.configurations.configurations << ActiveRecord::DatabaseConfigurations::HashConfig.new(
  env_name,
  connection_name.to_s,
  config
)

# ✅ Correct - Dynamic model classes with custom connection method
klass = Class.new(InboundHttpLogger::Models::InboundRequestLog) do
  @adapter_connection_name = adapter_connection_name

  def self.connection
    ActiveRecord::Base.connection_handler.retrieve_connection(@adapter_connection_name.to_s)
  end
end

# ❌ Wrong - Direct establish_connection interferes with Rails
klass.establish_connection(connection_name)

# ❌ Wrong - connects_to doesn't work with non-abstract classes
klass.connects_to database: { writing: connection_name }
```

**Critical Rules for Secondary Database Support**:

1. **Never use `establish_connection` on model classes** - This can interfere with Rails' primary database configuration and multi-database setups
2. **Add configurations to Rails but don't establish connections** - Let Rails manage connection establishment through its normal mechanisms
3. **Use custom connection methods for secondary databases** - Override the `connection` method to retrieve the correct connection from Rails' connection handler
4. **Inherit from main model classes** - Dynamic adapter model classes should inherit from the main model to get all instance methods like `formatted_call`

**Rationale**: Rails applications often use multiple databases (primary, read replicas, logging databases, etc.). The gem must not interfere with the main application's database configuration. By adding configurations without establishing connections, we let Rails handle connection pooling, failover, and multi-database routing properly.

**Rule**: Leverage Rails' connection pooling and multi-database support. Never manage database connections manually or interfere with the main application's database setup.

## Testing Patterns

### 1. Isolated Test Environment

The gem uses an in-memory SQLite database for testing, which provides excellent performance and isolation:

```ruby
# test/test_helper.rb - In-memory SQLite for main test suite
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

# lib/inbound_http_logger/test.rb - Separate test database for test utilities
module InboundHttpLogger::Test
  def configure(database_url: nil, adapter: :sqlite)
    # Uses separate SQLite file or in-memory database
    # Default: 'tmp/test_inbound_http_requests.sqlite3'
  end
end
```

**Benefits of In-Memory SQLite for Testing**:
- **Performance**: Extremely fast - no disk I/O overhead
- **Isolation**: Each test run starts with a clean database
- **No cleanup**: Database disappears when process ends
- **No temp file management**: No need to clean up test database files
- **Parallel testing**: Each process gets its own in-memory database

**Rule**: Use in-memory SQLite (`:memory:`) for the main test suite and separate SQLite files for test utilities. This provides optimal performance while maintaining proper isolation.

### 2. Parallel Testing Support
```ruby
# Thread-safe configuration for parallel tests
def test_with_custom_config
  InboundHttpLogger.with_configuration(enabled: true, debug_logging: true) do
    # This configuration is isolated to current thread
    # Other test threads are unaffected
    perform_test_actions
  end
  # Configuration automatically restored
end

# Using test helper for thread-safe configuration
def test_logging_behavior
  with_thread_safe_configuration(enabled: true, max_body_size: 5000) do
    # Test code here
  end
end
```

**Rule**: Use `with_configuration` or `with_thread_safe_configuration` for parallel testing. Never use global configuration mutations in multi-threaded test environments.

### 3. Test Framework Integration
```ruby
# Minitest helpers
def setup_inbound_http_logger_test
  InboundHttpLogger::Test.configure
  InboundHttpLogger::Test.enable!
end

# Thread-safe test setup
def setup_with_isolation
  setup_inbound_http_logger_test_with_isolation(enabled: true)
end
```

**Rule**: Provide framework-specific helpers for easy integration. Support both Minitest and RSpec patterns. Prefer isolation helpers for parallel testing.

## Package Management

### 1. Use Package Managers
```bash
# ✅ Correct
bundle add gem_name
npm install package_name

# ❌ Wrong - Never edit directly
# Editing Gemfile, package.json manually
```

**Rule**: Always use appropriate package managers (bundler, npm, etc.). Never manually edit package configuration files.

### 2. Dependency Management
```ruby
# Optional dependencies with graceful fallback
begin
  require 'pg'
rescue LoadError
  # Disable PostgreSQL features
end
```

**Rule**: Handle optional dependencies gracefully. Provide clear error messages when required dependencies are missing.

## Rails Integration Standards

### 1. Generator Conventions
```ruby
class MigrationGenerator < Rails::Generators::Base
  include ActiveRecord::Generators::Migration

  def create_migration_file
    migration_template 'template.rb.erb', 'db/migrate/migration.rb'
  end
end
```

**Rule**: Follow Rails generator conventions. Use proper migration templates with version detection.

### 2. Middleware Integration
```ruby
# Railtie integration
config.middleware.use InboundHttpLogger::Middleware::LoggingMiddleware
```

**Rule**: Integrate with Rails middleware stack properly. Respect middleware ordering.

## Performance Considerations

### 1. Database Optimizations
```ruby
# PostgreSQL-specific optimizations
t.index :response_body, using: :gin # For JSONB queries
t.index :url, using: :gin, opclass: :gin_trgm_ops # For text search
```

**Rule**: Implement database-specific optimizations in adapters. Use appropriate indexes for query patterns.

### 2. Body Size Limits
```ruby
config.max_body_size = 10_000 # 10KB default
```

**Rule**: Always respect configured size limits. Truncate large payloads to prevent memory issues.

## Security Guidelines

### 1. Sensitive Data Filtering
```ruby
config.sensitive_headers << 'authorization'
config.sensitive_body_keys << 'password'
```

**Rule**: Provide comprehensive sensitive data filtering. Default to secure configurations.

### 2. Configuration-Based Filtering Pattern
The gem uses a non-standard but justified pattern where filter methods are placed on the Configuration class rather than separate service objects:

```ruby
# Filter methods on configuration object
InboundHttpLogger.configuration.filter_headers(headers)
InboundHttpLogger.configuration.filter_sensitive_data(parsed_data)
```

**Rationale**:
- Filtering logic is entirely driven by configuration data (sensitive_headers, sensitive_body_keys, max_body_size)
- Encapsulates both filtering rules and their application in one place
- Ensures thread-safe access to configuration overrides
- Provides clean API without requiring additional objects

**Rule**: When behavior is entirely configuration-driven and tightly coupled to configuration data, placing methods on the configuration object is acceptable. Document the rationale clearly.

### 2. SQL Injection Prevention
```ruby
# ✅ Correct - Parameterized queries
where('status_code >= ?', 400)

# ❌ Wrong - String interpolation
where("status_code >= #{status}")
```

**Rule**: Always use parameterized queries. Never use string interpolation in SQL.

## Contribution Workflow

### 1. Conservative Approach
**Rule**: Ask for permission before:
- Committing or pushing code
- Installing dependencies
- Changing ticket status
- Merging branches
- Deploying code

### 2. Testing Requirements
```bash
# Always run tests after changes
bundle exec rake test
./bin/ci  # Run full CI suite locally
```

**Rule**: Always suggest writing/updating tests after code changes. Run the full test suite before proposing changes.

### 3. Documentation Standards
**Rule**: Update README.md and relevant documentation when adding features. Provide clear examples and configuration instructions.

## Common Anti-Patterns to Avoid

1. **❌ Direct package file editing** - Use package managers instead
2. **❌ Breaking error handling** - Logging errors must never break the app
3. **❌ Mixed concerns** - Keep modules focused and separated
4. **❌ Manual connection management** - Use Rails' connection pooling
5. **❌ Test pollution** - Always use isolated test configurations
6. **❌ Missing failsafes** - All external operations need error handling
7. **❌ Hardcoded configurations** - Use the centralized configuration system
8. **❌ Thread-unsafe code** - Use thread-local storage for request data
9. **❌ Global configuration mutations in tests** - Use `with_configuration` instead
10. **❌ Direct Rails.application calls** - Use dependency injection pattern
11. **❌ Mutable class variables (@@count)** - Use thread-safe alternatives
12. **❌ Global cache mutations without mutexes** - Protect shared state
13. **❌ Singleton state modifications** - Use thread-local or immutable patterns
14. **❌ Using `establish_connection` on secondary database models** - Interferes with Rails multi-database setup
15. **❌ Using `connects_to` with non-abstract model classes** - Causes "not allowed" errors
16. **❌ File-based test databases without cleanup** - Use in-memory SQLite for better performance

## Thread-Safe Configuration Examples

### Parallel Testing Pattern
```ruby
# Each test can run independently without affecting others
class MyTest < Minitest::Test
  def test_logging_with_custom_settings
    with_thread_safe_configuration(enabled: true, max_body_size: 5000) do
      # Test code here - configuration is isolated to this thread
      # Other parallel tests are unaffected
      perform_request_that_should_be_logged
      assert_request_logged
    end
    # Configuration automatically restored
  end
end
```

### Configuration Backup/Restore Pattern
```ruby
# Manual backup and restore for complex scenarios
backup = InboundHttpLogger.global_configuration.backup
begin
  # Make complex configuration changes
  InboundHttpLogger.configure do |config|
    config.enabled = true
    config.excluded_paths.clear
    config.excluded_paths << /custom_pattern/
  end

  # Perform operations
ensure
  InboundHttpLogger.global_configuration.restore(backup)
end
```

### Dependency Injection Pattern
```ruby
# Avoid direct Rails dependencies
InboundHttpLogger.configure do |config|
  config.logger_factory = -> { Rails.logger }
  config.cache_adapter = Rails.cache
end
```

## Summary

This gem prioritizes **reliability**, **performance**, **thread-safety**, and **Rails integration**. When in doubt:
1. Follow Rails conventions
2. Implement failsafe error handling
3. Use the established modular architecture
4. Use thread-safe configuration patterns for parallel testing
5. Implement dependency injection instead of direct Rails calls
6. Ask for guidance rather than making assumptions
7. Test thoroughly with isolated configurations

The goal is to provide robust HTTP request logging that never interferes with the main application while offering powerful features for debugging and monitoring in both single-threaded and multi-threaded environments.
