# frozen_string_literal: true

require_relative 'lib/nextjs_hydration_parser/version'

Gem::Specification.new do |spec|
  spec.name = 'nextjs-hydration-parser'
  spec.version = NextjsHydrationParser::VERSION
  spec.authors = ['Jonah George']
  spec.email = []

  spec.summary = 'A Ruby library for extracting and parsing Next.js hydration data from HTML content'
  spec.description = 'A specialized Ruby library for extracting and parsing Next.js 13+ hydration data from raw HTML pages. When scraping Next.js applications, the server-side rendered HTML contains complex hydration data chunks embedded in self.__next_f.push() calls that need to be properly assembled and parsed to access the underlying application data.'
  spec.homepage = 'https://github.com/jonahgeorge/nextjs-hydration-parser'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/jonahgeorge/nextjs-hydration-parser'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{lib}/**/*') + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ['lib']

  # Runtime dependencies
  # Note: chompjs is installed via git in Gemfile

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 13.0'
end
