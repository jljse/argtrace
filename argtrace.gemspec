# frozen_string_literal: true

require_relative "lib/argtrace/version"

Gem::Specification.new do |spec|
  spec.name          = "argtrace"
  spec.version       = Argtrace::VERSION
  spec.authors       = ["Riki Ishikawa"]
  spec.email         = ["riki.ishikawa@gmail.com"]

  spec.summary       = "trace arguments of method calls or block calls."
  spec.description   = "library to trace arguments of method calls or block calls with TracePoint and do callback."
  spec.homepage      = "https://github.com/jljse/argtrace/"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jljse/argtrace/"
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
