# frozen_string_literal: true

require_relative "lib/probot/version"

Gem::Specification.new do |spec|
  spec.name = "probot"
  spec.version = Probot::VERSION
  spec.authors = ["Dan Milne"]
  spec.email = ["d@nmilne.com"]

  spec.summary = "A robots.txt parser."
  spec.description = "A fully featured robots.txt parser."
  spec.homepage = "http://github.com/dkam/probot"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"
  spec.platform = Gem::Platform::RUBY

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "http://github.com/dkam/probot"
  spec.metadata["changelog_uri"] = "http://github.com/dkam/probot/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_development_dependency "debug"
end
