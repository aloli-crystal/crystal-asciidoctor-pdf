require "../spec_helper"

describe Asciidoctor::Parser do
  describe ".adjust_indentation!" do
    it "removes common leading whitespace" do
      lines = ["  line 1", "  line 2", "  line 3"]
      Asciidoctor::Parser.adjust_indentation!(lines)
      lines.should eq(["line 1", "line 2", "line 3"])
    end

    it "handles mixed indentation levels" do
      lines = ["    line 1", "  line 2", "      line 3"]
      Asciidoctor::Parser.adjust_indentation!(lines)
      lines.should eq(["  line 1", "line 2", "    line 3"])
    end

    it "preserves empty lines" do
      lines = ["  line 1", "", "  line 2"]
      Asciidoctor::Parser.adjust_indentation!(lines)
      lines.should eq(["line 1", "", "line 2"])
    end

    it "does nothing when no common indent" do
      lines = ["line 1", "  line 2"]
      Asciidoctor::Parser.adjust_indentation!(lines)
      lines.should eq(["line 1", "  line 2"])
    end

    it "does nothing on empty array" do
      lines = [] of String
      Asciidoctor::Parser.adjust_indentation!(lines)
      lines.should be_empty
    end
  end

  describe ".atx_section_title?" do
    it "detects level 0 section title" do
      Asciidoctor::Parser.atx_section_title?("= Title").should eq(0)
    end

    it "detects level 1 section title" do
      Asciidoctor::Parser.atx_section_title?("== Section").should eq(1)
    end

    it "detects level 2 section title" do
      Asciidoctor::Parser.atx_section_title?("=== Subsection").should eq(2)
    end

    it "detects level 3 section title" do
      Asciidoctor::Parser.atx_section_title?("==== Level 3").should eq(3)
    end

    it "detects level 4 section title" do
      Asciidoctor::Parser.atx_section_title?("===== Level 4").should eq(4)
    end

    it "returns nil for non-section lines" do
      Asciidoctor::Parser.atx_section_title?("just a line").should be_nil
    end

    it "returns nil for line starting with = but no space" do
      Asciidoctor::Parser.atx_section_title?("=nospace").should be_nil
    end

    it "detects markdown-style section title" do
      Asciidoctor::Parser.atx_section_title?("# Title").should eq(0)
    end

    it "detects markdown-style level 2" do
      Asciidoctor::Parser.atx_section_title?("## Section").should eq(1)
    end
  end

  describe ".is_delimited_block?" do
    it "detects listing block" do
      result = Asciidoctor::Parser.is_delimited_block?("----", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:listing)
    end

    it "detects example block" do
      result = Asciidoctor::Parser.is_delimited_block?("====", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:example)
    end

    it "detects sidebar block" do
      result = Asciidoctor::Parser.is_delimited_block?("****", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:sidebar)
    end

    it "detects open block" do
      result = Asciidoctor::Parser.is_delimited_block?("--", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:open)
    end

    it "detects literal block" do
      result = Asciidoctor::Parser.is_delimited_block?("....", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:literal)
    end

    it "detects comment block" do
      result = Asciidoctor::Parser.is_delimited_block?("////", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:comment)
    end

    it "detects pass block" do
      result = Asciidoctor::Parser.is_delimited_block?("++++", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:pass)
    end

    it "detects fenced code block" do
      result = Asciidoctor::Parser.is_delimited_block?("```", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:fenced_code)
    end

    it "detects longer delimited blocks" do
      result = Asciidoctor::Parser.is_delimited_block?("------", true)
      result.should_not be_nil
      result.not_nil!.context.should eq(:listing)
    end

    it "returns nil for non-delimited lines" do
      Asciidoctor::Parser.is_delimited_block?("just a line", true).should be_nil
    end

    it "returns nil for short lines" do
      Asciidoctor::Parser.is_delimited_block?("-", true).should be_nil
    end

    it "returns nil for 3-char non-fence delimiters" do
      Asciidoctor::Parser.is_delimited_block?("---", true).should be_nil
    end
  end

  describe ".is_section_title?" do
    it "detects atx section title" do
      Asciidoctor::Parser.is_section_title?("== Title").should eq(1)
    end

    it "returns nil for non-section lines" do
      Asciidoctor::Parser.is_section_title?("just a line").should be_nil
    end
  end

  describe ".parse_block_attribute_list" do
    it "parses a simple style" do
      attrs = {} of String => String
      Asciidoctor::Parser.parse_block_attribute_list("source", attrs)
      attrs["1"].should eq("source")
    end

    it "parses key=value pairs" do
      attrs = {} of String => String
      Asciidoctor::Parser.parse_block_attribute_list("source,ruby", attrs)
      attrs["1"].should eq("source")
      attrs["2"].should eq("ruby")
    end

    it "parses named attributes" do
      attrs = {} of String => String
      Asciidoctor::Parser.parse_block_attribute_list("role=lead", attrs)
      attrs["role"].should eq("lead")
    end

    it "parses shorthand id" do
      attrs = {} of String => String
      Asciidoctor::Parser.parse_block_attribute_list("source#myid", attrs)
      attrs["style"].should eq("source")
      attrs["id"].should eq("myid")
    end

    it "parses shorthand role" do
      attrs = {} of String => String
      Asciidoctor::Parser.parse_block_attribute_list("source.myrole", attrs)
      attrs["style"].should eq("source")
      attrs["role"].should eq("myrole")
    end

    it "parses shorthand option" do
      attrs = {} of String => String
      Asciidoctor::Parser.parse_block_attribute_list("source%nowrap", attrs)
      attrs["style"].should eq("source")
      attrs["nowrap-option"].should eq("")
    end
  end

  describe ".parse_block_metadata_line" do
    it "parses a block anchor" do
      reader = Asciidoctor::Reader.new(["[[myid]]", "content"])
      doc = Asciidoctor::Document.new
      attrs = {} of String => String
      result = Asciidoctor::Parser.parse_block_metadata_line(reader, doc, attrs)
      result.should be_true
      attrs["id"].should eq("myid")
    end

    it "parses a block title" do
      reader = Asciidoctor::Reader.new([".My Title", "content"])
      doc = Asciidoctor::Document.new
      attrs = {} of String => String
      result = Asciidoctor::Parser.parse_block_metadata_line(reader, doc, attrs)
      result.should be_true
      attrs["title"].should eq("My Title")
    end

    it "skips single-line comments" do
      reader = Asciidoctor::Reader.new(["// comment", "content"])
      doc = Asciidoctor::Document.new
      attrs = {} of String => String
      result = Asciidoctor::Parser.parse_block_metadata_line(reader, doc, attrs)
      result.should be_true
    end

    it "returns false for regular content" do
      reader = Asciidoctor::Reader.new(["just content"])
      doc = Asciidoctor::Document.new
      attrs = {} of String => String
      result = Asciidoctor::Parser.parse_block_metadata_line(reader, doc, attrs)
      result.should be_false
    end
  end

  describe ".parse_section_title" do
    it "parses an atx section title" do
      reader = Asciidoctor::Reader.new(["== My Section", "content"])
      doc = Asciidoctor::Document.new
      id, reftext, title, level, atx = Asciidoctor::Parser.parse_section_title(reader, doc)
      title.should eq("My Section")
      level.should eq(1)
      atx.should be_true
    end

    it "parses a level 0 title" do
      reader = Asciidoctor::Reader.new(["= Document Title", "content"])
      doc = Asciidoctor::Document.new
      id, reftext, title, level, atx = Asciidoctor::Parser.parse_section_title(reader, doc)
      title.should eq("Document Title")
      level.should eq(0)
      atx.should be_true
    end

    it "parses a level 3 title" do
      reader = Asciidoctor::Reader.new(["==== Deep Section", "content"])
      doc = Asciidoctor::Document.new
      id, reftext, title, level, atx = Asciidoctor::Parser.parse_section_title(reader, doc)
      title.should eq("Deep Section")
      level.should eq(3)
    end

    it "applies leveloffset" do
      reader = Asciidoctor::Reader.new(["== My Section", "content"])
      doc = Asciidoctor::Document.new
      doc.attributes["leveloffset"] = "1"
      id, reftext, title, level, atx = Asciidoctor::Parser.parse_section_title(reader, doc)
      level.should eq(2)
    end
  end

  describe ".process_authors" do
    it "parses a single author" do
      metadata = Asciidoctor::Parser.process_authors("John Doe")
      metadata["author"].should eq("John Doe")
      metadata["firstname"].should eq("John")
      metadata["lastname"].should eq("Doe")
      metadata["authorinitials"].should eq("JD")
      metadata["authorcount"].should eq("1")
    end

    it "parses an author with middle name" do
      metadata = Asciidoctor::Parser.process_authors("John Michael Doe")
      metadata["author"].should eq("John Michael Doe")
      metadata["firstname"].should eq("John")
      metadata["middlename"].should eq("Michael")
      metadata["lastname"].should eq("Doe")
      metadata["authorinitials"].should eq("JMD")
    end

    it "parses a single-name author" do
      metadata = Asciidoctor::Parser.process_authors("John")
      metadata["author"].should eq("John")
      metadata["firstname"].should eq("John")
      metadata["authorinitials"].should eq("J")
    end

    it "parses multiple authors separated by semicolons" do
      metadata = Asciidoctor::Parser.process_authors("John Doe; Jane Smith")
      metadata["authorcount"].should eq("2")
      metadata["author"].should eq("John Doe")
      metadata["author_2"].should eq("Jane Smith")
      metadata["authors"].should eq("John Doe, Jane Smith")
    end

    it "handles underscores in names" do
      metadata = Asciidoctor::Parser.process_authors("John_Michael Doe")
      metadata["firstname"].should eq("John Michael")
    end
  end

  describe ".resolve_ordered_list_marker" do
    it "resolves dot markers" do
      marker, style = Asciidoctor::Parser.resolve_ordered_list_marker(".")
      marker.should eq(".")
      style.should be_nil
    end

    it "resolves numeric markers" do
      marker, style = Asciidoctor::Parser.resolve_ordered_list_marker("1.")
      marker.should eq("1.")
      style.should eq(:arabic)
    end

    it "resolves lowercase alpha markers" do
      marker, style = Asciidoctor::Parser.resolve_ordered_list_marker("a.")
      marker.should eq("a.")
      style.should eq(:loweralpha)
    end

    it "resolves uppercase alpha markers" do
      marker, style = Asciidoctor::Parser.resolve_ordered_list_marker("A.")
      marker.should eq("A.")
      style.should eq(:upperalpha)
    end
  end

  describe ".sanitize_attribute_name" do
    it "lowercases the name" do
      Asciidoctor::Parser.sanitize_attribute_name("MyAttr").should eq("myattr")
    end

    it "removes invalid characters" do
      Asciidoctor::Parser.sanitize_attribute_name("my attr!").should eq("myattr")
    end
  end

  describe ".store_attribute" do
    it "stores an attribute in the document" do
      doc = Asciidoctor::Document.new
      Asciidoctor::Parser.store_attribute("myattr", "myvalue", doc)
      doc.attributes["myattr"].should eq("myvalue")
    end

    it "unsets an attribute with trailing bang" do
      doc = Asciidoctor::Document.new
      doc.attributes["myattr"] = "value"
      Asciidoctor::Parser.store_attribute("myattr!", "", doc)
      doc.attributes.has_key?("myattr").should be_false
    end

    it "unsets an attribute with leading bang" do
      doc = Asciidoctor::Document.new
      doc.attributes["myattr"] = "value"
      Asciidoctor::Parser.store_attribute("!myattr", "", doc)
      doc.attributes.has_key?("myattr").should be_false
    end

    it "resolves numbered to sectnums" do
      doc = Asciidoctor::Document.new
      Asciidoctor::Parser.store_attribute("numbered", "", doc)
      doc.attributes.has_key?("sectnums").should be_true
    end

    it "handles relative leveloffset with +" do
      doc = Asciidoctor::Document.new
      doc.attributes["leveloffset"] = "1"
      Asciidoctor::Parser.store_attribute("leveloffset", "+2", doc)
      doc.attributes["leveloffset"].should eq("3")
    end

    it "handles relative leveloffset with -" do
      doc = Asciidoctor::Document.new
      doc.attributes["leveloffset"] = "3"
      Asciidoctor::Parser.store_attribute("leveloffset", "-1", doc)
      doc.attributes["leveloffset"].should eq("2")
    end
  end

  describe ".uniform?" do
    it "returns true for uniform string" do
      Asciidoctor::Parser.uniform?("====", "=", 4).should be_true
    end

    it "returns false for non-uniform string" do
      Asciidoctor::Parser.uniform?("==-=", "=", 4).should be_false
    end

    it "returns false for empty string" do
      Asciidoctor::Parser.uniform?("", "=", 0).should be_false
    end
  end

  describe "next_block" do
    it "parses a simple paragraph" do
      reader = Asciidoctor::Reader.new(["This is a paragraph.", "With two lines."])
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Parser.next_block(reader, doc)
      block.should_not be_nil
      block.not_nil!.context.should eq(:paragraph)
    end

    it "parses a listing block" do
      reader = Asciidoctor::Reader.new(["----", "code here", "----"])
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Parser.next_block(reader, doc)
      block.should_not be_nil
      block.not_nil!.context.should eq(:listing)
    end

    it "parses a sidebar block" do
      reader = Asciidoctor::Reader.new(["****", "sidebar content", "****"])
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Parser.next_block(reader, doc)
      block.should_not be_nil
      block.not_nil!.context.should eq(:sidebar)
    end

    it "parses a literal block" do
      reader = Asciidoctor::Reader.new(["....", "literal content", "...."])
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Parser.next_block(reader, doc)
      block.should_not be_nil
      block.not_nil!.context.should eq(:literal)
    end

    it "parses a comment block and returns nil" do
      reader = Asciidoctor::Reader.new(["////", "comment content", "////"])
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Parser.next_block(reader, doc)
      block.should be_nil
    end

    it "parses a thematic break" do
      reader = Asciidoctor::Reader.new(["'''", "next content"])
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Parser.next_block(reader, doc)
      block.should_not be_nil
      block.not_nil!.context.should eq(:thematic_break)
    end

    it "parses an indented paragraph as literal" do
      reader = Asciidoctor::Reader.new(["  indented line 1", "  indented line 2"])
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Parser.next_block(reader, doc)
      block.should_not be_nil
      block.not_nil!.context.should eq(:literal)
    end

    it "returns nil when reader is empty" do
      reader = Asciidoctor::Reader.new([] of String)
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Parser.next_block(reader, doc)
      block.should be_nil
    end
  end

  describe "initialize_section" do
    it "creates a section from atx title" do
      reader = Asciidoctor::Reader.new(["== My Section", "", "content"])
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Parser.initialize_section(reader, doc)
      section.title.should eq("My Section")
      section.level.should eq(1)
      section.sectname.should eq("section")
    end

    it "creates a section with generated id" do
      reader = Asciidoctor::Reader.new(["== My Section", "", "content"])
      doc = Asciidoctor::Document.new
      doc.attributes["sectids"] = ""
      section = Asciidoctor::Parser.initialize_section(reader, doc)
      section.id.should_not be_nil
    end

    it "creates a chapter for book doctype level 1" do
      reader = Asciidoctor::Reader.new(["== Chapter One", "", "content"])
      doc = Asciidoctor::Document.new(doctype: "book")
      section = Asciidoctor::Parser.initialize_section(reader, doc)
      section.sectname.should eq("chapter")
    end

    it "creates a part for book doctype level 0" do
      reader = Asciidoctor::Reader.new(["= Part One", "", "content"])
      doc = Asciidoctor::Document.new(doctype: "book")
      section = Asciidoctor::Parser.initialize_section(reader, doc)
      section.sectname.should eq("part")
    end
  end

  describe "parse (integration)" do
    it "parses a simple document with title and paragraph" do
      source = "= My Document\n\nThis is a paragraph."
      reader = Asciidoctor::Reader.new(source)
      doc = Asciidoctor::Document.new
      Asciidoctor::Parser.parse(reader, doc)
      doc.blocks.should_not be_empty
    end

    it "parses a document with sections" do
      source = "= My Document\n\n== Section 1\n\nParagraph 1.\n\n== Section 2\n\nParagraph 2."
      reader = Asciidoctor::Reader.new(source)
      doc = Asciidoctor::Document.new
      Asciidoctor::Parser.parse(reader, doc)
      doc.blocks.size.should be >= 1
    end

    it "parses a document with nested sections" do
      source = "= My Document\n\n== Section 1\n\n=== Subsection 1.1\n\nContent."
      reader = Asciidoctor::Reader.new(source)
      doc = Asciidoctor::Document.new
      Asciidoctor::Parser.parse(reader, doc)
      doc.blocks.should_not be_empty
    end
  end
end

# ============================================================================
# Tests for newly ported methods (Task 3)
# ============================================================================

describe Asciidoctor::Parser do
  describe ".catalog_callouts" do
    it "detects callout markers in source text" do
      doc = Asciidoctor::Document.new
      text = "puts 'hello' <1>\nputs 'world' <2>"
      result = Asciidoctor::Parser.catalog_callouts(text, doc)
      result.should be_true
    end

    it "returns false when no callouts present" do
      doc = Asciidoctor::Document.new
      text = "puts 'hello'\nputs 'world'"
      result = Asciidoctor::Parser.catalog_callouts(text, doc)
      result.should be_false
    end

    it "handles auto-numbered callouts" do
      doc = Asciidoctor::Document.new
      text = "line 1 <.>\nline 2 <.>"
      result = Asciidoctor::Parser.catalog_callouts(text, doc)
      result.should be_true
    end
  end

  describe ".catalog_inline_anchors" do
    it "catalogs inline anchors in text" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      reader = Asciidoctor::Reader.new(["content"])
      text = "Some text [[myanchor]] more text"
      # Should not raise
      Asciidoctor::Parser.catalog_inline_anchors(text, block, doc, reader)
    end

    it "catalogs bibliography anchors" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      reader = Asciidoctor::Reader.new(["content"])
      text = "Some text [[[bibref]]] more text"
      Asciidoctor::Parser.catalog_inline_anchors(text, block, doc, reader)
    end
  end

  describe ".parse_cellspec" do
    it "parses text without cellspec at end position" do
      attrs, text = Asciidoctor::Parser.parse_cellspec("just text")
      attrs.should_not be_nil
      text.should eq("just text")
    end

    it "parses cellspec with horizontal alignment at start" do
      attrs, text = Asciidoctor::Parser.parse_cellspec(">|cell content", pos: :start, delimiter: "|")
      attrs.should_not be_nil
      if attrs
        attrs["halign"]?.should eq("right")
      end
      text.should eq("cell content")
    end

    it "parses cellspec with span at start" do
      attrs, text = Asciidoctor::Parser.parse_cellspec("2+|cell content", pos: :start, delimiter: "|")
      attrs.should_not be_nil
      if attrs
        attrs["colspan"]?.should eq(2)
      end
      text.should eq("cell content")
    end

    it "returns nil attrs when no delimiter found at start" do
      attrs, text = Asciidoctor::Parser.parse_cellspec("no delimiter", pos: :start, delimiter: "|")
      attrs.should be_nil
      text.should eq("no delimiter")
    end
  end

  describe ".parse_callout_list" do
    it "parses a callout list" do
      doc = Asciidoctor::Document.new
      callouts = doc.callouts
      # Register callouts first
      callouts.register(1)
      reader = Asciidoctor::Reader.new(["<1> First callout", "<2> Second callout"])
      line = reader.read_line.not_nil!
      match = Asciidoctor::CalloutListRx.match(line)
      if match
        list = Asciidoctor::Parser.parse_callout_list(reader, match, doc, callouts)
        list.context.should eq(:colist)
        list.items.size.should be >= 1
      end
    end
  end

  describe ".parse_list_item" do
    it "parses a simple unordered list item" do
      doc = Asciidoctor::Document.new
      list = Asciidoctor::List.new(doc, :ulist)
      reader = Asciidoctor::Reader.new(["* Item 1", "* Item 2"])
      line = reader.read_line.not_nil!
      match = Asciidoctor::UnorderedListRx.match(line)
      if match
        item = Asciidoctor::Parser.parse_list_item(reader, list, match, "*")
        item.should_not be_nil
        item.text.should eq("Item 1")
      end
    end

    it "parses a list item with continuation" do
      doc = Asciidoctor::Document.new
      list = Asciidoctor::List.new(doc, :ulist)
      reader = Asciidoctor::Reader.new(["* Item 1", "+", "Continuation text", "* Item 2"])
      line = reader.read_line.not_nil!
      match = Asciidoctor::UnorderedListRx.match(line)
      if match
        item = Asciidoctor::Parser.parse_list_item(reader, list, match, "*")
        item.should_not be_nil
      end
    end
  end

  describe ".resolve_ordered_list_start" do
    it "returns 1 for dot markers" do
      Asciidoctor::Parser.resolve_ordered_list_start(".").should eq(1)
    end

    it "returns the number for arabic markers" do
      Asciidoctor::Parser.resolve_ordered_list_start("3.").should eq(3)
    end

    it "returns the position for lowercase alpha markers" do
      Asciidoctor::Parser.resolve_ordered_list_start("c.").should eq(3)
    end

    it "returns the position for uppercase alpha markers" do
      Asciidoctor::Parser.resolve_ordered_list_start("C.").should eq(3)
    end

    it "returns the value for lowercase roman markers" do
      Asciidoctor::Parser.resolve_ordered_list_start("iii)").should eq(3)
    end

    it "returns the value for uppercase roman markers" do
      Asciidoctor::Parser.resolve_ordered_list_start("III)").should eq(3)
    end
  end

  describe ".resolve_ordered_list_marker (extended)" do
    it "resolves lowercase roman markers" do
      marker, style = Asciidoctor::Parser.resolve_ordered_list_marker("i)")
      marker.should eq("i)")
      style.should eq(:lowerroman)
    end

    it "resolves uppercase roman markers" do
      marker, style = Asciidoctor::Parser.resolve_ordered_list_marker("I)")
      marker.should eq("I)")
      style.should eq(:upperroman)
    end

    it "validates ordinal when requested" do
      marker, style = Asciidoctor::Parser.resolve_ordered_list_marker("2.", ordinal: 1, validate: true)
      marker.should eq("1.")
      style.should eq(:arabic)
    end
  end

  describe ".yield_buffered_attribute" do
    it "stores a style attribute" do
      attrs = {} of Symbol => String | Array(String)
      Asciidoctor::Parser.yield_buffered_attribute(attrs, nil, "source")
      attrs[:style].should eq("source")
    end

    it "stores an id attribute" do
      attrs = {} of Symbol => String | Array(String)
      Asciidoctor::Parser.yield_buffered_attribute(attrs, :id, "myid")
      attrs[:id].should eq("myid")
    end

    it "stores role attributes as array" do
      attrs = {} of Symbol => String | Array(String)
      Asciidoctor::Parser.yield_buffered_attribute(attrs, :role, "lead")
      Asciidoctor::Parser.yield_buffered_attribute(attrs, :role, "center")
      roles = attrs[:role]
      roles.should be_a(Array(String))
      roles.as(Array(String)).should eq(["lead", "center"])
    end

    it "stores option attributes as array" do
      attrs = {} of Symbol => String | Array(String)
      Asciidoctor::Parser.yield_buffered_attribute(attrs, :option, "nowrap")
      Asciidoctor::Parser.yield_buffered_attribute(attrs, :option, "linenums")
      options = attrs[:option]
      options.should be_a(Array(String))
      options.as(Array(String)).should eq(["nowrap", "linenums"])
    end

    it "does not store empty values" do
      attrs = {} of Symbol => String | Array(String)
      Asciidoctor::Parser.yield_buffered_attribute(attrs, :id, "")
      attrs.has_key?(:id).should be_false
    end
  end

  describe ".read_lines_for_list_item" do
    it "reads lines for a simple list item" do
      reader = Asciidoctor::Reader.new(["line 1", "* next item"])
      lines = Asciidoctor::Parser.read_lines_for_list_item(reader, :ulist, "*")
      lines.should eq(["line 1"])
    end

    it "reads lines until blank line for list item" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "", "next paragraph"])
      lines = Asciidoctor::Parser.read_lines_for_list_item(reader, :ulist, "*")
      lines.should eq(["line 1", "line 2"])
    end
  end

  describe "parse_manpage_header" do
    it "does not raise on empty document" do
      doc = Asciidoctor::Document.new(doctype: "manpage")
      reader = Asciidoctor::Reader.new([] of String)
      attrs = {} of String => String
      # Should not raise
      Asciidoctor::Parser.parse_manpage_header(reader, doc, attrs)
    end
  end
end
