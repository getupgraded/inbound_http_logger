# Changelog

## 0.0.4

* remove unnecessary duration_seconds column from database
* add quick enable/disable via environmen variable

## 0.0.3

* Database adapter architecture for better maintainability and flexibility.
* Added support for alternate database for SQLite logging.
* Added support for test mode for SQLite logging.
* Reduce model indices and fields.
* Rename gem to use HTTP (not Http) in the name.
* Better threading/parallel run support in tests.

## 0.0.2

* Added support for callbacks in parent classes.
* Use JSONB in PostgreSQL.

## 0.0.1

* Initial release with:

  - Rails integration: Rack middleware with Railtie and migration generators for seamless setup
  - Controller integration: Concerns for metadata, loggable associations, and custom events
  - Comprehensive logging: Request/response headers, bodies, timing, IP addresses, user agents
  - Automatic filtering of sensitive headers and body data
  - Performance: Early-exit logic, content type filtering, body size limits
  - Production-safety: Failsafe error handling ensures requests never fail due to logging
  - Configurable exclusions: URL patterns, content types, controllers, and actions
  - Rich querying: Search, filtering, analytics, and cleanup utilities
