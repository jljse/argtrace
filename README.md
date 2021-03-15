# Argtrace

Argtrace is a Ruby MRI method type analyser.

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
Argtrace::Default.main(rbs_path: "sig.rbs")

... (YOUR PROGRAM HERE) ...
```
RBS file is saved as "sig.rbs" in current directory.

### 2. Implicit trace
```console
$ ruby -r argtrace/autorun  YOUR_PROGRAM_HERE.rb
```
RBS file is saved as "sig.rbs" in current directory.

### 3. rspec
Modify Rakefile to load Argtrace.
```ruby
RSpec::Core::RakeTask.new(:spec) do |t|
  t.ruby_opts = %w[-r argtrace/autorun]
end
```
then run as usual like `rake spec`.
RBS file is saved as "sig.rbs" in current directory.

### Restriction
- Argtrace cannot work with C-extension,
  because TracePoint doesn't provide feature to access arguments of calls into C-extension.
- Only work with single-thread programs.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jljse/argtrace.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
