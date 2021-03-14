# frozen_string_literal: true

require "test_helper"
require_relative "signature_helper"

class TypeTest < Minitest::Test
  def test_equal
    t1 = Argtrace::Type.new_with_type(String)
    t2 = Argtrace::Type.new_with_value("foo")
    assert t1 == t2
    t3 = Argtrace::Type.new_with_value(2)
    assert t1 != t3
    assert t1 != String
  end

  def test_equal_symbol
    t1 = Argtrace::Type.new_with_value(:a)
    t2 = Argtrace::Type.new_with_value(:b)
    assert t1 != t2
  end

  def test_equal_array
    t1 = Argtrace::Type.new_with_value([1])
    t2 = Argtrace::Type.new_with_value(["x"])
    assert t1 != t2
    t3 = Argtrace::Type.new_with_value([2, 3])
    assert t1 == t3
  end

  def test_equal_bool
    t1 = Argtrace::Type.new_with_value(true)
    t2 = Argtrace::Type.new_with_value(false)
    assert t1 == t2
    t3 = Argtrace::Type.new_with_value([true])
    t4 = Argtrace::Type.new_with_value([false])
    assert t3 == t4
  end

  def test_superclass_of
    t1 = Argtrace::Type.new_with_type(Minitest::Test)
    t2 = Argtrace::Type.new_with_type(TypeTest)
    assert t1.superclass_of?(t2)
    refute t2.superclass_of?(t1)
    refute t1.superclass_of?(t1)
  end

  def test_superclass_of_symbol
    t1 = Argtrace::Type.new_with_value(:foo)
    t2 = Argtrace::Type.new_with_value(:bar)
    refute t2.superclass_of?(t1)
  end

  class X
  end

  class Y < X
  end

  def test_superclass_of_array
    t1 = Argtrace::Type.new_with_value([X.new])
    t2 = Argtrace::Type.new_with_value([Y.new])
    t3 = Argtrace::Type.new_with_value([1])
    assert t1.superclass_of?(t2)
    refute t2.superclass_of?(t1)
    refute t1.superclass_of?(t3)
  end

  def test_superclass_of_bool
    t1 = Argtrace::Type.new_with_value([true])
    t2 = Argtrace::Type.new_with_value([false])
    refute t1.superclass_of?(t2)
  end
end


class TypeUnionTest < Minitest::Test
  def test_add
    u = Argtrace::TypeUnion.new
    t1 = Argtrace::Type.new_with_type(String)
    t2 = Argtrace::Type.new_with_type(Integer)
    u.add(t1)
    u.add(t2)
    assert_equal [t1, t2].to_set, u.union.to_set
    t3 = Argtrace::Type.new_with_type(String)
    u.add(t3)
    assert_equal [t1, t2].to_set, u.union.to_set
  end

  class X
  end

  class Y < X
  end

  class Z < X
  end

  def test_add_complex
    u = Argtrace::TypeUnion.new
    s = Argtrace::Type.new_with_type(String)
    i = Argtrace::Type.new_with_type(Integer)
    x = Argtrace::Type.new_with_type(X)
    y = Argtrace::Type.new_with_type(Y)
    z = Argtrace::Type.new_with_type(Z)
    t = Argtrace::Type.new_with_value(true)
    f = Argtrace::Type.new_with_value(false)
    s1 = Argtrace::Type.new_with_value(:foo)
    s2 = Argtrace::Type.new_with_value(:bar)

    u.add(s)
    u.add(y)
    u.add(t)
    u.add(s1)
    assert_equal [s, y, t, s1].to_set, u.union.to_set
    u.add(z)
    u.add(i)
    assert_equal [s, y, t, s1, z, i].to_set, u.union.to_set
    u.add(x)
    assert_equal [s, t, s1, x, i].to_set, u.union.to_set
    u.add(f)
    assert_equal [s, t, s1, x, i].to_set, u.union.to_set
    u.add(s2)
    assert_equal [s, t, s1, x, i, s2].to_set, u.union.to_set
  end

  def test_merge_union
    u1 = Argtrace::TypeUnion.new
    u2 = Argtrace::TypeUnion.new
    s = Argtrace::Type.new_with_type(String)
    i = Argtrace::Type.new_with_type(Integer)
    x = Argtrace::Type.new_with_type(X)
    y = Argtrace::Type.new_with_type(Y)

    u1.add(s)
    u1.add(x)
    u2.add(i)
    u2.add(y)
    u1.merge_union(u2)
    assert_equal [s, x, i].to_set, u1.union.to_set
  end
end


class SignatureTest < Minitest::Test
  include SignatureHelper
  
  def test_merge
    sig1 = Argtrace::Signature.new
    sig1.params = params_from({
      x: [String],
      y: [Integer],
    })
    sig1.return_type = typeunion_from([String])

    sig2 = Argtrace::Signature.new
    sig2.params = params_from({
      x: [Regexp],
      y: [Array],
    })
    sig2.return_type = typeunion_from([Hash])

    sig1.merge(sig2.params, sig2.return_type)

    ans_param1 = typeunion_from([String, Regexp])
    ans_param2 = typeunion_from([Integer, Array])
    ans_ret = typeunion_from([String, Hash])

    assert_equal 2, sig1.params.size
    assert_equal ans_param1.union.to_set, sig1.params[0].type.union.to_set
    assert_equal ans_param2.union.to_set, sig1.params[1].type.union.to_set
    assert_equal ans_ret.union.to_set, sig1.return_type.union.to_set
  end
end