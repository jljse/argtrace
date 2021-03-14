require 'set'

module Argtrace

  # Store of signatures
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

    def learn(signature)
      ready_signature(signature).merge(signature.params, signature.return_type)
    end

    def to_rbs
      # TODO: should I output class inheritance info ?
      # TODO: private/public
      # TODO: attr_reader/attr_writer/attr_accessor
      mod_root = OutputModule.new

      @lib.keys.sort_by{|x| x.to_s}.each do |klass|
        klass_methods = @lib[klass]

        # output instance method first, and then output singleton method.
        [0, 1].each do |instance_or_singleton|
          klass_methods.keys.sort.each do |method_id|
            sig = klass_methods[method_id][instance_or_singleton]
            next unless sig

            mod_root.add_signature(sig)
          end
        end
      end

      mod_root.to_rbs
    end
  end

  # helper to convert TypeLib into RBS. OutputMoudle acts like Module tree node.
  class OutputModule
    attr_accessor :actual_module, :name, :children, :signatures

    def initialize
      @children = {}
      @signatures = []
    end

    def add_signature(signature)
      # this is root node, so use Kernel as const resolve source.
      @actual_module = Kernel

      constname = class_const_name(signature.defined_class)
      unless constname
        # cannot handle this
        return
      end

      add_signature_inner(constname, signature)
    end

    # split class name into consts (e.g. Argtrace::TypeLib to ["Argtrace", "TypeLib"])
    def class_const_name(klass)
      if /^[A-Za-z0-9_:]+$/ =~ klass.to_s
        # this should be normal name
        consts = klass.to_s.split("::")

        # assertion
        resolved_class = consts.inject(Kernel){|mod, const| mod.const_get(const)}
        if klass != resolved_class
          $stderr.puts "----- argtrace bug -----"
          $stderr.puts "#{klass} => #{consts} => #{resolved_class}"
          $stderr.puts "------------------------"
          raise "Failed to resolve class by constant"
        end

        return consts
      else
        return nil
      end
    end

    def add_signature_inner(name_consts, signature)
      if name_consts.empty?
        @signatures << signature
      else
        unless @children.key?(name_consts.first)
          mod = OutputModule.new
          mod.name = name_consts.first
          mod.actual_module = @actual_module.const_get(name_consts.first)
          @children[name_consts.first] = mod
        end
        current_resolving_name = name_consts.shift
        @children[current_resolving_name].add_signature_inner(name_consts, signature)
      end
    end

    def to_rbs
      # this is root node
      lines = []
      @children.keys.sort.each do |child_name|
        lines << @children[child_name].to_rbs_inner(0)
        lines << ""
      end
      return lines.join("\n")
    end

    def to_rbs_inner(indent_level)
      indent = "  " * indent_level
      classmod_def = @actual_module.class == Class ? "class" : "module"

      lines = []
      lines << "#{indent}#{classmod_def} #{name}"
      @children.keys.sort.each do |child_name|
        lines << @children[child_name].to_rbs_inner(indent_level + 1)
        lines << ""
      end
      @signatures.each do |sig|
        lines << sig_to_rbs(indent_level + 1, sig)
      end
      lines << "#{indent}end"
      return lines.join("\n")
    end

    def sig_to_rbs(indent_level, signature)
      indent = "  " * indent_level
      sig_name = signature.is_singleton_method ? "self.#{signature.method_id}" : signature.method_id
      params = signature.params
        .filter{|p| p.mode != :block}
        .map{|p| param_to_rbs(p)}
        .compact
        .join(", ")
      rettype = type_union_to_rbs(signature.return_type)
      blocktype = blocktype_to_rbs(signature.params.find{|p| p.mode == :block})
      return "#{indent}def #{sig_name} : (#{params})#{blocktype} -> #{rettype}"
    end

    def blocktype_to_rbs(blockparam)
      unless blockparam
        return ""
      end
      params = blockparam.type.params
        .map{|p| type_union_to_rbs(p.type)}
        .join(", ")
      return " { (#{params}) -> untyped }"
    end

    def param_to_rbs(param)
      case param.mode
      when :req
        return "#{type_union_to_rbs(param.type)} #{param.name}"
      when :opt
        return "?#{type_union_to_rbs(param.type)} #{param.name}"
      when :keyreq
        return "#{param.name}: #{type_union_to_rbs(param.type)}"
      when :key
        return "?#{param.name}: #{type_union_to_rbs(param.type)}"
      when :block
        return nil
      end
    end

    def type_union_to_rbs(typeunion)
      if typeunion.union.size == 0
        return "untyped"
      end
      # TODO: ugly
      if typeunion.union.size == 1 and NilClass == typeunion.union.first.data
        # TODO: I can't distinguish nil and untyped.
        return "untyped"
      end
      if typeunion.union.size == 2 and typeunion.union.any?{|x| NilClass == x.data}
        # type is nil and sometype, so represent it as "sometype?"
        sometype = typeunion.union.find{|x| NilClass != x.data}
        return "#{type_to_rbs(sometype)}?"
      end

      ret = typeunion.union.map{|type| type_to_rbs(type)}.join("|")
      return ret
    end

    def type_to_rbs(type)
      if type.data.is_a?(Symbol)
        return type.data.inspect
      elsif true == type.data || false == type.data || BooleanClass == type.data
        return "bool"
      elsif nil == type.data || NilClass == type.data
        return "nil"
      elsif Array == type.data
        if type.subdata
          case type.subdata
          when true, false, BooleanClass
            elementtype = "bool"
          else
            elementtype = type.subdata.to_s
          end
          return "Array[#{elementtype}]"
        else
          return "Array"
        end
      else
        return type.data.to_s
      end
    end

  end
end

