module Argtrace

  # instance per method/block call
  class CallInfo
    attr_accessor :signature

    # actual block instance
    attr_accessor :block_proc
  end

  # call stack of tracing targets
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

  # class definition related operation and result caching.
  class DefinitionResolver
    def initialize
      # TODO:      
    end
  end

  # Main class for tracing with TracePoint.
  class Tracer
    attr_accessor :is_dead

    def initialize()
      @notify_block = nil
      @callstack = CallStack.new
      @tp_holder = nil
      @is_dead = false

      # prune_event_count > 0 while no need to notify.
      # This is used to avoid undesirable signature lerning caused by error test.
      @prune_event_count = 0

      # cache of singleton-class => basic-class
      @singleton_class_map_cache = {}

      # cache of method location (klass => method_id => source_path)
      @method_location_cache = Hash.new{|h, klass| h[klass] = {}}

      # cache of judge result whether method is library-defined or user-defined
      @ignore_paths_cache = {}
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
        # TODO: return type (but maybe, there is no demand)
        block_param.type.merge(block_param_types, nil)
      end
    end

    # process method call/return event
    def trace_method_event(tp)
      if [:call, :c_call].include?(tp.event)
        # I don't know why but tp.parameters is different from called_method.parameters
        # and called_method.parameters not work.
        # called_method = get_called_method(tp)

        case check_event_filter(tp)
        when :prune
          @prune_event_count += 1
          skip_flag = true
        when false
          skip_flag = true
        end

        callinfo = CallInfo.new
        signature = Signature.new
        signature.defined_class = non_singleton_class(tp.defined_class)
        signature.method_id = tp.method_id
        signature.is_singleton_method = tp.defined_class.singleton_class?
        signature.params = get_param_types(tp.parameters, tp)
        callinfo.signature = signature
        callinfo.block_proc = get_block_param_value(tp.parameters, tp)

        @callstack.push_callstack(callinfo)

        if !skip_flag && @prune_event_count == 0
          # skip if it's object specific method
          @notify_block.call(tp.event, callinfo)
        end
      else
        case check_event_filter(tp)
        when :prune
          @prune_event_count -= 1
          skip_flag = true
        when false
          skip_flag = true
        end

        callinfo = @callstack.pop_callstack(tp)
        if callinfo
          if !skip_flag && @prune_event_count == 0
            @notify_block.call(tp.event, callinfo)
          end
        end
      end
    end

    # true if method is defined in user source
    def user_source?(klass, method_id)
      path = get_location(klass, method_id)
      return false unless path

      unless @ignore_paths_cache.key?(path)
        if path.start_with?("<internal:")
          # skip all ruby internal method
          @ignore_paths_cache[path] = true
        elsif path == "(eval)"
          # skip all eval
          @ignore_paths_cache[path] = true
        else
          # skip all sources under load path
          @ignore_paths_cache[path] = $LOAD_PATH.any?{|x| path.start_with?(x)}
        end
      end
      return ! @ignore_paths_cache[path]
    end

    def get_location(klass, method_id)
      unless @method_location_cache[klass].key?(method_id)
        path = nil
        m = klass.instance_method(method_id)
        if m and m.source_location
          path = m.source_location[0]
        end
        @method_location_cache[klass][method_id] = path
      end

      return @method_location_cache[klass][method_id]
    end

    # true if klass is defined under Module
    def under_module?(klass, mod)
      ks = non_singleton_class(klass).to_s
      ms = mod.to_s
      return ks == ms || ks.start_with?(ms + "::")
    end

    # convert singleton class (like #<Class:Regexp>) to non singleton class (like Regexp)
    def non_singleton_class(klass)
      unless klass.singleton_class?
        return klass
      end

      if /^#<Class:([A-Za-z0-9_:]+)>$/ =~ klass.inspect
        # maybe normal name class
        klass_name = Regexp.last_match[1]
        begin
          ret_klass = klass_name.split('::').inject(Kernel){|nm, sym| nm.const_get(sym)}
        rescue => e
          $stderr.puts "----- argtrace bug -----"
          $stderr.puts "cannot convert class name #{klass} => #{klass_name}"
          $stderr.puts e.full_message
          $stderr.puts "------------------------"
          raise
        end
        return ret_klass
      end

      # maybe this class is object's singleton class / special named class.
      # I can't find efficient way, so cache the calculated result.
      if @singleton_class_map_cache.key?(klass)
        return @singleton_class_map_cache[klass]
      end
      begin
        ret_klass = ObjectSpace.each_object(Module).find{|x| x.singleton_class == klass}
        @singleton_class_map_cache[klass] = ret_klass
      rescue => e
        $stderr.puts "----- argtrace bug -----"
        $stderr.puts "cannot convert class name #{klass} => #{klass_name}"
        $stderr.puts e.full_message
        $stderr.puts "------------------------"
        raise
      end
      return ret_klass
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
          if param[0] == :block
            p.type = Signature.new
          elsif param[1] == :* || param[1] == :&
            # workaround for ActiveSupport gem.
            # I don't know why this happen. just discard info about it.
            type = TypeUnion.new
            p.type = type
          else
            # TODO: this part is performance bottleneck caused by eval,
            # but It's essential code
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
          # On class method call, "defined_class" becomes singleton(singular) class.
        elsif tp.self.is_a?(tp.defined_class)
          # On ancestor's method call, "defined_class" is different from self.class.
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

    # check filter from set_filter
    def check_event_filter(tp)
      if @prune_event_filter
        return @prune_event_filter.call(tp)
      else
        return true
      end
    end

    # set event filter
    #   true = normal process
    #   false = skip notify
    #   :prune = skip notify and skip all nested events
    def set_filter(&prune_event_filter)
      @prune_event_filter = prune_event_filter
    end

    def set_exit(&exit_block)
      @exit_block = exit_block
    end

    def set_notify(&notify_block)
      @notify_block = notify_block
    end

    def enable
      @tp_holder.enable
    end

    def disable
      @tp_holder.disable
    end

    # start TracePoint with callback block
    def start_trace()
      tp = TracePoint.new(:c_call, :c_return, :call, :return, :b_call) do |tp|
        begin
          tp.disable
          # DEBUG:
          # p [tp.event, tp.defined_class, tp.method_id]
          self.trace(tp)
        rescue => e
          $stderr.puts "----- argtrace catch exception -----"
          $stderr.puts e.full_message
          $stderr.puts "------------------------------------"
          @is_dead = true
        ensure
          tp.enable unless @is_dead
        end
      end
      @tp_holder = tp

      at_exit do
        # hold Tracer reference in closure
        self.disable
        @exit_block.call if @exit_block
      end

      tp.enable
    end

  end

end