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

    CLASS_NAME_PATTERN = '[A-Z][A-Za-z0-9_]*'
    def api_class?(klass)
      if /\A(#{CLASS_NAME_PATTERN})(::#{CLASS_NAME_PATTERN})*\z/ =~ klass.to_s
        return true
      else
        # this must not be interface class
        return false
      end
    end

    NORMAL_METHOD_NAME_PATTERN = '[A-Za-z0-9_]+[=?!]?'
    OPERATOR_METHOD_NAME_PATTERN = '[!%&=\-~^|\[+*\]<>\/]+'
    def api_method?(method_id)
      if /\A((#{NORMAL_METHOD_NAME_PATTERN})|(#{OPERATOR_METHOD_NAME_PATTERN}))\z/ =~ method_id.to_s
        return true
      else
        # this must not be interface method
        return false
      end
    end

    def ready_signature(signature)
      return nil unless api_class?(signature.defined_class)
      return nil unless api_method?(signature.method_id)

      # DEBUG:
      # if not @lib.key?(signature.defined_class)
      #   p [signature.defined_class, signature.method_id, signature.defined_class.to_s, signature.method_id.to_s]
      # elsif not @lib[signature.defined_class].key?(signature.method_id)
      #   p [signature.defined_class, signature.method_id, signature.defined_class.to_s, signature.method_id.to_s]
      # end

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

    # remove non-api class from type signature
    def discard_noise_from_signature(signature)
      signature.params.each do |param|
        if param.mode == :block
          discard_noise_from_signature(param.type)
        else
          discard_noise_from_typeunion(param.type)
        end
      end
      discard_noise_from_typeunion(signature.return_type)
    end

    def discard_noise_from_typeunion(typeunion)
      return unless typeunion
      typeunion.union.delete_if{|type| noise_type?(type)}
    end

    def noise_type?(type)
      if type.data.is_a?(Symbol)
        return false
      end
      if type.data.is_a?(Array)
        if type.subdata == nil
          return false
        end
        return !api_class?(type.subdata)
      end
      if type.data.is_a?(Class)
        return !api_class?(type.data)
      end
      raise "Unexpected type data : #{type}"
    end

    # add signature into type library
    def learn(signature)
      sig = ready_signature(signature)
      if sig
        discard_noise_from_signature(signature)
        sig.merge(signature.params, signature.return_type)
      else
        # skip
        # $stderr.puts [:skip, signature].inspect
      end
    end

    def to_rbs
      # TODO: should I output class inheritance info ?
      # TODO: private/public
      # TODO: attr_reader/attr_writer/attr_accessor
      mod_root = OutputModule.new

      # DEBUG:
      # $stderr.puts @lib.inspect

      @lib.keys.sort_by{|x| x.to_s}.each do |klass|
        klass_methods = @lib[klass]

        # output instance method first, and then output singleton method.
        [0, 1].each do |instance_or_singleton|
          klass_methods.keys.sort.each do |method_id|
            sig = klass_methods[method_id][instance_or_singleton]
            next unless sig

            begin
              mod_root.add_signature(sig)
            rescue => e
              $stderr.puts "----- argtrace bug -----"
              $stderr.puts "#{klass}::#{method_id} (#{sig})"
              $stderr.puts e.full_message
              $stderr.puts "------------------------"
              raise
            end
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
      add_signature_inner(constname, signature)
    end

    # split class name into consts (e.g. Argtrace::TypeLib to ["Argtrace", "TypeLib"])
    # bad name class is already sanitized, just split.
    def class_const_name(klass)
      klass.to_s.split("::")
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
      if typeunion.union.count{|x| x.data.is_a?(Symbol)} >= 16
        # too much symbols, this should not be enum.
        symbols = typeunion.union.select{|x| x.data.is_a?(Symbol)}
        typeunion.union.delete_if{|x| x.data.is_a?(Symbol)}
        typeunion.add(Type.new_with_type(Symbol))
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

