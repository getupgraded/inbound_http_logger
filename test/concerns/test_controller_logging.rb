# frozen_string_literal: true

require 'test_helper'

class ControllerLoggingModuleMethodsTest < InboundHTTPLoggerTestCase
  def setup
    super
    # Clear thread-local data before each test
    Thread.current[:inbound_http_logger_metadata] = nil
    Thread.current[:inbound_http_logger_loggable] = nil
    InboundHTTPLogger.enable!
  end

  def test_can_set_and_get_metadata
    metadata = { test: 'value' }
    InboundHTTPLogger.set_metadata(metadata)
    assert_equal metadata, Thread.current[:inbound_http_logger_metadata]
  end

  def test_can_set_and_get_loggable
    object = Object.new
    InboundHTTPLogger.set_loggable(object)
    assert_equal object, Thread.current[:inbound_http_logger_loggable]
  end
end

class ControllerLoggingSetupTest < InboundHTTPLoggerTestCase
  def setup
    super
    # Clear thread-local data before each test
    Thread.current[:inbound_http_logger_metadata] = nil
    Thread.current[:inbound_http_logger_loggable] = nil
    InboundHTTPLogger.enable!
    @mock_controller = create_mock_controller
  end

  def test_sets_basic_metadata
    @mock_controller.send(:setup_inbound_logging)

    metadata = Thread.current[:inbound_http_logger_metadata]
    refute_nil metadata
    assert_equal 'test', metadata[:controller]
    assert_equal 'index', metadata[:action]
    assert_equal 'html', metadata[:format]
    assert_equal 'test-session-id', metadata[:session_id]
    assert_equal 'test-request-id', metadata[:request_id]
  end

  def test_works_with_basic_metadata_when_no_callback_is_set
    # Default mock_controller doesn't have any callback
    @mock_controller.send(:setup_inbound_logging)

    metadata = Thread.current[:inbound_http_logger_metadata]
    # Basic metadata should still be present
    assert_equal 'test', metadata[:controller]
    assert_equal 'index', metadata[:action]
    assert_equal 'html', metadata[:format]
  end

  def test_works_without_any_callback_set
    # Default mock_controller doesn't have any callback
    @mock_controller.send(:setup_inbound_logging)

    metadata = Thread.current[:inbound_http_logger_metadata]
    assert_nil metadata[:resource_id]
    assert_nil metadata[:organization_id]
    # But basic metadata should still be present
    assert_equal 'test', metadata[:controller]
    assert_equal 'index', metadata[:action]
  end

  private

    def create_mock_controller
      controller = Object.new

      # Mock basic controller methods
      controller.define_singleton_method(:controller_name) { 'test' }
      controller.define_singleton_method(:action_name) { 'index' }

      # Mock request object
      request = Object.new
      format_obj = Object.new
      format_obj.define_singleton_method(:to_s) { 'html' }
      request.define_singleton_method(:format) { format_obj }
      request.define_singleton_method(:request_id) { 'test-request-id' }
      controller.define_singleton_method(:request) { request }

      # Mock session object
      session = Object.new
      session.define_singleton_method(:id) { 'test-session-id' }
      controller.define_singleton_method(:session) { session }

      # Mock respond_to? method
      controller.define_singleton_method(:respond_to?) do |method_name|
        case method_name
        when :current_user, :current_resource, :current_organization
          false # Default to not having these methods
        else
          true
        end
      end

      # Mock the class method for context callback
      controller.define_singleton_method(:class) do
        mock_class = Object.new
        mock_class.define_singleton_method(:inbound_logging_context_callback) { nil }
        mock_class.define_singleton_method(:inbound_logging_context) do |callback|
          mock_class.define_singleton_method(:inbound_logging_context_callback) { callback }
        end
        mock_class
      end

      # Include the concern methods
      controller.extend(InboundHTTPLogger::Concerns::ControllerLogging)

      controller
    end
end

class ControllerLoggingLogRequestsTest < InboundHTTPLoggerTestCase
  def setup
    super
    @controller_base_class = Class.new do
      # Mock Rails controller methods
      def self.after_action(*args, **kwargs)
        # No-op for testing
      end

      def self.skip_after_action(*args, **kwargs)
        # No-op for testing
      end
    end

    @mock_controller_class = Class.new(@controller_base_class) do
      include InboundHTTPLogger::Concerns::ControllerLogging
    end
  end

  def test_raises_error_when_both_only_and_except_are_specified
    assert_raises(ArgumentError) do
      @mock_controller_class.log_requests(only: [:show], except: [:index])
    end
  end

  def test_accepts_only_parameter
    assert_nothing_raised do
      @mock_controller_class.log_requests(only: %i[show index])
    end
  end

  def test_accepts_except_parameter
    assert_nothing_raised do
      @mock_controller_class.log_requests(except: %i[internal debug])
    end
  end

  def test_accepts_context_parameter_with_only
    assert_nothing_raised do
      @mock_controller_class.log_requests(only: [:show], context: :set_context)
    end
  end

  def test_accepts_context_parameter_with_except
    assert_nothing_raised do
      @mock_controller_class.log_requests(except: [:internal], context: ->(log) { log.metadata[:test] = 'value' })
    end
  end

  def test_accepts_no_parameters_for_default_behavior
    assert_nothing_raised do
      @mock_controller_class.log_requests
    end
  end
end

class ControllerLoggingInheritanceTest < InboundHTTPLoggerTestCase
  def setup
    super
    @controller_base_class = Class.new do
      # Mock Rails controller methods
      def self.after_action(*args, **kwargs)
        # No-op for testing
      end

      def self.skip_after_action(*args, **kwargs)
        # No-op for testing
      end
    end

    @base_controller_class = Class.new(@controller_base_class) do
      include InboundHTTPLogger::Concerns::ControllerLogging
    end
  end

  def test_allows_subclass_to_skip_actions_when_base_class_uses_log_requests_only
    # Base class logs only specific actions
    @base_controller_class.log_requests only: %i[show index]

    # Subclass skips one of those actions
    assert_nothing_raised do
      subclass = Class.new(@base_controller_class) do
        skip_inbound_logging :show
      end
      refute_nil subclass
    end
  end

  def test_allows_subclass_to_use_except_when_base_class_uses_default_logging
    # Base class uses default logging (all actions)
    @base_controller_class.log_requests

    # Subclass excludes specific actions
    assert_nothing_raised do
      subclass = Class.new(@base_controller_class) do
        log_requests except: %i[internal debug]
      end
      refute_nil subclass
    end
  end

  def test_allows_subclass_to_override_with_only_when_base_class_uses_except
    # Base class excludes some actions
    @base_controller_class.log_requests except: [:internal]

    # Subclass uses only specific actions
    assert_nothing_raised do
      subclass = Class.new(@base_controller_class) do
        log_requests only: [:show]
      end
      refute_nil subclass
    end
  end

  def test_allows_multiple_inheritance_levels
    # Base class
    @base_controller_class.log_requests only: %i[show index create]

    # Middle class
    middle_class = Class.new(@base_controller_class) do
      skip_inbound_logging :create
    end

    # Final subclass
    assert_nothing_raised do
      subclass = Class.new(middle_class) do
        log_requests except: [:index]
      end
      refute_nil subclass
    end
  end
end

class ControllerLoggingContextCallbacksTest < InboundHTTPLoggerTestCase
  def setup
    super
    @controller_base_class = Class.new do
      # Mock Rails controller methods
      def self.after_action(*args, **kwargs)
        # No-op for testing
      end

      def self.skip_after_action(*args, **kwargs)
        # No-op for testing
      end
    end

    @controller_class_with_callback = Class.new(@controller_base_class) do
      include InboundHTTPLogger::Concerns::ControllerLogging

      attr_accessor :controller_name, :action_name, :request, :session, :test_resource

      def initialize
        @controller_name = 'test'
        @action_name = 'index'
        @request = create_mock_request
        @session = create_mock_session
        @test_resource = Object.new.tap { |r| r.define_singleton_method(:id) { 999 } }
        super
      end

      # Test method callback
      def set_log_context(log)
        log.loggable = @test_resource
        log.metadata[:custom_field] = 'custom_value'
      end

      private

        def create_mock_request
          request = Object.new
          format_obj = Object.new
          format_obj.define_singleton_method(:to_s) { 'html' }
          request.define_singleton_method(:format) { format_obj }
          request.define_singleton_method(:request_id) { 'test-request-id' }
          request
        end

        def create_mock_session
          session = Object.new
          session.define_singleton_method(:id) { 'test-session-id' }
          session
        end
    end
  end

  def test_executes_method_based_context_callback
    @controller_class_with_callback.inbound_logging_context(:set_log_context)
    controller = @controller_class_with_callback.new

    controller.send(:setup_inbound_logging)

    metadata = Thread.current[:inbound_http_logger_metadata]
    loggable = Thread.current[:inbound_http_logger_loggable]

    assert_equal 'custom_value', metadata[:custom_field]
    assert_equal 999, loggable.id
  end

  def test_executes_lambda_based_context_callback
    test_lambda = lambda { |log|
      log.metadata[:lambda_field] = 'lambda_value'
      log.loggable = 'test_loggable'
    }

    @controller_class_with_callback.inbound_logging_context(test_lambda)
    controller = @controller_class_with_callback.new

    controller.send(:setup_inbound_logging)

    metadata = Thread.current[:inbound_http_logger_metadata]
    loggable = Thread.current[:inbound_http_logger_loggable]

    assert_equal 'lambda_value', metadata[:lambda_field]
    assert_equal 'test_loggable', loggable
  end

  def test_handles_missing_callback_method_gracefully
    @controller_class_with_callback.inbound_logging_context(:nonexistent_method)
    controller = @controller_class_with_callback.new

    assert_nothing_raised do
      controller.send(:setup_inbound_logging)
    end

    metadata = Thread.current[:inbound_http_logger_metadata]
    refute_nil metadata
    assert_equal 'test', metadata[:controller]
  end

  def test_works_without_any_context_callback
    # Don't set any callback
    controller = @controller_class_with_callback.new

    controller.send(:setup_inbound_logging)

    metadata = Thread.current[:inbound_http_logger_metadata]
    refute_nil metadata
    assert_equal 'test', metadata[:controller]
  end
end

class ControllerLoggingInheritanceChainCallbackTest < InboundHTTPLoggerTestCase
  def setup
    super
    # Clear any existing callbacks before each test
    InboundHTTPLogger::Concerns::ControllerLogging.send(:class_variable_set, :@@context_callbacks, {})

    @controller_base_class = Class.new do
      # Mock Rails controller methods
      def self.after_action(*args, **kwargs)
        # No-op for testing
      end

      def self.skip_after_action(*args, **kwargs)
        # No-op for testing
      end
    end

    @base_controller_class = Class.new(@controller_base_class) do
      include InboundHTTPLogger::Concerns::ControllerLogging
    end
  end

  def test_finds_callback_in_current_class_when_set
    # Set callback on the class itself
    @base_controller_class.inbound_logging_context(:test_callback)

    callback = @base_controller_class.inbound_logging_context_callback
    assert_equal :test_callback, callback
  end

  def test_returns_nil_when_no_callback_is_set_anywhere_in_chain
    # No callback set anywhere
    callback = @base_controller_class.inbound_logging_context_callback
    assert_nil callback
  end

  def test_finds_callback_in_parent_class_when_not_set_in_current_class
    # Set callback on base class
    @base_controller_class.inbound_logging_context(:parent_callback)

    # Create subclass without its own callback
    subclass = Class.new(@base_controller_class)

    # Should find the parent's callback
    callback = subclass.inbound_logging_context_callback
    assert_equal :parent_callback, callback
  end

  def test_prefers_current_class_callback_over_parent_class_callback
    # Set callback on base class
    @base_controller_class.inbound_logging_context(:parent_callback)

    # Create subclass with its own callback
    subclass = Class.new(@base_controller_class) do
      inbound_logging_context(:child_callback)
    end

    # Should find the child's callback, not the parent's
    callback = subclass.inbound_logging_context_callback
    assert_equal :child_callback, callback
  end

  def test_walks_up_multiple_inheritance_levels
    # Set callback on base class
    @base_controller_class.inbound_logging_context(:grandparent_callback)

    # Create middle class without callback
    middle_class = Class.new(@base_controller_class)

    # Create final subclass without callback
    subclass = Class.new(middle_class)

    # Should find the grandparent's callback
    callback = subclass.inbound_logging_context_callback
    assert_equal :grandparent_callback, callback
  end

  def test_stops_at_object_class_and_returns_nil_if_no_callback_found
    # Create a deep inheritance chain with no callbacks
    level1 = Class.new(@base_controller_class)
    level2 = Class.new(level1)
    level3 = Class.new(level2)

    # Should return nil since no callback is set anywhere
    callback = level3.inbound_logging_context_callback
    assert_nil callback
  end

  def test_works_with_lambda_callbacks_in_inheritance_chain
    test_lambda = ->(log) { log.metadata[:inherited] = true }

    # Set lambda callback on base class
    @base_controller_class.inbound_logging_context(test_lambda)

    # Create subclass
    subclass = Class.new(@base_controller_class)

    # Should find the parent's lambda callback
    callback = subclass.inbound_logging_context_callback
    assert_equal test_lambda, callback
  end

  def test_finds_first_callback_when_multiple_levels_have_callbacks
    # Set callback on base class
    @base_controller_class.inbound_logging_context(:grandparent_callback)

    # Create middle class with callback
    middle_class = Class.new(@base_controller_class) do
      inbound_logging_context(:parent_callback)
    end

    # Create final subclass without callback
    subclass = Class.new(middle_class)

    # Should find the immediate parent's callback, not the grandparent's
    callback = subclass.inbound_logging_context_callback
    assert_equal :parent_callback, callback
  end
end
