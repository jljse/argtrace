# frozen_string_literal: true

require_relative "argtrace/version"
require_relative "argtrace/signature.rb"
require_relative "argtrace/tracer.rb"
require_relative "argtrace/typelib.rb"
require_relative "argtrace/default.rb"

module Argtrace
  class ArgtraceError < StandardError; end
end

