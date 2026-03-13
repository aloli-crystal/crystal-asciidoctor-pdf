require "xml"
require "./spec_helper"

# Test helper methods ported from Ruby Asciidoctor test_helper.rb
module TestHelpers
  BACKSLASH = "\\"
  SAMPLE_DATA = ["first line", "second line", "third line"]

  # Parse the source string into a Document.
  def self.document_from_string(src : String, opts : Hash(String, String) = {} of String => String) : Asciidoctor::Document
    opts["standalone"] = "false" unless opts.has_key?("standalone")
    Asciidoctor.load(src, opts)
  end

  # Parse the source string into a Document (with nullable values).
  # nil values are treated as attribute deletions (equivalent to !key)
  def self.document_from_string(src : String, opts : Hash(String, String?)) : Asciidoctor::Document
    normalized = {} of String => String
    opts.each do |k, v|
      if v.nil?
        # nil value means delete the attribute (equivalent to !key)
        normalized["!#{k}"] = ""
      else
        normalized[k] = v
      end
    end
    normalized["standalone"] = "false" unless normalized.has_key?("standalone")
    Asciidoctor.load(src, normalized)
  end

  # Parse the source string into a Document and return the first block.
  def self.block_from_string(src : String, opts : Hash(String, String) = {} of String => String) : Asciidoctor::Block
    opts["standalone"] = "false"
    doc = Asciidoctor.load(src, opts)
    doc.blocks.first.as(Asciidoctor::Block)
  end

  # Parse and convert the source string.
  def self.convert_string(src : String, opts : Hash(String, String) = {} of String => String) : String
    opts["standalone"] = "true" unless opts.has_key?("standalone")
    doc = Asciidoctor.load(src, opts)
    converter = doc.converter || Asciidoctor::Converter::Html5Converter.new("html5")
    result = converter.convert(doc)
    # Remove xmlns attributes to avoid confusing XML parser
    result.gsub(/\s+xmlns(:\w+)?="[^"]*"/, "")
  end

  # Parse and convert the source string to embedded output (no header/footer).
  def self.convert_string_to_embedded(src : String, opts : Hash(String, String) = {} of String => String) : String
    opts["standalone"] = "false"
    doc = Asciidoctor.load(src, opts)
    converter = doc.converter || Asciidoctor::Converter::Html5Converter.new("html5")
    converter.convert(doc)
  end

  # Parse and convert the source string as inline doctype.
  def self.convert_inline_string(src : String, opts : Hash(String, String) = {} of String => String) : String
    opts["doctype"] = "inline"
    doc = Asciidoctor.load(src, opts)
    converter = doc.converter || Asciidoctor::Converter::Html5Converter.new("html5")
    converter.convert(doc)
  end

  # Create an empty document.
  def self.empty_document(opts : Hash(String, String) = {} of String => String) : Asciidoctor::Document
    Asciidoctor.load("", opts.merge({"parse" => "false"}))
  end

  # Count XPath matches in HTML/XML content.
  def self.xpath_count(xpath : String, content : String) : Int32
    # Wrap content in a root element if it's a fragment
    wrapped = if content.starts_with?("<?xml") || content.starts_with?("<!DOCTYPE") || content.starts_with?("<html")
                content
              else
                "<div>#{content}</div>"
              end
    begin
      doc = XML.parse_html(wrapped)
      nodes = doc.xpath_nodes(xpath)
      nodes.size
    rescue
      0
    end
  end

  # Assert XPath matches a specific count in content.
  def self.assert_xpath_count(xpath : String, content : String, expected_count : Int32) : Bool
    actual = xpath_count(xpath, content)
    actual == expected_count
  end

  # Check if content includes a substring.
  def self.includes?(content : String, expected : String) : Bool
    content.includes?(expected)
  end

  # Decode a Unicode character from its codepoint.
  def self.decode_char(codepoint : Int32) : String
    codepoint.chr.to_s
  end
end
