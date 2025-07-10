# frozen_string_literal: true

module InboundHTTPLogger
  # Shared default configuration constants to avoid duplication
  # between Configuration class and test helpers
  module Defaults
    # Default maximum body size (10KB)
    MAX_BODY_SIZE = 10_000

    # Default excluded paths
    EXCLUDED_PATHS = [
      %r{^/assets/},
      %r{^/packs/},
      %r{^/health$},
      %r{^/ping$},
      %r{^/favicon\.ico$},
      %r{^/robots\.txt$},
      %r{^/sitemap\.xml$},
      /\.css$/,
      /\.js$/,
      /\.map$/,
      /\.ico$/,
      /\.png$/,
      /\.jpg$/,
      /\.jpeg$/,
      /\.gif$/,
      /\.svg$/,
      /\.woff$/,
      /\.woff2$/,
      /\.ttf$/,
      /\.eot$/
    ].freeze

    # Default excluded content types
    EXCLUDED_CONTENT_TYPES = [
      'text/html',
      'text/css',
      'text/javascript',
      'application/javascript',
      'application/x-javascript',
      'image/png',
      'image/jpeg',
      'image/gif',
      'image/svg+xml',
      'image/webp',
      'image/x-icon',
      'video/mp4',
      'video/webm',
      'audio/mpeg',
      'audio/wav',
      'font/woff',
      'font/woff2',
      'application/font-woff',
      'application/font-woff2'
    ].freeze

    # Default sensitive headers to filter
    SENSITIVE_HEADERS = %w[
      authorization
      cookie
      set-cookie
      x-api-key
      x-auth-token
      x-access-token
      bearer
      x-csrf-token
      x-session-id
    ].freeze

    # Default sensitive body keys to filter
    SENSITIVE_BODY_KEYS = %w[
      password
      secret
      token
      key
      auth
      credential
      private
      ssn
      social_security_number
      credit_card
      card_number
      cvv
      pin
    ].freeze
  end
end
