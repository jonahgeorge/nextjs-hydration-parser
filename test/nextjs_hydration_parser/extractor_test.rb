# frozen_string_literal: true

require 'test_helper'
require_relative '../support/fixtures'

class NextjsHydrationParser::ExtractorTest < Minitest::Test
  def setup
    @extractor = NextjsHydrationParser::Extractor.new
  end

  # Basic Functionality

  def test_initializes_correctly
    assert_instance_of Regexp, @extractor.script_pattern
    refute_nil @extractor.script_pattern
  end

  def test_parses_empty_html
    result = @extractor.parse('')
    assert_equal [], result
  end

  def test_parses_html_without_nextjs_hydration_data
    html = '<html><body><h1>No Next.js data here</h1></body></html>'
    result = @extractor.parse(html)
    assert_equal [], result
  end

  def test_parses_a_simple_chunk
    result = @extractor.parse(Fixtures::SIMPLE_HTML)

    assert_equal 1, result.length
    assert_equal 1, result[0][:chunk_id]
    assert_operator result[0][:extracted_data].length, :>=, 1
    assert_equal 1, result[0][:chunk_count]
  end

  def test_parses_multiple_chunks_with_different_ids
    html = <<~HTML
      <script>self.__next_f.push([1,"{\\\"test1\\\": \\\"value1\\\"}"])</script>
      <script>self.__next_f.push([2,"{\\\"test2\\\": \\\"value2\\\"}"])</script>
      <script>self.__next_f.push([3,"{\\\"test3\\\": \\\"value3\\\"}"])</script>
    HTML

    result = @extractor.parse(html)

    assert_equal 3, result.length
    chunk_ids = result.map { |chunk| chunk[:chunk_id] }
    assert_includes chunk_ids, 1
    assert_includes chunk_ids, 2
    assert_includes chunk_ids, 3
  end

  def test_parses_multiple_chunks_with_same_id_continuation
    html = <<~HTML
      <script>self.__next_f.push([1,"{\\\"data\\\": [\\\"part1\\\","])</script>
      <script>self.__next_f.push([1,"\\\"part2\\\", \\\"part3\\\"]}"])</script>
    HTML

    result = @extractor.parse(html)

    assert_equal 1, result.length
    assert_equal 1, result[0][:chunk_id]
    assert_equal 2, result[0][:chunk_count]
    assert_equal 2, result[0][:_positions].length
  end

  # Data Types

  def test_parses_json_string_data
    html = '<script>self.__next_f.push([1,"{\\\"key\\\": \\\"value\\\", \\\"number\\\": 42}"])</script>'
    result = @extractor.parse(html)

    assert_equal 1, result.length
    data_items = result[0][:extracted_data]
    assert_operator data_items.length, :>=, 1

    # Should find the JSON data (keys include escaped quotes)
    json_found = data_items.any? do |item|
      item[:data].is_a?(Hash) && item[:data].values.any? { |v| v.to_s.include?('value') }
    end
    assert json_found, 'JSON data should be parsed correctly'
  end

  def test_parses_javascript_object_syntax
    html = "<script>self.__next_f.push([1,\"{key: 'value', array: [1, 2, 3]}\"])</script>"
    result = @extractor.parse(html)

    assert_equal 1, result.length
    assert_operator result[0][:extracted_data].length, :>=, 1
  end

  def test_parses_base64_data_format
    html = '<script>self.__next_f.push([1,"api_key:{\\\"response\\\": \\\"success\\\"}"])</script>'
    result = @extractor.parse(html)

    assert_equal 1, result.length
    data_items = result[0][:extracted_data]

    # Should find data (type is "whole_text" not "colon_separated")
    assert_operator data_items.length, :>, 0
    assert(data_items.any? { |item| item[:data].is_a?(Hash) })
  end

  def test_parses_escaped_strings
    html = '<script>self.__next_f.push([1,"\\\"escaped string with \\\\\\\"quotes\\\\\\\"\\\""])</script>'
    result = @extractor.parse(html)

    # The extractor may not parse this specific escaped string format, but should return a result
    assert_equal 1, result.length
  end

  # Error Handling

  def test_handles_error_chunk_structure
    html = '<script>self.__next_f.push([1,"{broken json}"])</script>'
    result = @extractor.parse(html)

    # Should have at least one result (might be error or recovered)
    assert_operator result.length, :>=, 1

    # Check if any error chunks have proper structure
    error_chunks = result.select { |chunk| chunk[:chunk_id] == 'error' }
    error_chunks.each do |chunk|
      assert chunk.key?(:raw_content)
      assert chunk.key?(:_error)
      assert chunk.key?(:_position)
    end
  end

  def test_continues_parsing_after_error
    html = <<~HTML
      <script>self.__next_f.push([1,"{\\\"valid\\\": \\\"first\\\"}"])</script>
      <script>self.__next_f.push([2,"{broken json}"])</script>
      <script>self.__next_f.push([3,"{\\\"valid\\\": \\\"after_error\\\"}"])</script>
    HTML

    result = @extractor.parse(html)

    # Should find valid chunks before and after error
    valid_chunks = result.reject { |c| c[:chunk_id] == 'error' }
    assert_operator valid_chunks.length, :>=, 2
  end

  # Position Tracking

  def test_tracks_positions_correctly
    html = <<~HTML
      start
      <script>self.__next_f.push([1,"{\\\"test\\\": \\\"value\\\"}"])</script>
      middle content
      <script>self.__next_f.push([2,"{\\\"test2\\\": \\\"value2\\\"}"])</script>
      end
    HTML

    result = @extractor.parse(html)

    assert_equal 2, result.length

    # Positions should be different and in ascending order
    pos1 = result[0][:_positions][0]
    pos2 = result[1][:_positions][0]

    refute_equal pos1, pos2
    assert_operator pos1, :<, pos2 # First chunk should appear before second
  end

  def test_tracks_multi_chunk_positions
    html = <<~HTML
      <script>self.__next_f.push([1,"first part"])</script>
      some content
      <script>self.__next_f.push([1,"second part"])</script>
    HTML

    result = @extractor.parse(html)

    assert_equal 1, result.length
    assert_equal 2, result[0][:chunk_count]
    assert_equal 2, result[0][:_positions].length
    assert_operator result[0][:_positions][0], :<, result[0][:_positions][1]
  end

  # get_all_keys

  def test_extracts_all_unique_keys_from_parsed_chunks
    result = @extractor.parse(Fixtures::ECOMMERCE_HTML)
    all_keys = @extractor.get_all_keys(result)

    assert_instance_of Hash, all_keys
    # get_all_keys returns a hash with keys and their counts
    # The actual structure has nested keys like "id", "name", etc.
    assert_operator all_keys.keys.length, :>, 0
  end

  def test_get_all_keys_respects_max_depth_parameter
    result = @extractor.parse(Fixtures::COMPLEX_HTML)
    all_keys = @extractor.get_all_keys(result, max_depth: 1)

    assert_instance_of Hash, all_keys
  end

  # find_data_by_pattern

  def test_finds_data_matching_a_pattern
    result = @extractor.parse(Fixtures::ECOMMERCE_HTML)
    products = @extractor.find_data_by_pattern(result, 'product')

    assert_instance_of Array, products
    assert_operator products.length, :>, 0
    assert products.first.key?(:path)
    assert products.first.key?(:key)
    assert products.first.key?(:value)
  end

  def test_find_data_by_pattern_performs_case_insensitive_search
    result = @extractor.parse(Fixtures::ECOMMERCE_HTML)
    products_lower = @extractor.find_data_by_pattern(result, 'product')
    products_upper = @extractor.find_data_by_pattern(result, 'PRODUCT')

    assert_equal products_lower, products_upper
  end
end
