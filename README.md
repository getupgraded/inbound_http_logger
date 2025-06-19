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
  # Skip logging for specific actions
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
  log_inbound_only :show, :create # Only log these actions
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
