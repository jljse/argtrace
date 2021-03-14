require "test_helper"
require_relative "signature_helper"

class TracerTest < Minitest::Test
  include SignatureHelper

  class X
    def foo(x, y)
      x
    end

    def bar()
      nil
    end
  end

  def signature_from(klass, method_id, params_hash, ret_type)
    sig = Argtrace::Signature.new
    sig.defined_class = klass
    sig.method_id = method_id
    sig.params = params_from(params_hash)
    sig.return_type = typeunion_from(ret_type)
    sig.is_singleton_method = false
    return sig
  end

  def test_learn
    lib = Argtrace::TypeLib.new
    lib.learn(signature_from(X, :foo, {x: [String], y: [Integer]}, [String]))
    lib.learn(signature_from(X, :foo, {x: [String], y: [Integer]}, [String]))
    lib.learn(signature_from(X, :bar, {}, [NilClass]))
    lib.learn(signature_from(X, :bar, {}, [TrueClass]))
    lib.learn(signature_from(X, :bar, {}, [FalseClass]))

    ans_foo_params = params_from({x: [String], y: [Integer]})
    ans_foo_ret = typeunion_from([String])
    assert_equal 2, lib.lib[X][:foo][0].params.size
    assert_equal_typeunion ans_foo_params[0].type, lib.lib[X][:foo][0].params[0].type
    assert_equal_typeunion ans_foo_params[1].type, lib.lib[X][:foo][0].params[1].type
    assert_equal_typeunion ans_foo_ret, lib.lib[X][:foo][0].return_type

    ans_bar_ret = typeunion_from([NilClass, TrueClass])
    assert_equal 0, lib.lib[X][:bar][0].params.size
    assert_equal_typeunion ans_bar_ret, lib.lib[X][:bar][0].return_type
  end
end