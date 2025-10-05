# frozen_string_literal: true

require_relative 'nextjs_hydration_parser/version'
require_relative 'nextjs_hydration_parser/extractor'

# Next.js Hydration Parser
#
# A Ruby library for extracting and parsing Next.js hydration data from HTML content.
module NextjsHydrationParser
  class Error < StandardError; end
end
