# Argtrace

Argtrace is a Ruby method type analyser.

Argtrace uses TracePoint and traces all of method calling,
peeks actual type of parameters and return value,
and finally summarize them into RBS format.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'argtrace'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install argtrace

## Usage

### 1. Explicit trace

```ruby
require 'argtrace'

typelib = Argtrace::TypeLib.new
tracer = Argtrace::Tracer.new
tracer.set_filter do |tp|
  # you can filter event by Module nesting
  # return tracer.under_module?(tp.defined_class, "Nokogiri")

  # or by method location
  return tracer.under_path?(tp.defined_class, tp.method_id, __dir__)
end
tracer.set_notify do |ev, callinfo|
  if ev == :return
    typelib.learn(callinfo.signature)
  end
end
tracer.set_exit do
  puts typelib.to_rbs
end
tracer.start_trace

... (YOUR PROGRAM HERE) ...
```

### 2. Implicit trace
```console
$ ruby -m argtrace  YOUR_PROGRAM_HERE.rb
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/argtrace.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
