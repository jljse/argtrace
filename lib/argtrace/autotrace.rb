module Argtrace
  class AutoTrace
    def self.main
      typelib = Argtrace::TypeLib.new
      tracer = Argtrace::Tracer.new
      ignore_paths_cache = {}

      tracer.set_filter do |tp|
        if [:call, :return].include?(tp.event)
          tracer.user_source?(tp.defined_class, tp.method_id)
        else
          true
        end
      end

      tracer.set_notify do |ev, callinfo|
        if ev == :return
          typelib.learn(callinfo.signature)
        end
      end

      tracer.set_exit do
        File.open("sig.rbs", "w") do |f|
          f.puts typelib.to_rbs
        end
      end

      tracer.start_trace
    end
  end
end
