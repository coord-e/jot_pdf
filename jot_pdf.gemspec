# frozen_string_literal: true

require_relative "lib/jot_pdf/version"

Gem::Specification.new do |spec|
  spec.name = "jot_pdf"
  spec.version = JotPDF::VERSION
  spec.authors = ["coord_e"]
  spec.email = ["me@coord-e.com"]

  spec.summary = "Streaming PDF writer DSL"
  spec.homepage = "https://github.com/coord-e/jot_pdf"
  spec.license = "MIT"
  spec.required_ruby_version = ">=3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/coord-e/jot_pdf"
  spec.metadata["changelog_uri"] = "https://github.com/coord-e/jot_pdf/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ sig/shims/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "docile", "~> 1.0"
  spec.add_dependency "ttfunk", "~> 1.0"
end
