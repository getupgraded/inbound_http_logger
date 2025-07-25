# InboundHTTPLogger

[![CI](https://github.com/getupgraded/inbound_http_logger/actions/workflows/test.yml/badge.svg)](https://github.com/getupgraded/inbound_http_logger/actions/workflows/test.yml)

A production-safe gem for comprehensive inbound HTTP request logging in Rails applications. Uses Rack middleware for automatic request capture with configurable filtering and controller-level integration.

## Features

- **Automatic Rails integration**: Rack middleware with Railtie for seamless setup
- **Comprehensive logging**: Request/response headers, bodies, timing, IP addresses, user agents
- **Security-first**: Automatic filtering of sensitive headers and body data
- **Performance-optimized**: Early-exit logic, content type filtering, body size limits
- **Production-safe**: Failsafe error handling ensures requests never fail due to logging
- **Controller integration**: Concerns for metadata, loggable associations, and custom events
- **Configurable exclusions**: URL patterns, content types, controllers, and actions
- **Rich querying**: Search, filtering, analytics, and cleanup utilities
- **SQLite logging**: Optional separate SQLite database for local logging and testing
- **Test utilities**: Persistent test logging with request counting and analysis tools

## Requirements

This gem supports Ruby 3.2 or newer and Rails 7.2 or newer. The CI matrix also
tests against Ruby 3.3 and Rails 8.1 to ensure compatibility.

## Installation

Add to your Gemfile:

```ruby
gem 'inbound_http_logger', git: "https://github.com/getupgraded/inbound_http_logger.git" # this is not a published gem yet
```

Run the generator to create the database migration:

```bash
rails generate inbound_http_logger:migration
rails db:migrate
```

## Configuration

### Basic Setup

```ruby
# config/initializers/inbound_http_logger.rb
InboundHTTPLogger.configure do |config|
  config.enabled = true

  # Optional: Add custom path exclusions
  config.excluded_paths << %r{/internal-api}

  # Optional: Add custom sensitive headers
  config.sensitive_headers << 'x-custom-token'

  # Optional: Set max body size (default: 10KB)
  config.max_body_size = 50_000

  # Optional: Enable debug logging
  config.debug_logging = Rails.env.development?

  # Optional: Enable secondary database logging
  config.configure_secondary_database('sqlite3:///log/requests.sqlite3')
end
```

### Environment Variable Control

You can completely disable the gem (preventing middleware registration, controller concerns, and all functionality) using environment variables:

```bash
# Disable the gem completely (no middleware, no controller concerns, no logging)
ENABLE_INBOUND_HTTP_LOGGER=false

# Enable the gem (default behavior)
ENABLE_INBOUND_HTTP_LOGGER=true
# or simply omit the variable (defaults to enabled)
```

**Supported disable values:** `false`, `FALSE`, `0`, `no`, `off`
**All other values (including missing/empty) enable the gem**

This is particularly useful for:
- **Heroku deployments**: Change environment variables to disable logging without code changes
- **Performance testing**: Quickly disable HTTP logging overhead
- **Debugging**: Isolate issues by disabling HTTP request logging
- **Independent control**: Disable inbound logging while keeping outbound logging active

**Note:** Environment variable changes require an application restart to take effect.

### Environment-specific Configuration

```ruby
# config/environments/production.rb
InboundHTTPLogger.configure do |config|
  config.enabled = true
  config.debug_logging = false
end

# config/environments/test.rb
InboundHTTPLogger.configure do |config|
  config.enabled = false # Disable in tests for performance
end

# config/environments/development.rb
InboundHTTPLogger.configure do |config|
  config.enabled = true
  config.debug_logging = true
end
```

## Usage

Once configured, the gem automatically logs all inbound HTTP requests to your **main Rails database** using ActiveRecord:

```ruby
# All requests to your Rails app will be automatically logged to your main database
# GET /users -> logged to main Rails database
# POST /orders -> logged to main Rails database
# PUT /products/123 -> logged to main Rails database

# Query logs using ActiveRecord
logs = InboundHTTPLogger::Models::InboundRequestLog.recent
error_logs = InboundHTTPLogger::Models::InboundRequestLog.failed
```

## Additional Database Logging

The gem supports **optional** logging to an additional database alongside the main Rails database. This provides **dual logging** - your main database gets all logs, plus an additional specialized database. This is particularly useful for:

- **Local development**: Keep a separate log file for debugging
- **Testing**: Persistent test logs that don't interfere with your main database
- **Analytics**: Separate storage for request analytics and monitoring
- **Performance**: Use optimized databases for logging (e.g., PostgreSQL with JSONB)

### Supported Database Types

- **SQLite** - Perfect for local development and testing
- **PostgreSQL** - High-performance with JSONB support and GIN indexes
- **MySQL** - (Future support planned)

### Basic Configuration

```ruby
# config/initializers/inbound_http_logger.rb
InboundHTTPLogger.configure do |config|
  # Enable logging to your main Rails database (default behavior)
  config.enabled = true

  # That's it! Logs will be stored in your main Rails database using ActiveRecord
  # No additional configuration needed for basic usage
end
```

### Additional Database Configuration (Optional)

If you want to **also** log to a separate database (in addition to your main Rails database):

```ruby
# config/initializers/inbound_http_logger.rb
InboundHTTPLogger.configure do |config|
  config.enabled = true  # Main Rails database logging

  # OPTIONAL: Also log to an additional database

  # SQLite (simple file-based logging)
  config.configure_secondary_database('sqlite3:///log/requests.sqlite3')

  # PostgreSQL (high-performance with JSONB)
  config.configure_secondary_database('postgresql://user:pass@host/logs_db')

  # Or use environment variable
  config.configure_secondary_database(ENV['LOGGING_DATABASE_URL'])
end
```

### Programmatic Control

```ruby
# Main database logging (always uses your Rails database)
InboundHTTPLogger.enable!   # Enable main database logging
InboundHTTPLogger.disable!  # Disable all logging
InboundHTTPLogger.enabled?  # Check if logging is enabled

# Additional database logging (optional, in addition to main database)
InboundHTTPLogger.enable_secondary_logging!('sqlite3:///log/requests.sqlite3')
InboundHTTPLogger.enable_secondary_logging!('postgresql://user:pass@host/logs')
InboundHTTPLogger.disable_secondary_logging!
InboundHTTPLogger.secondary_logging_enabled?
```

## Test Utilities

The gem provides a dedicated test namespace with powerful utilities for testing HTTP request logging.

### Importing Test Utilities

**Important**: Test utilities are not automatically loaded with the main gem. You must explicitly require them in your test environment:

```ruby
# In your test files or test_helper.rb
require 'inbound_http_logger/test'
```

This design keeps production environments lean by only loading test utilities when explicitly needed.

### Test Configuration

```ruby
# Configure test logging with separate database
InboundHTTPLogger::Test.configure(
  database_url: 'sqlite3:///tmp/test_requests.sqlite3',
  adapter: :sqlite
)

# Or use PostgreSQL for tests
InboundHTTPLogger::Test.configure(
  database_url: 'postgresql://localhost/test_logs',
  adapter: :postgresql
)

# Enable test logging
InboundHTTPLogger::Test.enable!

# Disable test logging
InboundHTTPLogger::Test.disable!
```

### Test Utilities API

```ruby
# Count all logged requests during tests
total_requests = InboundHTTPLogger::Test.logs_count

# Count requests by status code
successful_requests = InboundHTTPLogger::Test.logs_with_status(200)
error_requests = InboundHTTPLogger::Test.logs_with_status(500)

# Count requests for specific paths
api_requests = InboundHTTPLogger::Test.logs_for_path('/api/')
user_requests = InboundHTTPLogger::Test.logs_for_path('/users')

# Get all logged requests
all_logs = InboundHTTPLogger::Test.all_logs

# Get logs matching specific criteria
failed_requests = InboundHTTPLogger::Test.logs_matching(status: 500)
api_posts = InboundHTTPLogger::Test.logs_matching(method: 'POST', path: '/api')

# Analyze request patterns
analysis = InboundHTTPLogger::Test.analyze
# Returns: { total_requests: 100, success_rate: 95.0, error_rate: 5.0, ... }

# Clear test logs manually (if needed)
InboundHTTPLogger::Test.clear_logs!

# Reset test environment
InboundHTTPLogger::Test.reset!
```

### Test Framework Integration

#### Important: Configuration Isolation in Tests

**WARNING**: Never modify the global configuration directly in tests without proper restoration, as this can cause test pollution and unpredictable failures in parallel test execution.

#### Recommended Test Setup Patterns

**Option 1: Thread-Safe Configuration (Recommended)**
```ruby
describe "My Feature" do
  include InboundHTTPLogger::Test::Helpers

  it "logs requests with thread-safe configuration" do
    # Uses thread-safe configuration with in-memory SQLite for true isolation
    InboundHTTPLogger.with_configuration(
      enabled: true,
      secondary_database_url: 'sqlite3::memory:',
      secondary_database_adapter: :sqlite,
      clear_excluded_paths: true,
      clear_excluded_content_types: true
    ) do
      # Configuration changes only affect current thread
      # Safe for parallel test execution
      get '/some/path'
      assert_request_logged('GET', '/some/path')
    end
    # Configuration automatically restored after block
  end
end
```

**Option 2: Manual Backup/Restore**
```ruby
describe "My Feature" do
  include InboundHTTPLogger::Test::Helpers

  before do
    @config_backup = backup_inbound_http_logger_configuration
    setup_inbound_http_logger_test

    InboundHTTPLogger.configure do |config|
      config.enabled = true
      config.excluded_paths.clear
      config.excluded_content_types.clear
    end
  end

  after do
    teardown_inbound_http_logger_test
    restore_inbound_http_logger_configuration(@config_backup)
  end
end
```

**Option 3: Legacy Configuration Block (Not Recommended)**
```ruby
describe "My Feature" do
  include InboundHTTPLogger::Test::Helpers

  it "logs requests with configuration block" do
    # Legacy approach - use Option 1 instead for better thread safety
    with_inbound_http_logger_configuration(
      enabled: true,
      clear_excluded_paths: true,
      clear_excluded_content_types: true
    ) do
      get '/some/path'
      assert_request_logged('GET', '/some/path')
    end
    # Configuration automatically restored after block
  end
end
```

**Option 4: Temporary Configuration Changes (Legacy)**
```ruby
describe "My Feature" do
  include InboundHTTPLogger::Test::Helpers

  it "logs requests with custom configuration" do
    with_inbound_http_logger_configuration(
      enabled: true,
      clear_excluded_paths: true,
      clear_excluded_content_types: true
    ) do
      # Your test code here
      get '/some/path'
      assert_request_logged('GET', '/some/path')
    end
    # Configuration automatically restored after block
  end
end
```

#### System Test Setup (Capybara/Playwright)

For system tests that make real HTTP requests through a browser, you need to enable both main logging and test utilities:

```ruby
# test/application_system_test_case.rb
require 'inbound_http_logger/test'  # Required for test utilities

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include InboundHTTPLogger::Test::Helpers

  setup do
    # Use thread-safe configuration for system tests
    @inbound_http_logger_backup = InboundHTTPLogger.global_configuration.backup
    InboundHTTPLogger.configure do |config|
      config.enabled = true
      config.secondary_database_url = 'sqlite3:///tmp/system_test_requests.sqlite3'
      config.secondary_database_adapter = :sqlite
    end
  end

  teardown do
    InboundHTTPLogger.global_configuration.restore(@inbound_http_logger_backup) if @inbound_http_logger_backup
  end
end

# In your system tests
class CheckoutSystemTest < ApplicationSystemTestCase
  test "logs checkout flow requests" do
    visit '/checkout'
    fill_in 'Email', with: 'user@example.com'
    click_on 'Continue'

    # Assert that HTTP requests were logged during the flow
    assert_request_count(2)  # Expected number of requests
    assert_request_logged('GET', '/checkout')
    assert_request_logged('POST', '/checkout/email')
  end
end
```

#### Minitest Setup (Unit/Integration Tests)

```ruby
# test/test_helper.rb
require 'inbound_http_logger/test'  # Required for test utilities

class ActiveSupport::TestCase
  include InboundHTTPLogger::Test::Helpers

  setup do
    @inbound_http_logger_backup = InboundHTTPLogger.global_configuration.backup
    InboundHTTPLogger.configure do |config|
      config.enabled = true
      config.secondary_database_url = 'sqlite3:///tmp/test_requests.sqlite3'
      config.secondary_database_adapter = :sqlite
    end
  end

  teardown do
    InboundHTTPLogger.global_configuration.restore(@inbound_http_logger_backup) if @inbound_http_logger_backup
  end
end

# In your tests
class APITest < ActiveSupport::TestCase
  test "logs API requests correctly" do
    get '/api/users'
    post '/api/users', params: { name: 'John' }

    # Use helper methods
    assert_request_logged('GET', '/api/users', status: 200)
    assert_request_logged('POST', '/api/users', status: 201)
    assert_request_count(2)

    # Or use direct API
    assert_equal 2, InboundHTTPLogger::Test.logs_count
    assert_equal 1, InboundHTTPLogger::Test.logs_with_status(200)
    assert_equal 1, InboundHTTPLogger::Test.logs_with_status(201)
  end

  test "analyzes request patterns" do
    get '/api/users'    # 200
    get '/api/missing'  # 404

    analysis = InboundHTTPLogger::Test.analyze
    assert_equal 2, analysis[:total_requests]
    assert_equal 50.0, analysis[:success_rate]
    assert_equal 50.0, analysis[:error_rate]
  end
end
```

#### RSpec Setup

```ruby
# spec/rails_helper.rb
require 'inbound_http_logger/test'  # Required for test utilities

RSpec.configure do |config|
  config.include InboundHTTPLogger::Test::Helpers

  config.before(:each) do
    setup_inbound_http_logger_test
  end

  config.after(:each) do
    teardown_inbound_http_logger_test
  end
end

# In your specs
RSpec.describe "API logging" do
  it "logs requests correctly" do
    get '/api/users'

    expect(InboundHTTPLogger::Test.logs_count).to eq(1)
    assert_request_logged('GET', '/api/users')
    assert_success_rate(100.0)
  end
end
```



### ActiveRecord Integration

- **Native ActiveRecord**: All database operations use ActiveRecord models and migrations
- **Rails-native**: Integrates seamlessly with your existing Rails database setup
- **Default connection**: Uses your main Rails database connection by default
- **Multiple database support**: Additional databases use Rails' `connects_to` for proper connection pooling
- **Migration support**: Includes Rails generator for creating the required database table

### Database Features

- **Automatic table creation**: Database tables are created automatically via ActiveRecord migrations
- **Thread-safe**: Safe for concurrent access with proper ActiveRecord connection pooling
- **Graceful degradation**: If database gems are not available, logging is disabled with warnings
- **Dual logging**: When additional database is configured, logs go to both main and additional databases
- **Independent operation**: Additional database logging works independently of main database
- **Database-specific optimizations**:
  - PostgreSQL uses JSONB columns with GIN indexes for fast JSON queries
  - SQLite uses JSON columns with appropriate indexes
  - Automatic adapter detection and optimization

## Features Overview

The gem provides a clean, modern API for HTTP request logging with multiple database support:

#### Secondary Database Configuration

```ruby
# Configure secondary database logging
config.configure_secondary_database('sqlite3:///log/requests.sqlite3')

# Or use PostgreSQL for better performance
config.configure_secondary_database('postgresql://user:pass@host/logs_db')

# Programmatic control
InboundHTTPLogger.enable_secondary_logging!('sqlite3:///log/requests.sqlite3')
InboundHTTPLogger.disable_secondary_logging!
```

#### Test Setup

```ruby
# First, require the test utilities
require 'inbound_http_logger/test'

# Configure test logging
InboundHTTPLogger::Test.configure(database_url: 'sqlite3:///tmp/test.sqlite3')
InboundHTTPLogger::Test.enable!
count = InboundHTTPLogger::Test.logs_count
```

### Key Benefits

- **High performance**: PostgreSQL with JSONB support and GIN indexes
- **Flexible storage**: Support for SQLite, PostgreSQL, and future database adapters
- **Comprehensive testing**: Dedicated test utilities with framework integration
- **Clean architecture**: Proper namespace separation and modern API design
- **Production ready**: Uses Rails' multiple database support and connection pooling

### Controller Integration

Include the concern in your controllers for enhanced logging:

```ruby
class ApplicationController < ActionController::Base
  include InboundHTTPLogger::Concerns::ControllerLogging
end

class UsersController < ApplicationController
  # Configure logging with Rails-standard filter options
  log_requests only: [:show, :index]  # Log only specific actions
  # OR
  log_requests except: [:internal_status, :debug]  # Log all except specific actions

  # Skip logging for specific actions (alternative approach)
  skip_inbound_logging :internal_status

  def show
    user = User.find(params[:id])

    # Associate this request with a model
    set_inbound_log_loggable(user)

    # Add custom metadata
    add_inbound_log_metadata(user_type: user.role, plan: user.plan)

    # Log custom events
    log_inbound_event('user_profile_viewed', user_id: user.id)

    render json: user
  end
end
```

### Custom Context Callbacks

The gem provides flexible ways to add custom context to your logs using callbacks:

#### Method-based Callbacks

```ruby
class UsersController < ApplicationController
  # Set context for specific actions using a method
  log_requests only: [:show, :index], context: :set_log_context

  private

  def set_log_context(log)
    log.loggable = @user
    log.metadata[:user_role] = @user.role
    log.metadata[:plan] = @user.plan
  end
end
```

#### Lambda-based Callbacks

```ruby
class OrdersController < ApplicationController
  # Set context using a lambda for specific actions
  log_requests only: [:show, :update], context: ->(log) {
    log.loggable = @order
    log.metadata[:order_status] = @order.status
    log.metadata[:retailer_id] = @order.retailer_id
  }
end
```

#### Global Context for All Actions

```ruby
class ApplicationController < ActionController::Base
  include InboundHTTPLogger::Concerns::ControllerLogging

  # Set context for all actions in this controller
  inbound_logging_context :set_global_context

  private

  def set_global_context(log)
    log.metadata[:tenant_id] = current_tenant&.id if respond_to?(:current_tenant)
    log.metadata[:user_id] = current_user&.id if respond_to?(:current_user)
  end
end
```

#### Log Context Object

The callback receives a `log` object with these properties:

- `log.loggable` - Set the main object associated with this request (captures full object data)
- `log.metadata` - Hash for adding custom metadata fields (for fast querying)

**Best Practice**: Use `log.loggable` for the main object and only add essential IDs to `log.metadata` for database queries. The loggable object contains all the detailed information you need.

### Real-World Example

Here's how you might use this in a Rails e-commerce application:

```ruby
class OrdersController < ApplicationController
  # Capture order context for specific actions
  log_requests only: [:show, :update], context: :set_order_context

  def show
    @order = Order.find(params[:id])
    render json: @order
  end

  private

  def set_order_context(log)
    if @order
      # Setting loggable captures the full object for detailed logging
      log.loggable = @order
      # Add essential metadata for fast querying (using safe navigation)
      log.metadata[:order_id] = @order.id
      log.metadata[:customer_id] = @order&.customer_id
      log.metadata[:status] = @order&.status
    end
  end
end

class ApplicationController < ActionController::Base
  include InboundHTTPLogger::Concerns::ControllerLogging

  # Global context for all controllers
  inbound_logging_context :set_global_context

  private

  def set_global_context(log)
    # Add tenant/organization context
    if current_organization
      log.metadata[:organization_id] = current_organization.id
      log.metadata[:organization_name] = current_organization.name
    end

    # Add user context
    if current_user
      log.metadata[:user_id] = current_user.id
      log.metadata[:user_role] = current_user.role
    end
  end
end
```

### Querying Logs

```ruby
# Find all logs
logs = InboundHTTPLogger::Models::InboundRequestLog.all

# Find by status code
error_logs = InboundHTTPLogger::Models::InboundRequestLog.failed
success_logs = InboundHTTPLogger::Models::InboundRequestLog.successful

# Find slow requests (>1 second)
slow_logs = InboundHTTPLogger::Models::InboundRequestLog.slow(1000)

# Search functionality
logs = InboundHTTPLogger::Models::InboundRequestLog.search(
  q: 'users',           # Search in URL and body
  status: [200, 201],   # Filter by status codes
  method: 'POST',       # Filter by HTTP method
  ip_address: '127.0.0.1',
  start_date: '2024-01-01',
  end_date: '2024-01-31'
)

# Clean up old logs (older than 90 days)
InboundHTTPLogger::Models::InboundRequestLog.cleanup(90)
```

### Rake Tasks

```bash
# Analyze request patterns and performance
rails inbound_http_logger:analyze

# Clean up old logs
rails inbound_http_logger:cleanup[30]  # Delete logs older than 30 days

# Show recent failed requests
rails inbound_http_logger:failed

# Show slow requests
rails inbound_http_logger:slow[500]    # Show requests slower than 500ms
```

## Security Features

### Automatic Header Filtering

The following headers are automatically filtered:
- `authorization`, `cookie`, `set-cookie`
- `x-api-key`, `x-auth-token`, `x-access-token`
- `x-csrf-token`, `x-session-id`

### Automatic Body Filtering

JSON request/response bodies are parsed and the following keys are filtered:
- `password`, `secret`, `token`, `key`
- `auth`, `credential`, `private`
- `ssn`, `credit_card`, `cvv`, `pin`

### Content Type Exclusions

The following content types are excluded by default:
- HTML, CSS, JavaScript
- Images, videos, audio, fonts
- Static assets

### Path Exclusions

The following URL patterns are excluded by default:
- Assets (`/assets/`, `/packs/`)
- Health checks (`/health`, `/ping`)
- Static files (`.css`, `.js`, `.ico`, images, fonts)

## Performance Considerations

- **Early exit**: When disabled, adds virtually no overhead
- **Path filtering**: Excluded paths are filtered before processing
- **Content type filtering**: Static assets and HTML are skipped
- **Body size limits**: Large request/response bodies are truncated
- **Failsafe design**: Logging errors never break HTTP requests
- **JSONB optimization**: PostgreSQL users benefit from native JSON storage and querying

### PostgreSQL JSONB Optimization

When using PostgreSQL, the gem automatically uses JSONB columns for storing JSON request and response bodies, providing several benefits:

- **Native JSON storage**: JSON responses are stored as parsed objects, not strings
- **Efficient querying**: Use PostgreSQL's JSON operators for fast searches
- **Reduced memory usage**: No application-level JSON parsing overhead
- **Better indexing**: GIN indexes on JSONB columns for optimal query performance

#### JSONB Query Examples

```ruby
# Search for requests containing specific JSON data
logs = InboundHTTPLogger::Models::InboundRequestLog.with_response_containing('status', 'success')

# Use PostgreSQL JSON operators directly
logs = InboundHTTPLogger::Models::InboundRequestLog.where("response_body @> ?", { status: 'error' }.to_json)

# Search within nested JSON structures
logs = InboundHTTPLogger::Models::InboundRequestLog.where("response_body -> 'user' ->> 'role' = ?", 'admin')

# Use GIN indexes for fast text search within JSON
logs = InboundHTTPLogger::Models::InboundRequestLog.where("response_body::text ILIKE ?", '%error%')
```

#### Database Compatibility

- **PostgreSQL**: Uses JSONB columns with GIN indexes for optimal performance
- **SQLite/MySQL**: Uses standard JSON columns with text-based searching
- **Migration**: Automatically detects database adapter and uses appropriate column types

## Rails-Style Controller Hooks

The gem provides Rails-idiomatic controller hooks that follow the same conventions as `before_action`, `after_action`, etc.

### log_requests Method

The primary method for configuring request logging:

```ruby
class UsersController < ApplicationController
  # Log only specific actions
  log_requests only: [:show, :index]

  # Log all actions except specific ones
  log_requests except: [:internal, :debug]

  # Add context to logged requests
  log_requests only: [:show], context: :set_user_context
  log_requests except: [:internal], context: ->(log) { log.metadata[:tenant] = current_tenant.id }

  # Default behavior (log all actions) - no parameters needed
  log_requests
end
```

## Controller-Level Control

```ruby
class AdminController < ApplicationController
  # Exclude entire controller
  InboundHTTPLogger.configuration.exclude_controller('admin')
end

class UsersController < ApplicationController
  # Exclude specific actions
  InboundHTTPLogger.configuration.exclude_action('users', 'internal')

  # Or use controller methods
  skip_inbound_logging :internal, :debug
  log_requests only: [:show, :create] # Only log these actions
  # OR
  log_requests except: [:internal, :debug] # Log all except these actions

  # Provide context for logging by implementing these methods
  def current_resource
    @user # The main resource being operated on
  end

  def current_organization
    current_user&.organization # For multi-tenant applications
  end
end
```

## Thread Safety

The gem is fully thread-safe and supports parallel testing frameworks. It uses thread-local variables for request-specific metadata and loggable associations, ensuring that concurrent requests and tests don't interfere with each other.

### Parallel Testing Support

For parallel testing frameworks, use the thread-safe configuration override:

```ruby
# Thread-safe configuration changes for testing
InboundHTTPLogger.with_configuration(enabled: true, debug_logging: true) do
  # Configuration changes only affect current thread
  # Other test threads are unaffected
  # Automatically restored when block exits
end
```

### Configuration Backup and Restore

The Configuration class provides built-in backup and restore methods:

```ruby
# Manual backup and restore for complex scenarios
backup = InboundHTTPLogger.global_configuration.backup
begin
  # Make complex configuration changes
  InboundHTTPLogger.configure do |config|
    config.enabled = true
    config.excluded_paths.clear
  end
  # Perform operations
ensure
  InboundHTTPLogger.global_configuration.restore(backup)
end
```

## Error Handling

All logging operations are wrapped in failsafe error handling. If logging fails for any reason, the original HTTP request continues normally and the error is logged to Rails.logger.

## API Reference

### Main Module Methods

```ruby
# Main Database Configuration (uses your Rails database)
InboundHTTPLogger.configure { |config| ... }
InboundHTTPLogger.configuration
InboundHTTPLogger.enable!   # Enable logging to main Rails database
InboundHTTPLogger.disable!  # Disable all logging
InboundHTTPLogger.enabled?  # Check if main database logging is enabled

# Thread-Safe Configuration (for testing)
InboundHTTPLogger.with_configuration(**overrides) { ... }  # Thread-safe temporary config
InboundHTTPLogger.global_configuration                     # Access global config directly
InboundHTTPLogger.reset_configuration!                     # Reset to defaults (testing only)

# Additional Database Logging (optional, in addition to main database)
InboundHTTPLogger.enable_secondary_logging!(url, adapter: :sqlite)
InboundHTTPLogger.disable_secondary_logging!
InboundHTTPLogger.secondary_logging_enabled?
```

### Test Module Methods

```ruby
# Configuration
InboundHTTPLogger::Test.configure(database_url:, adapter:)
InboundHTTPLogger::Test.enable!
InboundHTTPLogger::Test.disable!
InboundHTTPLogger::Test.enabled?

# Logging
InboundHTTPLogger::Test.log_request(request, body, status, headers, response, duration)

# Querying
InboundHTTPLogger::Test.logs_count
InboundHTTPLogger::Test.logs_with_status(status)
InboundHTTPLogger::Test.logs_for_path(path)
InboundHTTPLogger::Test.all_logs
InboundHTTPLogger::Test.logs_matching(criteria)
InboundHTTPLogger::Test.analyze

# Management
InboundHTTPLogger::Test.clear_logs!
InboundHTTPLogger::Test.reset!
```

### Test Helpers

```ruby
# Include in test classes
include InboundHTTPLogger::Test::Helpers

# Configuration Management
backup_inbound_http_logger_configuration
restore_inbound_http_logger_configuration(backup)
with_inbound_http_logger_configuration(**options) { ... }
with_thread_safe_configuration(**overrides) { ... }  # Recommended for parallel testing

# Thread-Safe Configuration (Recommended)
InboundHTTPLogger.with_configuration(**overrides) { ... }

# Test Setup (Basic)
setup_inbound_http_logger_test(database_url:, adapter:)
teardown_inbound_http_logger_test

# Assertions
assert_request_logged(method, path, status:)
assert_request_count(expected_count, criteria = {})
assert_success_rate(expected_rate, tolerance: 0.1)
```

### Configuration Management Best Practices

#### ❌ DON'T: Modify Global Configuration Directly
```ruby
# This causes test pollution!
before do
  InboundHTTPLogger.configure do |config|
    config.excluded_paths.clear  # Permanently modifies global state
    config.excluded_content_types.clear
  end
end
```

#### ✅ DO: Use Thread-Safe Configuration
```ruby
# This safely isolates configuration changes per thread
it "logs requests without exclusions" do
  InboundHTTPLogger.with_configuration(
    enabled: true,
    secondary_database_url: 'sqlite3::memory:',
    secondary_database_adapter: :sqlite,
    clear_excluded_paths: true,
    clear_excluded_content_types: true
  ) do
    get '/assets/app.css'
    assert_request_logged('GET', '/assets/app.css')
  end
  # Configuration automatically restored
end
```

#### ✅ DO: Use Temporary Configuration Changes
```ruby
it "logs requests without exclusions" do
  with_inbound_http_logger_configuration(
    clear_excluded_paths: true,
    clear_excluded_content_types: true
  ) do
    get '/assets/app.css'
    assert_request_logged('GET', '/assets/app.css')
  end
  # Configuration automatically restored
end
```

#### Configuration Reset (Advanced)
```ruby
# WARNING: Only use in controlled environments
# This loses all initializer customizations
InboundHTTPLogger.reset_configuration!

# Create fresh configuration with defaults
fresh_config = InboundHTTPLogger.create_fresh_configuration
```

### Model Methods

```ruby
# Querying
InboundHTTPLogger::Models::InboundRequestLog.search(params)
InboundHTTPLogger::Models::InboundRequestLog.recent
InboundHTTPLogger::Models::InboundRequestLog.with_status(status)
InboundHTTPLogger::Models::InboundRequestLog.with_method(method)
InboundHTTPLogger::Models::InboundRequestLog.successful
InboundHTTPLogger::Models::InboundRequestLog.failed
InboundHTTPLogger::Models::InboundRequestLog.slow(threshold_ms)

# PostgreSQL JSONB methods
InboundHTTPLogger::Models::InboundRequestLog.with_response_containing(key, value)
InboundHTTPLogger::Models::InboundRequestLog.with_request_containing(key, value)

# Management
InboundHTTPLogger::Models::InboundRequestLog.cleanup(older_than_days)
```

### Configuration Options

```ruby
config.enabled = true                    # Enable/disable logging
config.debug_logging = false            # Enable debug output
config.max_body_size = 10_000           # Max body size to log (bytes)
config.log_level = :info                # Log level

# Secondary database
config.configure_secondary_database(url, adapter: :sqlite)
config.secondary_database_url = 'sqlite3:///path'
config.secondary_database_adapter = :postgresql

# Exclusions
config.excluded_paths << /pattern/
config.excluded_content_types << 'text/html'
config.sensitive_headers << 'x-custom-token'
config.sensitive_body_keys << 'secret_field'
config.exclude_controller('controller_name')
config.exclude_action('controller_name', 'action_name')
```

## Development

### Running Tests

```bash
# Install dependencies
bundle install

# Run gem tests
bundle exec rake test

# Run system tests (from parent Rails app)
cd ../..
rails test test/system/

# Run specific system test with HTTP logging
rails test test/system/affirm/accepted_test.rb
```

### Git Hooks

Use the provided `pre-commit` hook to run RuboCop before each commit:

```bash
# we use RVM inhouse, so we assume that. Adjust as you see fit (or skip hooks, the same checks happen in CI anyway)
git config core.hooksPath githooks
```

### System Test Requirements

For system tests to work with HTTP logging, ensure:

1. **Main logging enabled**: `InboundHTTPLogger.enable!` in system test setup
2. **Test utilities configured**: `setup_inbound_http_logger_test` with database URL
3. **Middleware active**: The Rails middleware stack includes the logging middleware
4. **Database setup**: Test database can be SQLite or PostgreSQL

### Debugging System Tests

If system tests aren't logging requests:

```ruby
# Check if logging is enabled
puts "Main logging: #{InboundHTTPLogger.enabled?}"
puts "Test logging: #{InboundHTTPLogger::Test.enabled?}"

# Check middleware is active
middleware_names = Rails.application.middleware.map(&:name)
puts "Middleware active: #{middleware_names.include?('InboundHTTPLogger::Middleware::LoggingMiddleware')}"

# Check request counts
puts "Main DB requests: #{InboundHTTPLogger::Models::InboundRequestLog.count}"
puts "Test DB requests: #{InboundHTTPLogger::Test.logs_count}"
```

## Future Enhancements

- Performance monitoring and metrics
- Log rotation and archival strategies
- Look into writing to SQLite on disk and using https://litestream.io/ to aggregate the logs 
- Redis adapter for high-throughput logging
- MySQL adapter (upon request)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
