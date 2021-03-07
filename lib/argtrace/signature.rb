
module Argtrace

  class Signature
    attr_accessor :defined_class, :method_id, :params, :return_type

    def initialize
      @params = []
    end

    def merge(all_params)
      normal_params = all_params.select{|p| p.mode == :req || p.mode == :opt}
      for i in 0...normal_params.size
        if i == @params.size
          @params << normal_params[i]  # TODO: dup
        else
          if @params[i].mode == normal_params[i].mode &&
              @params[i].name == normal_params[i].name
            @params[i].type.merge_union(normal_params[i].type)
          else
            raise "signature change not supported"
          end
          
        end
      end
    end

    def get_block_param
      @params.find{|x| x.mode == :block}
    end

    def to_s
      "Signature(#{@defined_class}::#{@method_id}(" + @params.map{|x| x.to_s}.join(",") + ") => #{@return_type.to_s})"
    end

    def inspect
      to_s
    end
  end

  class Parameter
    attr_accessor :mode, :name, :type

    def hash
      [@mode, @name, @type].hash
    end

    def to_s
      "Parameter(#{@name}@#{@mode}:#{@type.to_s})"
    end

    def inspect
      to_s
    end
  end

  class TypeUnion
    attr_accessor :union;

    def initialize
      @union = []
    end

    def merge_union(other_union)
      other_union.union.each do |type|
        self.add(type)
      end
    end

    def add(type)
      for i in 0...@union.size
        if @union[i] == type
          # already in union
          return
        end
        if type.superclass_of?(@union[i])
          # remove redundant element
          @union[i] = nil
        end
      end
      @union.compact!
      @union << type
      self
    end

    def to_s
      if @union.empty?
        "TypeUnion(None)"
      else
        "TypeUnion(" + @union.map{|x| x.to_s}.join("|") + ")"
      end
    end

    def inspect
      to_s
    end
  end

  class BooleanClass
  end

  class Type
    attr_accessor :data;

    def initialize()
      @data = nil
    end

    def self.new_with_type(actual_type)
      ret = Type.new
      ret.data = actual_type
      return ret
    end

    def self.new_with_value(actual_value)
      ret = Type.new
      if actual_value.is_a?(Symbol)
        # use symbol as type
        ret.data = actual_value
      elsif true == actual_value || false == actual_value
        # warn: operands of == must in this order, because of override.
        # treat true and false as boolean
        ret.data = BooleanClass
      else
        ret.data = actual_value.class
      end
      return ret
    end

    def hash
      @data.hash
    end

    def ==(other)
      if other.class != Type
        return false
      end
      return @data == other.data
    end

    # true if self(Type) includes other(Type) as type declaration
    def superclass_of?(other)
      if other.class != Type
        raise TypeError, "parameter must be Argtrace::Type"
      end
      if @data.is_a?(Symbol)
        return false
      elsif other.data.is_a?(Symbol)
        return false
      else
        return other.data < @data
      end
    end

    def to_s
      if @data.is_a?(Symbol)
        @data
      else
        @data.to_s
      end
    end

    def inspect
      to_s
    end
  end

end
