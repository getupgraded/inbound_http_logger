# frozen_string_literal: true

require 'test_helper'

describe InboundHttpLogger::Concerns::ControllerLogging do
  before do
    # Clear thread-local data before each test
    Thread.current[:inbound_http_logger_metadata] = nil
    Thread.current[:inbound_http_logger_loggable] = nil
    InboundHttpLogger.enable!
  end

  # Create a mock controller base class that provides Rails controller methods
  let(:controller_base_class) do
    Class.new do
      # Mock Rails controller methods
      def self.after_action(*args, **kwargs)
        # No-op for testing
      end

      def self.skip_after_action(*args, **kwargs)
        # No-op for testing
      end
    end
  end

  # Test the module methods directly without including in a controller
  describe 'module methods' do
    it 'can set and get metadata' do
      metadata = { test: 'value' }
      InboundHttpLogger.set_metadata(metadata)
      _(Thread.current[:inbound_http_logger_metadata]).must_equal metadata
    end

    it 'can set and get loggable' do
      object = Object.new
      InboundHttpLogger.set_loggable(object)
      _(Thread.current[:inbound_http_logger_loggable]).must_equal object
    end
  end

  # Test the setup_inbound_logging method by calling it directly
  describe 'setup_inbound_logging method' do
    let(:mock_controller) do
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
      controller.extend(InboundHttpLogger::Concerns::ControllerLogging)

      controller
    end

    it 'sets basic metadata' do
      mock_controller.send(:setup_inbound_logging)

      metadata = Thread.current[:inbound_http_logger_metadata]
      _(metadata).wont_be_nil
      _(metadata[:controller]).must_equal 'test'
      _(metadata[:action]).must_equal 'index'
      _(metadata[:format]).must_equal 'html'
      _(metadata[:session_id]).must_equal 'test-session-id'
      _(metadata[:request_id]).must_equal 'test-request-id'
    end

    it 'works with basic metadata when no callback is set' do
      # Default mock_controller doesn't have any callback
      mock_controller.send(:setup_inbound_logging)

      metadata = Thread.current[:inbound_http_logger_metadata]
      # Basic metadata should still be present
      _(metadata[:controller]).must_equal 'test'
      _(metadata[:action]).must_equal 'index'
      _(metadata[:format]).must_equal 'html'
    end

    it 'works without any callback set' do
      # Default mock_controller doesn't have any callback
      mock_controller.send(:setup_inbound_logging)

      metadata = Thread.current[:inbound_http_logger_metadata]
      _(metadata[:resource_id]).must_be_nil
      _(metadata[:organization_id]).must_be_nil
      # But basic metadata should still be present
      _(metadata[:controller]).must_equal 'test'
      _(metadata[:action]).must_equal 'index'
    end
  end

  describe 'log_requests method' do
    let(:mock_controller_class) do
      Class.new(controller_base_class) do
        include InboundHttpLogger::Concerns::ControllerLogging
      end
    end

    it 'raises error when both only and except are specified' do
      _(proc {
        mock_controller_class.log_requests(only: [:show], except: [:index])
      }).must_raise ArgumentError
    end

    it 'accepts only parameter' do
      # Should not raise an error
      mock_controller_class.log_requests(only: %i[show index])
    end

    it 'accepts except parameter' do
      # Should not raise an error
      mock_controller_class.log_requests(except: %i[internal debug])
    end

    it 'accepts context parameter with only' do
      # Should not raise an error
      mock_controller_class.log_requests(only: [:show], context: :set_context)
    end

    it 'accepts context parameter with except' do
      # Should not raise an error
      mock_controller_class.log_requests(except: [:internal], context: ->(log) { log.metadata[:test] = 'value' })
    end

    it 'accepts no parameters for default behavior' do
      # Should not raise an error
      mock_controller_class.log_requests
    end
  end

  describe 'inheritance behavior' do
    let(:base_controller_class) do
      Class.new(controller_base_class) do
        include InboundHttpLogger::Concerns::ControllerLogging
      end
    end

    it 'allows subclass to skip actions when base class uses log_requests only' do
      # Base class logs only specific actions
      base_controller_class.log_requests only: %i[show index]

      # Subclass skips one of those actions
      subclass = Class.new(base_controller_class) do
        skip_inbound_logging :show
      end

      # Should not raise an error
      _(subclass).wont_be_nil
    end

    it 'allows subclass to use except when base class uses default logging' do
      # Base class uses default logging (all actions)
      base_controller_class.log_requests

      # Subclass excludes specific actions
      subclass = Class.new(base_controller_class) do
        log_requests except: %i[internal debug]
      end

      # Should not raise an error
      _(subclass).wont_be_nil
    end

    it 'allows subclass to override with only when base class uses except' do
      # Base class excludes some actions
      base_controller_class.log_requests except: [:internal]

      # Subclass uses only specific actions
      subclass = Class.new(base_controller_class) do
        log_requests only: [:show]
      end

      # Should not raise an error
      _(subclass).wont_be_nil
    end

    it 'allows multiple inheritance levels' do
      # Base class
      base_controller_class.log_requests only: %i[show index create]

      # Middle class
      middle_class = Class.new(base_controller_class) do
        skip_inbound_logging :create
      end

      # Final subclass
      subclass = Class.new(middle_class) do
        log_requests except: [:index]
      end

      # Should not raise an error
      _(subclass).wont_be_nil
    end
  end

  describe 'context callbacks' do
    let(:controller_class_with_callback) do
      Class.new(controller_base_class) do
        include InboundHttpLogger::Concerns::ControllerLogging

        attr_accessor :controller_name, :action_name, :request, :session, :test_resource

        def initialize
          @controller_name = 'test'
          @action_name = 'index'
          @request = create_mock_request
          @session = create_mock_session
          @test_resource = Object.new.tap { |r| r.define_singleton_method(:id) { 999 } }
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

    it 'executes method-based context callback' do
      controller_class_with_callback.inbound_logging_context(:set_log_context)
      controller = controller_class_with_callback.new

      controller.send(:setup_inbound_logging)

      metadata = Thread.current[:inbound_http_logger_metadata]
      loggable = Thread.current[:inbound_http_logger_loggable]

      _(metadata[:custom_field]).must_equal 'custom_value'
      _(loggable.id).must_equal 999
    end

    it 'executes lambda-based context callback' do
      test_lambda = lambda { |log|
        log.metadata[:lambda_field] = 'lambda_value'
        log.loggable = 'test_loggable'
      }

      controller_class_with_callback.inbound_logging_context(test_lambda)
      controller = controller_class_with_callback.new

      controller.send(:setup_inbound_logging)

      metadata = Thread.current[:inbound_http_logger_metadata]
      loggable = Thread.current[:inbound_http_logger_loggable]

      _(metadata[:lambda_field]).must_equal 'lambda_value'
      _(loggable).must_equal 'test_loggable'
    end

    it 'handles missing callback method gracefully' do
      controller_class_with_callback.inbound_logging_context(:nonexistent_method)
      controller = controller_class_with_callback.new

      # Should not raise an exception
      controller.send(:setup_inbound_logging)

      metadata = Thread.current[:inbound_http_logger_metadata]
      _(metadata).wont_be_nil
      _(metadata[:controller]).must_equal 'test'
    end

    it 'works without any context callback' do
      # Don't set any callback
      controller = controller_class_with_callback.new

      controller.send(:setup_inbound_logging)

      metadata = Thread.current[:inbound_http_logger_metadata]
      _(metadata).wont_be_nil
      _(metadata[:controller]).must_equal 'test'
    end
  end

  describe 'inheritance chain callback lookup' do
    before do
      # Clear any existing callbacks before each test
      InboundHttpLogger::Concerns::ControllerLogging.send(:class_variable_set, :@@context_callbacks, {})
    end

    let(:base_controller_class) do
      Class.new(controller_base_class) do
        include InboundHttpLogger::Concerns::ControllerLogging
      end
    end

    it 'finds callback in current class when set' do
      # Set callback on the class itself
      base_controller_class.inbound_logging_context(:test_callback)

      callback = base_controller_class.inbound_logging_context_callback
      _(callback).must_equal :test_callback
    end

    it 'returns nil when no callback is set anywhere in chain' do
      # No callback set anywhere
      callback = base_controller_class.inbound_logging_context_callback
      _(callback).must_be_nil
    end

    it 'finds callback in parent class when not set in current class' do
      # Set callback on base class
      base_controller_class.inbound_logging_context(:parent_callback)

      # Create subclass without its own callback
      subclass = Class.new(base_controller_class)

      # Should find the parent's callback
      callback = subclass.inbound_logging_context_callback
      _(callback).must_equal :parent_callback
    end

    it 'prefers current class callback over parent class callback' do
      # Set callback on base class
      base_controller_class.inbound_logging_context(:parent_callback)

      # Create subclass with its own callback
      subclass = Class.new(base_controller_class) do
        inbound_logging_context(:child_callback)
      end

      # Should find the child's callback, not the parent's
      callback = subclass.inbound_logging_context_callback
      _(callback).must_equal :child_callback
    end

    it 'walks up multiple inheritance levels' do
      # Set callback on base class
      base_controller_class.inbound_logging_context(:grandparent_callback)

      # Create middle class without callback
      middle_class = Class.new(base_controller_class)

      # Create final subclass without callback
      subclass = Class.new(middle_class)

      # Should find the grandparent's callback
      callback = subclass.inbound_logging_context_callback
      _(callback).must_equal :grandparent_callback
    end

    it 'stops at Object class and returns nil if no callback found' do
      # Create a deep inheritance chain with no callbacks
      level1 = Class.new(base_controller_class)
      level2 = Class.new(level1)
      level3 = Class.new(level2)

      # Should return nil since no callback is set anywhere
      callback = level3.inbound_logging_context_callback
      _(callback).must_be_nil
    end

    it 'works with lambda callbacks in inheritance chain' do
      test_lambda = ->(log) { log.metadata[:inherited] = true }

      # Set lambda callback on base class
      base_controller_class.inbound_logging_context(test_lambda)

      # Create subclass
      subclass = Class.new(base_controller_class)

      # Should find the parent's lambda callback
      callback = subclass.inbound_logging_context_callback
      _(callback).must_equal test_lambda
    end

    it 'finds first callback when multiple levels have callbacks' do
      # Set callback on base class
      base_controller_class.inbound_logging_context(:grandparent_callback)

      # Create middle class with callback
      middle_class = Class.new(base_controller_class) do
        inbound_logging_context(:parent_callback)
      end

      # Create final subclass without callback
      subclass = Class.new(middle_class)

      # Should find the immediate parent's callback, not the grandparent's
      callback = subclass.inbound_logging_context_callback
      _(callback).must_equal :parent_callback
    end
  end
end
