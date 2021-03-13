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
Argtrace::AutoTrace.main()

... (YOUR PROGRAM HERE) ...
```

### 2. Implicit trace
Currently not supported yet.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/argtrace.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
