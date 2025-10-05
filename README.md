> [!CAUTION]
> This is an LLM-ported version of [`kennyaires/nextjs-hydration-parser`](https://github.com/kennyaires/nextjs-hydration-parser) to Ruby. While the test suite passes and functionality is maintained, this port should be considered experimental.

# Next.js Hydration Parser

A specialized Ruby library for extracting and parsing Next.js 13+ hydration data from raw HTML pages. When scraping Next.js applications, the server-side rendered HTML contains complex hydration data chunks embedded in `self.__next_f.push()` calls that need to be properly assembled and parsed to access the underlying application data.

## Problem Statement

Next.js 13+ applications with App Router use a sophisticated hydration system that splits data across multiple script chunks in the raw HTML. When you scrape these pages (before JavaScript execution), you get fragments like:

```html
<script>
  self.__next_f.push([1, "partial data chunk 1"]);
</script>
<script>
  self.__next_f.push([1, "continuation of data"]);
</script>
<script>
  self.__next_f.push([2, '{"products":[{"id":1,"name":"Product"}]}']);
</script>
```

This data is:

- **Split across multiple chunks** that need to be reassembled
- **Encoded in various formats** (JSON strings, base64, escaped content)
- **Mixed with rendering metadata** that needs to be filtered out
- **Difficult to parse** due to complex escaping and nested structures

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'chompjs', git: 'https://github.com/jonahgeorge/chompjs.git'
gem 'nextjs-hydration-parser', git: 'https://github.com/jonahgeorge/nextjs-hydration-parser.git'
```

## Quick Start

```ruby
require 'nextjs_hydration_parser'
require 'http'

# Create an extractor instance
extractor = NextjsHydrationParser::Extractor.new

# Scrape a Next.js page (before JavaScript execution)
response = HTTP.get('https://example-nextjs-ecommerce.com/products')
html_content = response.to_s

# Extract and parse the hydration data
chunks = extractor.parse(html_content)

# Process the results to find meaningful data
chunks.each do |chunk|
  puts "Chunk ID: #{chunk[:chunk_id]}"
  chunk[:extracted_data].each do |item|
    if item[:type] == 'colon_separated'
      # Often contains API response data
      puts "API Data: #{item[:data]}"
    elsif item[:data].to_s.include?('products')
      # Found product data
      puts "Products: #{item[:data]}"
    end
  end
end
```

### Real-world Example: E-commerce Scraping

```ruby
# Extract product data from a Next.js e-commerce site
extractor = NextjsHydrationParser::Extractor.new
html_content = File.read('product_page.html')

chunks = extractor.parse(html_content)

# Find product information
products = extractor.find_data_by_pattern(chunks, 'product')
products.each do |product_data|
  if product_data[:value].is_a?(Hash)
    product = product_data[:value]
    puts "Product: #{product['name'] || 'Unknown'}"
    puts "Price: $#{product['price'] || 'N/A'}"
    puts "Stock: #{product['inventory'] || 'Unknown'}"
  end
end
```

## Advanced Usage

### Scraping Complex Next.js Applications

```ruby
require 'http'
require 'nextjs_hydration_parser'

def scrape_nextjs_data(url)
  # Get raw HTML (before JavaScript execution)
  headers = { 'User-Agent' => 'Mozilla/5.0 (compatible; DataExtractor/1.0)' }
  response = HTTP.headers(headers).get(url)

  # Parse hydration data
  extractor = NextjsHydrationParser::Extractor.new
  chunks = extractor.parse(response.to_s)

  # Extract meaningful data
  extracted_data = {}

  chunks.each do |chunk|
    next if chunk[:chunk_id] == 'error'  # Skip malformed chunks

    chunk[:extracted_data].each do |item|
      data = item[:data]

      # Look for common data patterns
      if data.is_a?(Hash)
        # API responses often contain these keys
        ['products', 'users', 'posts', 'data', 'results'].each do |key|
          if data.key?(key)
            extracted_data[key] = data[key]
          end
        end
      end
    end
  end

  extracted_data
end

# Usage
data = scrape_nextjs_data('https://nextjs-shop.example.com')
puts "Found #{data['products']&.length || 0} products"
```

### Handling Large HTML Files

When scraping large Next.js applications, you might encounter hundreds of hydration chunks:

```ruby
# Read from file
html_content = File.read('large_nextjs_page.html', encoding: 'utf-8')

# Parse and extract
extractor = NextjsHydrationParser::Extractor.new
chunks = extractor.parse(html_content)

puts "Found #{chunks.length} hydration chunks"

# Get overview of all available data keys
all_keys = extractor.get_all_keys(chunks)
puts "Most common data keys:"
all_keys.first(20).each do |key, count|
  puts "  #{key}: #{count} occurrences"
end

# Focus on specific data types
api_data = []
chunks.each do |chunk|
  chunk[:extracted_data].each do |item|
    if item[:type] == 'colon_separated' && item[:identifier]&.downcase&.include?('api')
      api_data << item[:data]
    end
  end
end

puts "Found #{api_data.length} API data chunks"
```

## API Reference

### `NextjsHydrationParser::Extractor`

The main class for extracting Next.js hydration data.

#### Methods

- **`parse(html_content) -> Array<Hash>`**

  Parse Next.js hydration data from HTML content.
  - `html_content`: Raw HTML string containing script tags
  - Returns: Array of parsed data chunks

- **`get_all_keys(parsed_chunks, max_depth: 3) -> Hash`**

  Extract all unique keys from parsed chunks.
  - `parsed_chunks`: Output from `parse()` method
  - `max_depth`: Maximum depth to traverse (default: 3)
  - Returns: Hash of keys and their occurrence counts

- **`find_data_by_pattern(parsed_chunks, pattern) -> Array`**

  Find data matching a specific pattern.
  - `parsed_chunks`: Output from `parse()` method
  - `pattern`: Key pattern to search for
  - Returns: Array of matching data items

## Data Structure

The parser returns data in the following structure:

```ruby
[
  {
    chunk_id: "1",  # ID from self.__next_f.push([ID, data])
    extracted_data: [
      {
        type: "colon_separated|standalone_json|whole_text",
        data: {...},  # Parsed JavaScript/JSON object
        identifier: "...",  # For colon_separated type
        start_position: 123  # For standalone_json type
      }
    ],
    chunk_count: 1,  # Number of chunks with this ID
    _positions: [123]  # Original positions in HTML
  }
]
```

## Supported Data Formats

The parser handles various data formats commonly found in Next.js 13+ hydration chunks:

### 1. JSON Strings

```javascript
self.__next_f.push([1, '{"products":[{"id":1,"name":"Laptop","price":999}]}']);
```

### 2. Base64 + JSON Combinations

```javascript
self.__next_f.push([
  2,
  'eyJhcGlLZXkiOiJ4eXoifQ==:{"data":{"users":[{"id":1}]}}',
]);
```

### 3. JavaScript Objects

```javascript
self.__next_f.push([
  3,
  "{key: 'value', items: [1, 2, 3], nested: {deep: true}}",
]);
```

### 4. Escaped Content

```javascript
self.__next_f.push([4, '"escaped content with \\"quotes\\" and newlines\\n"']);
```

### 5. Multi-chunk Data

```javascript
// Data split across multiple chunks with same ID
self.__next_f.push([5, "first part of data"]);
self.__next_f.push([5, " continued here"]);
self.__next_f.push([5, " and final part"]);
```

### 6. Complex Nested Structures

Next.js often embeds API responses, page props, and component data in deeply nested formats that the parser can extract and flatten for easy access.

## How Next.js 13+ Hydration Works

Understanding the hydration process helps explain why this library is necessary:

1. **Server-Side Rendering**: Next.js renders your page on the server, generating static HTML
2. **Data Embedding**: Instead of making separate API calls, Next.js may embeds the data directly in the HTML using `self.__next_f.push()` calls
3. **Chunk Splitting**: Large data sets are split across multiple chunks to optimize loading
4. **Client Hydration**: When JavaScript loads, these chunks are reassembled and used to hydrate React components

When scraping, you're intercepting step 2 - getting the raw HTML with embedded data before the JavaScript processes it. This gives you access to all the data the application uses, but in a fragmented format that needs intelligent parsing.

**Why not just use the rendered page?**

- Faster scraping (no JavaScript execution wait time)
- Access to internal data structures not visible in the DOM
- Bypasses client-side anti-scraping measures
- Gets raw API responses before component filtering/transformation

## Error Handling

The parser includes robust error handling:

- **Malformed data**: Continues processing and marks chunks with errors
- **Multiple parsing strategies**: Falls back to alternative parsing methods
- **Partial data**: Handles incomplete or truncated data gracefully
