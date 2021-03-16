module Argtrace

  # signature of method/block 
  class Signature
    attr_accessor :defined_class, :method_id, :is_singleton_method, :params, :return_type

    def initialize
      @is_singleton_method = false
      @params = []
    end

    def signature_for_block?
      @method_id == nil
    end

    def merge(all_params, ret)
      unless @params
        @params = []
      end
      # all params (including optional / keyword etc)
      for i in 0...all_params.size
        if i == @params.size
          @params << all_params[i]  # TODO: dup
        else
          same_mode = @params[i].mode == all_params[i].mode
          same_name = @params[i].name == all_params[i].name
          # allow name changing only for block call
          if same_mode && (signature_for_block? || same_name)
            if all_params[i].mode == :block
              # TODO: buggy
              # merging of block parameter type is quite tricky...
              @params[i].type.merge(
                all_params[i].type.params, nil)
            else
              @params[i].type.merge_union(all_params[i].type)
            end
          else
            raise "signature change not supported"
          end
        end
      end

      if ret
        unless @return_type
          @return_type = TypeUnion.new
        end
        @return_type.merge_union(ret)
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

  # instance for one parameter
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

  # Union of types (e.g. String | Integer)
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
        if @union[i].superclass_of?(type)
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

  # placeholder for TrueClass / FalseClass
  class BooleanClass
  end

  # type in RBS manner
  class Type
    attr_accessor :data, :subdata

    def initialize()
      @data = nil
      @subdata = nil
    end

    def self.new_with_type(actual_type)
      ret = Type.new
      if actual_type == TrueClass || actual_type == FalseClass
        ret.data = BooleanClass
      else
        ret.data = actual_type
      end
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
      elsif actual_value.class == Array
        # TODO: multi type array
        ret.data = Array
        unless actual_value.empty?
          if true == actual_value.first || false == actual_value.first
            ret.subdata = BooleanClass
          else
            ret.subdata = actual_value.first.class
          end
        end
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
      return @data == other.data && @subdata == other.subdata
    end

    def eql?(other)
      self.==(other)
    end

    # true if self(Type) includes other(Type) as type declaration
    # false if self and other is same Type.
    def superclass_of?(other)
      if other.class != Type
        raise TypeError, "parameter must be Argtrace::Type"
      end
      if @data.is_a?(Symbol)
        return false
      elsif other.data.is_a?(Symbol)
        return false
      elsif @data == Array && other.data == Array
        # TODO: merge for Array type like:
        #   Array[X] | Array[Y]  =>  Array[X|Y]
        if @subdata
          if other.subdata
            return other.subdata < @subdata
          else
            return true
          end
        else
          # if self Array is untyped, cannot replace other as declaration.
          return false
        end
      else
        return other.data < @data
      end
    end

    def to_s
      if @data.is_a?(Symbol)
        @data.inspect
      elsif @data == Array
        if @subdata
          "Array[#{@subdata}]"
        else
          @data
        end
      else
        @data.to_s
      end
    end

    def inspect
      to_s
    end
  end

end
