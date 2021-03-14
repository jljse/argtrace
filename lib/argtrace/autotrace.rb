module Argtrace
  # Default tracing setting.
  class AutoTrace
    # Default tracing setting. Analyse only user sources, and output them into RBS file.
    def self.main(rbs_path: "sig.rbs")
      typelib = Argtrace::TypeLib.new
      tracer = Argtrace::Tracer.new

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
        File.open(rbs_path, "w") do |f|
          f.puts typelib.to_rbs
        end
      end

      tracer.start_trace
    end
  end
end
