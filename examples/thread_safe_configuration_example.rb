#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating thread-safe configuration for parallel testing
require_relative '../lib/inbound_http_logger'

puts "=== Thread-Safe Configuration Example ==="
puts

# Set up initial configuration
InboundHttpLogger.configure do |config|
  config.enabled = false
  config.debug_logging = false
  config.max_body_size = 10_000
end

puts "Initial configuration:"
puts "  enabled: #{InboundHttpLogger.configuration.enabled?}"
puts "  debug_logging: #{InboundHttpLogger.configuration.debug_logging}"
puts "  max_body_size: #{InboundHttpLogger.configuration.max_body_size}"
puts

# Demonstrate thread-safe configuration overrides
puts "=== Thread-Safe Configuration Overrides ==="
puts

results = []
threads = 3.times.map do |i|
  Thread.new do
    # Each thread gets its own configuration context
    InboundHttpLogger.with_configuration(
      enabled: i.even?,
      debug_logging: i.odd?,
      max_body_size: 1000 * (i + 1)
    ) do
      sleep 0.1 # Simulate some work and allow potential interference

      results[i] = {
        thread_id: i,
        enabled: InboundHttpLogger.configuration.enabled?,
        debug_logging: InboundHttpLogger.configuration.debug_logging,
        max_body_size: InboundHttpLogger.configuration.max_body_size
      }

      puts "Thread #{i} configuration:"
      puts "  enabled: #{results[i][:enabled]}"
      puts "  debug_logging: #{results[i][:debug_logging]}"
      puts "  max_body_size: #{results[i][:max_body_size]}"
    end
  end
end

threads.each(&:join)
puts

# Verify configuration was restored
puts "Configuration after threads completed:"
puts "  enabled: #{InboundHttpLogger.configuration.enabled?}"
puts "  debug_logging: #{InboundHttpLogger.configuration.debug_logging}"
puts "  max_body_size: #{InboundHttpLogger.configuration.max_body_size}"
puts

# Demonstrate nested configuration overrides
puts "=== Nested Configuration Overrides ==="
puts

InboundHttpLogger.with_configuration(enabled: true) do
  puts "Outer override - enabled: #{InboundHttpLogger.configuration.enabled?}"

  InboundHttpLogger.with_configuration(debug_logging: true) do
    puts "Inner override - enabled: #{InboundHttpLogger.configuration.enabled?}, debug_logging: #{InboundHttpLogger.configuration.debug_logging}"
  end

  puts "Back to outer - enabled: #{InboundHttpLogger.configuration.enabled?}, debug_logging: #{InboundHttpLogger.configuration.debug_logging}"
end

puts "Back to original - enabled: #{InboundHttpLogger.configuration.enabled?}, debug_logging: #{InboundHttpLogger.configuration.debug_logging}"
puts

# Demonstrate dependency injection
puts "=== Dependency Injection Example ==="
puts

require 'stringio'
custom_log_output = StringIO.new

InboundHttpLogger.with_configuration(
  logger_factory: -> { Logger.new(custom_log_output) }
) do
  logger = InboundHttpLogger.configuration.logger
  logger.info("This goes to the custom logger")
  puts "Custom logger output: #{custom_log_output.string.strip}"
end

puts
puts "=== Configuration Backup/Restore Example ==="
puts

# Demonstrate the backup/restore functionality
original_enabled = InboundHttpLogger.configuration.enabled?
puts "Original enabled: #{original_enabled}"

# Change configuration
InboundHttpLogger.configure { |config| config.enabled = !original_enabled }
puts "After change: #{InboundHttpLogger.configuration.enabled?}"

# Create backup and restore
backup = InboundHttpLogger.global_configuration.backup
InboundHttpLogger.global_configuration.restore(backup)
puts "After restore: #{InboundHttpLogger.configuration.enabled?}"

puts
puts "=== Example Complete ==="
puts "All configuration changes were isolated and properly restored!"
puts "The simplified approach uses:"
puts "  - Thread-local configuration overrides for testing"
puts "  - Built-in backup/restore methods on Configuration class"
puts "  - No complex mutex or delegation patterns"
puts "  - Clean encapsulation within the Configuration class"
