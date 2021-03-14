# frozen_string_literal: true

require "test_helper"
require_relative "signature_helper"
require 'pathname'

class TracerTest < Minitest::Test
  include SignatureHelper

  def example_method(x, y)
    x
  end

  def test_user_source()
    trace = Argtrace::Tracer.new
    refute trace.user_source?(String, :split)
    refute trace.user_source?(Minitest::Test, :assert_equal)
    refute trace.user_source?(Pathname, :parent)
    assert trace.user_source?(TracerTest, :example_method)
  end

  def test_under_module()
    trace = Argtrace::Tracer.new
    assert trace.under_module?(Argtrace::Tracer, "Argtrace")
    assert trace.under_module?(Minitest::Test, "Minitest::Test")
    refute trace.under_module?(Minitest::Test, "Minites")
  end

  def test_trace
    filter_counter = 0
    notify_counter = 0
    ans_params = params_from({x: [String], y: [Integer]})
    ans_ret = typeunion_from([String])

    trace = Argtrace::Tracer.new
    trace.set_filter do |tp|
      if tp.event == :call and filter_counter == 0
        filter_counter += 1
        assert_equal TracerTest, tp.defined_class
        assert_equal :example_method, tp.method_id
      end
      true
    end

    trace.set_notify do |ev, callinfo|
      if ev == :return and notify_counter == 0
        notify_counter += 1
        assert_equal TracerTest, callinfo.signature.defined_class
        assert_equal :example_method, callinfo.signature.method_id
        assert_equal 2, callinfo.signature.params.size
        assert_equal_typeunion ans_params[0].type, callinfo.signature.params[0].type
        assert_equal_typeunion ans_params[1].type, callinfo.signature.params[1].type
        assert_equal_typeunion ans_ret, callinfo.signature.return_type
      end
    end

    trace.start_trace
    self.example_method("1", 2)
    trace.stop_trace

    assert_equal 1, filter_counter
    assert_equal 1, notify_counter
  end
end
