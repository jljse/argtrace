# frozen_string_literal: true

require_relative "argtrace/version"

module Argtrace
  class ArgtraceError < StandardError; end
  
  class CallInfo
    attr_accessor :signature, :block_proc
  end

  class CallStack
    def initialize
      # thread.object_id => stack
      @stack = Hash.new{|h,k| h[k] = []}
    end
  
    def push_callstack(callinfo)
      id = Thread.current.object_id
      # DEBUG:
      # p "[#{id}]>>" + " "*@stack[id].size*2 + callinfo.signature.to_s

      @stack[id].push callinfo
    end
  
    def pop_callstack(tp)
      id = Thread.current.object_id
      ent = @stack[id].pop
      if ent
        # DEBUG:
        # p "[#{id}]<<" + " "*@stack[id].size*2 + ent.signature.to_s

        if tp.method_id != ent.signature.method_id
          raise <<~EOF
            callstack is broken
            returning by tracepoint: #{tp.defined_class}::#{tp.method_id}
            top of stack: #{ent.signature.to_s}
            rest of stack:
              #{@stack[id].map{|x| x.signature.to_s}.join("\n  ")}
          EOF
        end
        type = TypeUnion.new
        type.add(Type.new_with_value(tp.return_value))
        ent.signature.return_type = type
      end
      return ent
    end

    # find callinfo which use specific block
    def find_by_block_location(path, lineno)
      id = Thread.current.object_id
      ret = []
      @stack[id].each do |info|
        if info.block_proc && info.block_proc.source_location == [path, lineno]
          ret << info
        end
      end
      return ret
    end
  end

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

  class Tracer
    attr_accessor :is_dead

    def initialize(&notify_block)
      @notify_block = notify_block
      @callstack = CallStack.new
      @tp_holder = nil
      @is_dead = false
    end

    # entry point of trace event
    def trace(tp)
      if ignore_event?(tp)
        return
      end

      if [:b_call, :b_return].include?(tp.event)
        trace_block_event(tp)
      else
        trace_method_event(tp)
      end
    end

    # process block call/return event
    def trace_block_event(tp)
      # I cannot determine the called block instance directly, so use block's location.
      callinfos_with_block = @callstack.find_by_block_location(tp.path, tp.lineno)
      callinfos_with_block.each do |callinfo|
        block_param = callinfo.signature.get_block_param
        block_param_types = get_param_types(callinfo.block_proc.parameters, tp)
        block_param.type.merge(block_param_types)
      end
    end

    # process method call/return event
    def trace_method_event(tp)
      if [:call, :c_call].include?(tp.event)
        # I don't know why but tp.parameters is different from called_method.parameters
        # and called_method.parameters not work.
        # called_method = get_called_method(tp)

        callinfo = CallInfo.new
        signature = Signature.new
        signature.defined_class = tp.defined_class
        signature.method_id = tp.method_id
        signature.params = get_param_types(tp.parameters, tp)
        callinfo.signature = signature
        callinfo.block_proc = get_block_param_value(tp.parameters, tp)

        @callstack.push_callstack(callinfo)
        @notify_block.call(tp.event, callinfo)
      else
        callinfo = @callstack.pop_callstack(tp)
        if callinfo
          @notify_block.call(tp.event, callinfo)
        end
      end
    end

    # convert parameters to Parameter[]
    def get_param_types(parameters, tp)
      if tp.event == :c_call
        # I cannot get parameter values of c_call ...
        return []
      else
        return parameters.map{|param|
          # param[0]=:req, param[1]=:x
          p = Parameter.new
          p.mode = param[0]
          p.name = param[1]
          if param[1] == :* || param[1] == :&
            # workaround for ActiveSupport gem.
            # I don't know why this happen. just discard info about it.
            type = TypeUnion.new
            p.type = type
          elsif param[0] == :block
            p.type = Signature.new
          else
            type = TypeUnion.new
            begin
              val = tp.binding.eval(param[1].to_s)
            rescue => e
              $stderr.puts "----- argtrace bug -----"
              $stderr.puts parameters.inspect
              $stderr.puts e.full_message
              $stderr.puts "------------------------"
              raise
            end
            type.add Type.new_with_value(val)
            p.type = type
          end
          p
        }
      end
    end

    # pickup block parameter as proc if exists
    def get_block_param_value(parameters, tp)
      if tp.event == :c_call
        # I cannot get parameter values of c_call ...
        return nil
      else
        parameters.each do |param|
          if param[0] == :block
            if param[1] == :&
              # workaround for ActiveSupport gem.
              # I don't know why this happen. just discard info about it.
              return nil
            end
            begin
              val = tp.binding.eval(param[1].to_s)
            rescue => e
              $stderr.puts "----- argtrace bug -----"
              $stderr.puts parameters.inspect
              $stderr.puts e.full_message
              $stderr.puts "------------------------"
              raise
            end
            return val
          end
        end
        return nil
      end
    end

    # current called method object
    def get_called_method(tp)
      if tp.defined_class != tp.self.class
        # I cannot identify all cases for this, so checks strictly.

        if tp.defined_class.singleton_class?
          # On class method call, "defined_class" becomes singleton(singular) class, so just let it go.
        elsif tp.self.is_a?(tp.defined_class)
          # On ancestor's method call, "defined_class" is different from self.class, as expected.
        else
          # This is unknown case.
          raise "type inconsistent def:#{tp.defined_class} <=> self:#{tp.self.class} "
        end
      end
      return tp.self.method(tp.method_id)
    end

    # true for the unhandleable events
    def ignore_event?(tp)
      if tp.defined_class.equal?(Class) and tp.method_id == :new
        # On "Foo.new", I want "Foo" here,
        # but "binding.receiver" equals to caller's "self" so I cannot get "Foo" from anywhere.
        # Just ignore.
        return true
      end
    
      if tp.defined_class.equal?(BasicObject) and tp.method_id == :initialize
        # On "Foo#initialize", I want "Foo" here,
        # but if "Foo" doesn't  have explicit "initialize" method then no clue to get "Foo".
        # Just ignore.
        return true
      end
    
      if tp.defined_class.equal?(Class) and tp.method_id == :inherited
        # I can't understand this.
        # Just ignore.
        return true
      end
    
      if tp.defined_class.equal?(Module) and tp.method_id == :method_added
        # I can't understand this.
        # Just ignore.
        return true
      end
    
      return false
    end

    def start
      @tp_holder.enable
    end

    def stop
      @tp_holder.disable
    end

    def tp_holder=(tp)
      @tp_holder = tp
    end

    # start TracePoint with callback block
    def self.start(&notify_block)
      tracer = Tracer.new(&notify_block)
      tp = TracePoint.new(:c_call, :c_return, :call, :return, :b_call) do |tp|
        begin
          tp.disable
          # DEBUG:
          # p [tp.event, tp.defined_class, tp.method_id]
          tracer.trace(tp)
        rescue => e
          $stderr.puts "----- argtrace catch exception -----"
          $stderr.puts e.full_message
          $stderr.puts "------------------------------------"
          tracer.is_dead = true
        ensure
          tp.enable unless tracer.is_dead
        end
      end
      tracer.tp_holder = tp

      at_exit do
        # hold reference in closure
        tracer.stop
      end

      tp.enable
      return tracer
    end

  end
end

