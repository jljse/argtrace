require 'set'

module Argtrace

  class TypeLib
    # class => { method_id => [normal_method_signature, singleton_method_signature] }
    def lib
      @lib
    end

    def initialize
      @lib = Hash.new{|hklass, klass|
        hklass[klass] = Hash.new{|hmethod, method_id|
          hmethod[method_id] = [nil, nil]
        }
      }
    end

    def ready_signature(signature)
      pair = @lib[signature.defined_class][signature.method_id]
      index = signature.is_singleton_method ? 1 : 0
      unless pair[index]
        sig = Signature.new
        sig.defined_class = signature.defined_class
        sig.method_id = signature.method_id
        sig.is_singleton_method = signature.is_singleton_method
        sig.return_type = nil
        pair[index] = sig
      end
      return pair[index]
    end

    def lern(signature)
      ready_signature(signature).merge(signature.params, signature.return_type)
    end
  end

end

typelib = Argtrace::TypeLib.new
tracer = Argtrace::Tracer.new
tracer.set_filter do |tp|
  if tracer.part_of_module?(tp.defined_class, "Nokogiri")
    true
  else
    false
  end
end
tracer.set_notify do |ev, callinfo|
  if ev == :return
    typelib.lern(callinfo.signature)
  end
end
tracer.set_exit do
  typelib.lib.keys.sort_by{|x| x.to_s}.each do |klass|
    klass_methods = typelib.lib[klass]

    puts "----------"
    puts klass.to_s
    [0, 1].each do |index|
      klass_methods.keys.each do |method_id|
        sig = klass_methods[method_id][index]
        next unless sig

        singleton_tag = sig.is_singleton_method ? "self." : ""
        params_str = sig.params.map{|x| x.to_s}.join(", ")
        puts "  #{singleton_tag}#{method_id} : (#{params_str}) => #{sig.return_type.to_s}"
      end
    end
    puts
  end
end
tracer.start_trace
