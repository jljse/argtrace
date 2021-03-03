# frozen_string_literal: true

require_relative "argtrace/version"

module Argtrace
  class Error < StandardError; end
  
  class CallInfo
    attr_accessor :defined_class, :method_id, :param_types, :return_type, :block_proc
  end

  class CallStack
    def initialize
      @stack = []
    end
  
    def push_callstack(callinfo)
      @stack.push callinfo
    end
  
    def pop_callstack(tp)
      ent = @stack.pop
      if ent
        if tp.method_id != ent.method_id
          raise "callstack is broken ret:#{tp.method_id} <=> stack:#{ent.method_id}"
        end
        ent.return_type = tp.return_value.class
      end
      return ent
    end

    def find_by_block_location(path, lineno)
      ret = []
      @stack.each do |info|
        if info.block_proc && info.block_proc.source_location == [path, lineno]
          ret << info
        end
      end
      return ret
    end
  end

  class ParamType
    attr_accessor :mode, :name, :type
  end

  class Tracer
    def initialize(&notify_block)
      @notify_block = notify_block
      @callstack = CallStack.new
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
        # TODO:
      end
      # TODO:
      # @notify_block.call(tp)
    end

    # process method call/return event
    def trace_method_event(tp)
      if [:call, :c_call].include?(tp.event)
        called_method = get_called_method(tp)

        callinfo = CallInfo.new
        callinfo.defined_class = tp.defined_class
        callinfo.method_id = tp.method_id
        callinfo.param_types = get_param_types(called_method.parameters, tp)
        @callstack.push_callstack(callinfo)
        @notify_block.call(tp.event, callinfo)
      else
        callinfo = @callstack.pop_callstack(tp)
        if callinfo
          @notify_block.call(tp.event, callinfo)
        end
      end
    end

    # convert parameters to ParamType[]
    def get_param_types(parameters, tp)
      if tp.event == :c_call
        # I cannot get parameter values of c_call ...
        return []
      else
        return parameters.map{|param|
          # param[0]=:req, param[1]=:x
          type = ParamType.new
          type.mode = param[0]
          type.name = param[1]
          type.type = tp.binding.eval(param[1].to_s).class
          type
        }
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
      called_method = tp.self.method(tp.method_id)
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
    
      return false
    end

    # start TracePoint with callback block
    def self.start(&notify_block)
      tracer = Tracer.new(&notify_block)
      tp = TracePoint.new(:c_call, :c_return, :call, :return, :b_call) do |tp|
        begin
          tp.disable
          tracer.trace(tp)
        ensure
          tp.enable
        end
      end

      at_exit do
        tp.disable
      end

      tp.enable
      return tracer
    end
  end
end
