# frozen_string_literal: true

require 'chompjs'
require 'json'
require 'logger'

module NextjsHydrationParser
  # A class for extracting and parsing Next.js hydration data from HTML content.
  #
  # This class provides methods to parse self.__next_f.push calls and extract
  # structured data from Next.js hydration scripts.
  class Extractor
    attr_reader :script_pattern, :logger

    def initialize
      @script_pattern = /self\.__next_f\.push\(\[(.*?)\]\)/m
      @logger = Logger.new($stdout)
      @logger.level = Logger::WARN
    end

    # Parse Next.js/Nuxt.js hydration data from script tags containing self.__next_f.push calls.
    # Returns an array of parsed data chunks, preserving all available information.
    #
    # @param html_content [String] Raw HTML content containing script tags
    # @return [Array<Hash>] Array of parsed data chunks
    def parse(html_content)
      # Find all script matches with their positions
      raw_chunks = []
      html_content.scan(@script_pattern) do |match|
        chunk_content = match[0]
        position = Regexp.last_match.begin(0)

        begin
          # Parse the chunk content more carefully
          parsed_chunk = parse_single_chunk(chunk_content)
          if parsed_chunk
            parsed_chunk[:_position] = position
            raw_chunks << parsed_chunk
          end
        rescue StandardError => e
          @logger.debug("Error parsing chunk at position #{position}: #{e}")
          # Still add raw content for debugging
          raw_chunks << {
            chunk_id: 'error',
            raw_content: chunk_content,
            _position: position,
            _error: e.message
          }
        end
      end

      # Sort by position to maintain order
      raw_chunks.sort_by! { |x| x[:_position] }

      # Group chunks and handle continuations
      process_chunks(raw_chunks)
    end

    # Parse a single chunk content from self.__next_f.push([chunk_id, data]).
    #
    # @param content [String] The content inside the brackets
    # @return [Hash, nil] Parsed chunk or nil if parsing fails
    def parse_single_chunk(content)
      content = content.strip

      # Try multiple parsing strategies

      # Strategy 1: Use chompjs to parse as array
      begin
        parsed_array = Chompjs.parse("[#{content}]")
        if parsed_array.length >= 2
          chunk_id = parsed_array[0]
          chunk_data = parsed_array[1].to_s
          return {
            chunk_id: chunk_id,
            raw_data: chunk_data,
            parsed_data: nil # Will be filled later
          }
        end
      rescue StandardError
        # Continue to next strategy
      end

      # Strategy 2: Manual parsing - find first comma outside quotes
      comma_pos = find_separator_comma(content)
      if comma_pos != -1
        chunk_id_part = content[0...comma_pos].strip
        data_part = content[(comma_pos + 1)..].strip

        # Parse chunk_id
        begin
          chunk_id = Chompjs.parse(chunk_id_part)
        rescue StandardError
          chunk_id = chunk_id_part.gsub(/^["']|["']$/, '')
        end

        # Clean data part (remove surrounding quotes and unescape)
        if data_part.start_with?('"') && data_part.end_with?('"')
          data_part = data_part[1..-2]
          data_part = data_part.gsub('\\"', '"').gsub('\\\\', '\\')
        end

        return { chunk_id: chunk_id, raw_data: data_part, parsed_data: nil }
      end

      # Strategy 3: Treat entire content as data with unknown ID
      { chunk_id: 'unknown', raw_data: content, parsed_data: nil }
    end

    # Process raw chunks, combining continuations and extracting JSON data.
    #
    # @param raw_chunks [Array<Hash>] Array of raw parsed chunks
    # @return [Array<Hash>] Array of processed data chunks
    def process_chunks(raw_chunks)
      # Group chunks by ID first
      chunks_by_id = raw_chunks.group_by { |chunk| chunk[:chunk_id] }

      # Process each group
      result = []

      chunks_by_id.each do |chunk_id, chunk_list|
        # Sort by position to maintain order
        chunk_list.sort_by! { |x| x[:_position] }

        # Combine all data for this chunk_id
        combined_data = chunk_list.map { |chunk| chunk[:raw_data] }.join

        # Try to extract structured data
        extracted_items = extract_all_data_structures(combined_data)

        processed_chunk = {
          chunk_id: chunk_id,
          extracted_data: extracted_items,
          chunk_count: chunk_list.length,
          _positions: chunk_list.map { |chunk| chunk[:_position] }
        }

        result << processed_chunk
      end

      result
    end

    # Extract all possible data structures from a text string.
    # Handles various patterns like base64:json, plain json, etc.
    #
    # @param text [String] Text to parse
    # @return [Array<Hash>] Array of extracted data structures
    def extract_all_data_structures(text)
      extracted = []

      return extracted if text.nil? || text.strip.empty?

      # Pattern 1: Look for base64_id:json_content patterns
      text.scan(/([^:]*):(\{.*)/) do
        identifier = Regexp.last_match(1).strip
        json_part = Regexp.last_match(2)

        # Try to extract complete JSON from this position
        complete_json = extract_complete_json(json_part)
        if complete_json
          parsed_json = parse_js_object(complete_json)
          if parsed_json
            extracted << {
              type: 'colon_separated',
              identifier: identifier,
              data: parsed_json,
              raw_json: complete_json
            }
          end
        end
      end

      # Pattern 2: Look for standalone JSON objects/arrays
      json_starts = []
      text.scan(/[{\[]/).each do
        json_starts << Regexp.last_match.begin(0)
      end

      json_starts.each do |start_pos|
        substring = text[start_pos..]
        complete_json = extract_complete_json(substring)

        # check if complete_json was not extracted already
        next if complete_json && extracted.any? { |item| item[:raw_json]&.include?(complete_json) }

        next unless complete_json && complete_json.length > 10 # Skip very small objects

        parsed_json = parse_js_object(complete_json)
        # Avoid duplicates
        next unless parsed_json && !extracted.any? { |item| item[:raw_json] == complete_json }

        extracted << {
          type: 'standalone_json',
          data: parsed_json,
          raw_json: complete_json,
          start_position: start_pos
        }
      end

      # Pattern 3: Try parsing the entire text as JSON
      if extracted.empty?
        parsed_whole = parse_js_object(text)
        if parsed_whole
          extracted << {
            type: 'whole_text',
            data: parsed_whole,
            raw_json: text
          }
        end
      end

      # Remove raw_json from the final output
      extracted.each do |item|
        item.delete(:raw_json)
      end

      extracted
    end

    # Parse JavaScript object/JSON from text using multiple strategies.
    #
    # @param text [String] String containing JavaScript object or JSON
    # @return [Object, nil] Parsed object or nil if parsing fails
    def parse_js_object(text)
      return nil if text.nil? || text.strip.empty?

      text = text.strip

      # Strategy 1: Try chompjs (best for JS objects)
      begin
        return Chompjs.parse(text)
      rescue StandardError
        # Continue to next strategy
      end

      # Strategy 2: Try standard JSON
      begin
        return JSON.parse(text)
      rescue StandardError
        # Continue to next strategy
      end

      # Strategy 3: Clean up and try again
      begin
        cleaned = clean_js_object(text)
        return Chompjs.parse(cleaned)
      rescue StandardError
        # Continue to next strategy
      end

      begin
        cleaned = clean_js_object(text)
        return JSON.parse(cleaned)
      rescue StandardError
        # Failed all strategies
      end

      nil
    end

    # Clean up common JavaScript object issues for JSON parsing.
    #
    # @param text [String] Raw JavaScript object string
    # @return [String] Cleaned string
    def clean_js_object(text)
      # Remove trailing commas before closing braces/brackets
      text = text.gsub(/,(\s*[}\]])/, '\1')

      # Remove JavaScript comments
      text = text.gsub(%r{//.*?$}, '')
      text = text.gsub(%r{/\*.*?\*/}m, '')

      text.strip
    end

    # Extract a complete JSON object or array from the beginning of a string.
    #
    # @param text [String] String starting with JSON
    # @return [String, nil] Complete JSON string or nil if not found
    def extract_complete_json(text)
      return nil if text.nil?

      # Find the actual start of JSON (skip whitespace)
      start_idx = 0
      start_idx += 1 while start_idx < text.length && text[start_idx].match?(/\s/)

      return nil if start_idx >= text.length

      first_char = text[start_idx]
      if first_char == '{'
        open_char = '{'
        close_char = '}'
      elsif first_char == '['
        open_char = '['
        close_char = ']'
      else
        return nil
      end

      count = 0
      in_string = false
      escape_next = false

      (start_idx...text.length).each do |i|
        char = text[i]

        if escape_next
          escape_next = false
          next
        end

        if char == '\\' && in_string
          escape_next = true
          next
        end

        if char == '"' && !escape_next
          in_string = !in_string
          next
        end

        unless in_string
          if char == open_char
            count += 1
          elsif char == close_char
            count -= 1

            return text[start_idx..i] if count == 0
          end
        end
      end

      nil
    end

    # Find the comma that separates chunk_id from chunk_data.
    #
    # @param text [String] Text to search
    # @return [Integer] Position of separator comma, or -1 if not found
    def find_separator_comma(text)
      in_quotes = false
      quote_char = nil
      escape_next = false
      paren_count = 0
      bracket_count = 0
      brace_count = 0

      text.each_char.with_index do |char, i|
        if escape_next
          escape_next = false
          next
        end

        if char == '\\'
          escape_next = true
          next
        end

        if ['"', "'"].include?(char)
          if !in_quotes
            in_quotes = true
            quote_char = char
          elsif char == quote_char
            in_quotes = false
            quote_char = nil
          end
          next
        end

        unless in_quotes
          case char
          when '('
            paren_count += 1
          when ')'
            paren_count -= 1
          when '['
            bracket_count += 1
          when ']'
            bracket_count -= 1
          when '{'
            brace_count += 1
          when '}'
            brace_count -= 1
          when ','
            return i if paren_count == 0 && bracket_count == 0 && brace_count == 0
          end
        end
      end

      -1
    end

    # Get all unique keys from the parsed chunks.
    #
    # @param parsed_chunks [Array<Hash>] Output from parse method
    # @param max_depth [Integer] Maximum depth to traverse when collecting keys
    # @return [Hash] Dictionary of keys and their occurrence count
    def get_all_keys(parsed_chunks, max_depth: 3)
      key_counts = {}

      collect_keys = lambda do |obj, depth = 0|
        return if depth > max_depth

        if obj.is_a?(Hash)
          obj.each do |key, value|
            next if key.to_s.start_with?('_') # Skip internal keys

            key_str = key.to_s
            key_counts[key_str] = key_counts.fetch(key_str, 0) + 1
            collect_keys.call(value, depth + 1)
          end
        elsif obj.is_a?(Array)
          obj.each do |item|
            collect_keys.call(item, depth + 1)
          end
        end
      end

      parsed_chunks.each do |chunk|
        next unless chunk[:extracted_data]

        chunk[:extracted_data].each do |extracted_item|
          collect_keys.call(extracted_item[:data]) if extracted_item[:data]
        end
      end

      key_counts.sort_by { |_k, v| -v }.to_h
    end

    # Find data that matches a specific pattern.
    #
    # @param parsed_chunks [Array<Hash>] Output from parse method
    # @param pattern [String] Key pattern to search for
    # @return [Array] Array of matching data items
    def find_data_by_pattern(parsed_chunks, pattern)
      results = []

      search_recursive = lambda do |obj, path = ''|
        if obj.is_a?(Hash)
          obj.each do |key, value|
            current_path = path.empty? ? key.to_s : "#{path}.#{key}"

            if key.to_s.downcase.include?(pattern.downcase)
              results << {
                path: current_path,
                key: key.to_s,
                value: value
              }
            end

            search_recursive.call(value, current_path)
          end
        elsif obj.is_a?(Array)
          obj.each_with_index do |item, i|
            current_path = "#{path}[#{i}]"
            search_recursive.call(item, current_path)
          end
        end
      end

      parsed_chunks.each do |chunk|
        next unless chunk[:extracted_data]

        chunk[:extracted_data].each do |extracted_item|
          next unless extracted_item[:data]

          search_recursive.call(
            extracted_item[:data],
            "chunk_#{chunk[:chunk_id]}"
          )
        end
      end

      results
    end
  end
end
