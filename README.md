# InboundHttpLogger

[![CI](https://github.com/getupgraded/inbound_http_logger/actions/workflows/test.yml/badge.svg)](https://github.com/getupgraded/inbound_http_logger/actions/workflows/inbound-http-logger-ci.yml)

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
InboundHttpLogger.configure do |config|
  config.enabled = true

  # Optional: Add custom path exclusions
  config.excluded_paths << %r{/internal-api}

  # Optional: Add custom sensitive headers
  config.sensitive_headers << 'x-custom-token'

  # Optional: Set max body size (default: 10KB)
  config.max_body_size = 50_000

  # Optional: Enable debug logging
  config.debug_logging = Rails.env.development?
end
```

### Environment-specific Configuration

```ruby
# config/environments/production.rb
InboundHttpLogger.configure do |config|
  config.enabled = true
  config.debug_logging = false
end

# config/environments/test.rb
InboundHttpLogger.configure do |config|
  config.enabled = false # Disable in tests for performance
end

# config/environments/development.rb
InboundHttpLogger.configure do |config|
  config.enabled = true
  config.debug_logging = true
end
```

## Usage

Once configured, the gem automatically logs all inbound HTTP requests via Rack middleware:

```ruby
# All requests to your Rails app will be automatically logged
# GET /users -> logged
# POST /orders -> logged
# PUT /products/123 -> logged
```

### Controller Integration

Include the concern in your controllers for enhanced logging:

```ruby
class ApplicationController < ActionController::Base
  include InboundHttpLogger::Concerns::ControllerLogging
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
  include InboundHttpLogger::Concerns::ControllerLogging

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
  include InboundHttpLogger::Concerns::ControllerLogging

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
```

### Querying Logs

```ruby
# Find all logs
logs = InboundHttpLogger::Models::InboundRequestLog.all

# Find by status code
error_logs = InboundHttpLogger::Models::InboundRequestLog.failed
success_logs = InboundHttpLogger::Models::InboundRequestLog.successful

# Find slow requests (>1 second)
slow_logs = InboundHttpLogger::Models::InboundRequestLog.slow(1000)

# Search functionality
logs = InboundHttpLogger::Models::InboundRequestLog.search(
  q: 'users',           # Search in URL and body
  status: [200, 201],   # Filter by status codes
  method: 'POST',       # Filter by HTTP method
  ip_address: '127.0.0.1',
  start_date: '2024-01-01',
  end_date: '2024-01-31'
)

# Clean up old logs (older than 90 days)
InboundHttpLogger::Models::InboundRequestLog.cleanup(90)
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
logs = InboundHttpLogger::Models::InboundRequestLog.with_response_containing('status', 'success')

# Use PostgreSQL JSON operators directly
logs = InboundHttpLogger::Models::InboundRequestLog.where("response_body @> ?", { status: 'error' }.to_json)

# Search within nested JSON structures
logs = InboundHttpLogger::Models::InboundRequestLog.where("response_body -> 'user' ->> 'role' = ?", 'admin')

# Use GIN indexes for fast text search within JSON
logs = InboundHttpLogger::Models::InboundRequestLog.where("response_body::text ILIKE ?", '%error%')
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
  InboundHttpLogger.configuration.exclude_controller('admin')
end

class UsersController < ApplicationController
  # Exclude specific actions
  InboundHttpLogger.configuration.exclude_action('users', 'internal')

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

The gem is fully thread-safe and uses thread-local variables for request-specific metadata and loggable associations.

## Error Handling

All logging operations are wrapped in failsafe error handling. If logging fails for any reason, the original HTTP request continues normally and the error is logged to Rails.logger.

## Development

```bash
bundle install
bundle exec rake test
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
