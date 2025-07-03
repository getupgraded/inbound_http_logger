# frozen_string_literal: true

namespace :inbound_http_logger do
  desc 'Analyze inbound HTTP request logs'
  task analyze: :environment do
    puts "=== InboundHTTPLogger Analysis ==="
    puts

    model = InboundHTTPLogger::Models::InboundRequestLog

    # Total counts
    total_logs = model.count
    puts "Total inbound request logs: #{total_logs}"

    if total_logs > 0
      # Status code breakdown
      puts "\n=== Status Code Breakdown ==="
      status_counts = model.group(:status_code).count.sort
      status_counts.each do |status, count|
        percentage = (count.to_f / total_logs * 100).round(1)
        status_text = Rack::Utils::HTTP_STATUS_CODES[status] || 'Unknown'
        puts "  #{status} (#{status_text}): #{count} (#{percentage}%)"
      end

      # HTTP method breakdown
      puts "\n=== HTTP Method Breakdown ==="
      method_counts = model.group(:http_method).count.sort
      method_counts.each do |method, count|
        percentage = (count.to_f / total_logs * 100).round(1)
        puts "  #{method}: #{count} (#{percentage}%)"
      end

      # Most frequent paths
      puts "\n=== Most Frequent Paths (Top 10) ==="
      path_counts = model.group(:url).count.sort_by { |_, count| -count }.first(10)
      path_counts.each do |path, count|
        percentage = (count.to_f / total_logs * 100).round(1)
        puts "  #{path}: #{count} (#{percentage}%)"
      end

      # Performance metrics
      puts "\n=== Performance Metrics ==="
      avg_duration = model.average(:duration_ms)
      max_duration = model.maximum(:duration_ms)
      slow_requests = model.slow(1000).count

      puts "  Average response time: #{avg_duration&.round(2)}ms"
      puts "  Maximum response time: #{max_duration&.round(2)}ms"
      puts "  Slow requests (>1s): #{slow_requests} (#{(slow_requests.to_f / total_logs * 100).round(1)}%)"

      # Recent activity
      puts "\n=== Recent Activity (Last 10) ==="
      recent_logs = model.recent.limit(10)
      recent_logs.each do |log|
        puts "  #{log.created_at.strftime('%Y-%m-%d %H:%M:%S')} - #{log.http_method} #{log.url} - #{log.status_code} (#{log.formatted_duration})"
      end

      # Error analysis
      failed_count = model.failed.count
      if failed_count > 0
        puts "\n=== Error Analysis ==="
        puts "  Total failed requests: #{failed_count} (#{(failed_count.to_f / total_logs * 100).round(1)}%)"

        error_paths = model.failed.group(:url).count.sort_by { |_, count| -count }.first(5)
        puts "  Top error paths:"
        error_paths.each do |path, count|
          puts "    #{path}: #{count} errors"
        end
      end
    else
      puts "No logs found. Make sure InboundHTTPLogger is enabled and receiving requests."
    end

    puts "\n=== Configuration Status ==="
    puts "  Enabled: #{InboundHTTPLogger.enabled?}"
    puts "  Debug logging: #{InboundHTTPLogger.configuration.debug_logging}"
    puts "  Max body size: #{InboundHTTPLogger.configuration.max_body_size} bytes"
    puts "  Excluded paths: #{InboundHTTPLogger.configuration.excluded_paths.size} patterns"
    puts "  Excluded controllers: #{InboundHTTPLogger.configuration.excluded_controllers.size} controllers"
  end

  desc 'Clean up old inbound request logs'
  task :cleanup, [:days] => :environment do |_, args|
    days = (args[:days] || 90).to_i

    puts "Cleaning up inbound request logs older than #{days} days..."

    deleted_count = InboundHTTPLogger::Models::InboundRequestLog.cleanup(days)

    puts "Deleted #{deleted_count} old log entries."
  end

  desc 'Show recent failed requests'
  task failed: :environment do
    puts "=== Recent Failed Requests ==="

    failed_logs = InboundHTTPLogger::Models::InboundRequestLog.failed.recent.limit(20)

    if failed_logs.any?
      failed_logs.each do |log|
        puts "\n#{log.created_at.strftime('%Y-%m-%d %H:%M:%S')} - #{log.status_code}"
        puts "  #{log.http_method} #{log.url}"
        puts "  IP: #{log.ip_address}"
        puts "  Duration: #{log.formatted_duration}"
        puts "  User-Agent: #{log.user_agent}" if log.user_agent.present?
      end
    else
      puts "No failed requests found."
    end
  end

  desc 'Show slow requests'
  task :slow, [:threshold] => :environment do |_, args|
    threshold = (args[:threshold] || 1000).to_i

    puts "=== Slow Requests (>#{threshold}ms) ==="

    slow_logs = InboundHTTPLogger::Models::InboundRequestLog.slow(threshold).recent.limit(20)

    if slow_logs.any?
      slow_logs.each do |log|
        puts "\n#{log.created_at.strftime('%Y-%m-%d %H:%M:%S')} - #{log.formatted_duration}"
        puts "  #{log.http_method} #{log.url}"
        puts "  Status: #{log.status_code}"
        puts "  IP: #{log.ip_address}"
      end
    else
      puts "No slow requests found."
    end
  end
end
