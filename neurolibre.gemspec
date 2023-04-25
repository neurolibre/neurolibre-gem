# frozen_string_literal: true

require File.expand_path "#{File.dirname(__FILE__)}/lib/neurolibre/version"

Gem::Specification.new do |s|
  s.name = "neurolibre"
  s.version = Theoj::VERSION
  s.platform = Gem::Platform::RUBY
  s.date = Time.now.strftime('%Y-%m-%d')
  s.authors = ["Juanjo Bazán"]
  s.homepage = 'http://github.com/neurolibre/neurolibre-gem'
  s.license = "MIT"
  s.summary = "Editorial objects used by NeuroLibre"
  s.description = "A library to manage editorial objects used in the NeuroLibre's moderation and screening process"
  s.metadata = {
    "bug_tracker_uri"   => "https://github.com/neurolibre/neurolibre-gem/issues",
    "changelog_uri"     => "https://github.com/neurolibre/neurolibre-gem/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://www.rubydoc.info/gems/neurolibre",
    "homepage_uri"      => s.homepage,
    "source_code_uri"   => s.homepage
  }
  s.files = %w(LICENSE README.md CHANGELOG.md) + Dir.glob("{spec,lib/**/*}") & `git ls-files -z`.split("\0")
  s.require_paths = ["lib"]
  s.rdoc_options = ['--main', 'README.md', '--charset=UTF-8']

  s.add_dependency "octokit", "~> 6.0"
  s.add_dependency "faraday", "~> 2.7"
  s.add_dependency "faraday-retry", "~> 2.0"
  s.add_dependency "openjournals-nameable", "~> 1.1"
  s.add_dependency "github-linguist", "~> 7.24"
  s.add_dependency "rugged", "~> 1.5"
  s.add_dependency "commonmarker", "~> 0.23"

  s.add_development_dependency "rake", "~> 13.0.6"
  s.add_development_dependency "rspec", "~> 3.11"
end
