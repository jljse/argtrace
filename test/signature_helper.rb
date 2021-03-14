module SignatureHelper
  def params_from(hashes)
    ret = []
    hashes.each_pair do |name, types|
      param = Argtrace::Parameter.new
      param.mode = :req
      param.name = name
      param.type = typeunion_from(types)
      ret << param
    end
    return ret
  end

  def typeunion_from(types)
    union = Argtrace::TypeUnion.new
    types.each do |type|
      t = Argtrace::Type.new_with_type(type)
      union.add(t)
    end
    return union
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

  def assert_equal_typeunion(u1, u2)
    assert_equal Argtrace::TypeUnion, u1.class
    assert_equal Argtrace::TypeUnion, u2.class
    assert_equal u1.union.to_set, u2.union.to_set
  end
end