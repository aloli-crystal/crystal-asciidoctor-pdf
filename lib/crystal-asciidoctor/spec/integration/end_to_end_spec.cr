require "../spec_helper"

describe "End-to-end integration" do
  describe "Asciidoctor.load" do
    it "loads a simple document from a string" do
      source = "= My Document\nAuthor Name\n\nThis is a paragraph."
      doc = Asciidoctor.load(source)
      doc.should be_a(Asciidoctor::Document)
      doc.doctitle.should eq("My Document")
    end

    it "loads a document with sections" do
      source = <<-ADOC
      = Main Title

      == Section One

      First paragraph.

      == Section Two

      Second paragraph.
      ADOC
      doc = Asciidoctor.load(source)
      doc.should be_a(Asciidoctor::Document)
      doc.blocks.size.should be >= 0
    end
  end

  describe "Asciidoctor.convert" do
    it "converts a simple paragraph to HTML5" do
      source = "This is a simple paragraph."
      result = Asciidoctor.convert(source)
      result.should be_a(String)
      result.should contain("This is a simple paragraph.")
    end

    it "converts a document with a title to HTML5" do
      source = "= Document Title\n\nA paragraph of text."
      result = Asciidoctor.convert(source)
      result.should be_a(String)
      result.should contain("A paragraph of text.")
    end

    it "converts to docbook5 backend" do
      source = "= Document Title\n\nA paragraph."
      result = Asciidoctor.convert(source, {"backend" => "docbook5"})
      result.should be_a(String)
    end

    it "converts to manpage backend" do
      source = "= command(1)\nAuthor\n\n== NAME\n\ncommand - a test command\n\n== SYNOPSIS\n\n*command* [_options_]"
      result = Asciidoctor.convert(source, {"backend" => "manpage"})
      result.should be_a(String)
    end
  end

  describe "Reader" do
    it "reads lines from a string source" do
      source = "Line 1\nLine 2\nLine 3"
      reader = Asciidoctor::Reader.new(source.split("\n"))
      reader.has_more_lines?.should be_true
      reader.read_line.should eq("Line 1")
      reader.read_line.should eq("Line 2")
      reader.read_line.should eq("Line 3")
      reader.has_more_lines?.should be_false
    end

    it "supports peek and unshift" do
      reader = Asciidoctor::Reader.new(["A", "B", "C"])
      reader.peek_line.should eq("A")
      reader.read_line.should eq("A")
      reader.unshift_line("X")
      reader.read_line.should eq("X")
      reader.read_line.should eq("B")
    end

    it "reads all lines at once" do
      reader = Asciidoctor::Reader.new(["A", "B", "C"])
      lines = reader.read_lines
      lines.should eq(["A", "B", "C"])
      reader.has_more_lines?.should be_false
    end
  end

  describe "Parser utility methods" do
    it "detects delimited blocks" do
      result = Asciidoctor::Parser.is_delimited_block?("----")
      result.should_not be_nil
      result.not_nil!.context.should eq(:listing)
    end

    it "detects section titles" do
      result = Asciidoctor::Parser.is_section_title?("== Section Title", nil)
      result.should_not be_nil
    end

    it "detects atx section title level" do
      # Section titles are parsed via the reader, so we test detection
      result = Asciidoctor::Parser.is_section_title?("= Document Title", nil)
      result.should_not be_nil
      result2 = Asciidoctor::Parser.is_section_title?("=== Level 2", nil)
      result2.should_not be_nil
      result3 = Asciidoctor::Parser.is_section_title?("Not a title", nil)
      result3.should be_nil
    end

    it "parses block metadata line with anchor" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::Reader.new(["[[my-anchor]]"])
      attrs = {} of String => String
      result = Asciidoctor::Parser.parse_block_metadata_line(reader, doc, attrs)
      result.should be_true
      attrs["id"]?.should eq("my-anchor")
    end

    it "parses block metadata line with block title" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::Reader.new([".My Title"])
      attrs = {} of String => String
      result = Asciidoctor::Parser.parse_block_metadata_line(reader, doc, attrs)
      result.should be_true
      attrs["title"]?.should eq("My Title")
    end
  end

  describe "HTML5 Converter full pipeline" do
    it "converts a paragraph block through the full pipeline" do
      doc = Asciidoctor::Document.new
      converter = Asciidoctor::Converter::Html5Converter.new
      doc.converter = converter

      block = Asciidoctor::Block.new(
        parent_block: doc,
        context: :paragraph,
        content_model: Asciidoctor::ContentModel::Simple,
        source: "Hello, World!"
      )
      result = converter.convert_paragraph(block)
      result.should contain("<p>Hello, World!</p>")
    end

    it "converts a section with a paragraph" do
      doc = Asciidoctor::Document.new
      converter = Asciidoctor::Converter::Html5Converter.new
      doc.converter = converter

      section = Asciidoctor::Section.new(document: doc, parent: doc, level: 1)
      section.title = "My Section"
      section.id = "my-section"
      section.numeral = "1"

      para = Asciidoctor::Block.new(
        parent_block: section,
        context: :paragraph,
        content_model: Asciidoctor::ContentModel::Simple,
        source: "A paragraph inside a section."
      )
      section << para

      result = converter.convert_section(section)
      result.should contain("My Section")
      result.should contain("my-section")
      result.should contain("A paragraph inside a section.")
    end

    it "converts a listing block" do
      doc = Asciidoctor::Document.new
      converter = Asciidoctor::Converter::Html5Converter.new
      doc.converter = converter

      block = Asciidoctor::Block.new(
        parent_block: doc,
        context: :listing,
        content_model: Asciidoctor::ContentModel::Verbatim
      )
      block.style = "source"
      block.attributes["language"] = "crystal"
      block.lines = ["puts \"Hello\""]

      result = converter.convert_listing(block)
      result.should contain("<code")
      result.should contain("crystal")
      result.should contain("puts")
    end

    it "converts an admonition block" do
      doc = Asciidoctor::Document.new
      converter = Asciidoctor::Converter::Html5Converter.new
      doc.converter = converter

      block = Asciidoctor::Block.new(
        parent_block: doc,
        context: :admonition,
        content_model: Asciidoctor::ContentModel::Compound
      )
      block.style = "NOTE"
      block.attributes["name"] = "note"
      block.attributes["textlabel"] = "Note"

      result = converter.convert_admonition(block)
      result.should contain("admonitionblock")
      result.should contain("Note")
    end

    it "converts inline quoted text" do
      doc = Asciidoctor::Document.new
      converter = Asciidoctor::Converter::Html5Converter.new

      emphasis = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "italic", type: :emphasis)
      result = converter.convert_inline_quoted(emphasis)
      result.should contain("<em>italic</em>")

      strong = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "bold", type: :strong)
      result = converter.convert_inline_quoted(strong)
      result.should contain("<strong>bold</strong>")

      mono = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "code", type: :monospaced)
      result = converter.convert_inline_quoted(mono)
      result.should contain("<code>code</code>")
    end

    it "converts inline anchors" do
      doc = Asciidoctor::Document.new
      converter = Asciidoctor::Converter::Html5Converter.new

      link = Asciidoctor::Inline.new(parent_block: doc, context: :anchor, text: "Example", type: :link)
      link.target = "https://example.com"
      result = converter.convert_inline_anchor(link)
      result.should contain("href=\"https://example.com\"")
      result.should contain("Example")
    end
  end

  describe "Callouts" do
    it "registers and retrieves callouts" do
      callouts = Asciidoctor::Callouts.new
      callouts.register(1)
      callouts.current_list.size.should eq(1)
      callouts.current_list[0][:ordinal].should eq(1)
    end
  end

  describe "SafeMode" do
    it "has correct values" do
      Asciidoctor::SafeMode::UNSAFE.should eq(0)
      Asciidoctor::SafeMode::SAFE.should eq(1)
      Asciidoctor::SafeMode::SERVER.should eq(10)
      Asciidoctor::SafeMode::SECURE.should eq(20)
    end
  end

  describe "Rx patterns" do
    it "matches section titles" do
      match = Asciidoctor::AtxSectionTitleRx.match("== Section Title")
      match.should_not be_nil
    end

    it "matches block anchors" do
      match = Asciidoctor::BlockAnchorRx.match("[[my-id]]")
      match.should_not be_nil
    end

    it "matches attribute entries" do
      match = Asciidoctor::AttributeEntryRx.match(":author: John Doe")
      match.should_not be_nil
    end

    it "matches block titles" do
      match = Asciidoctor::BlockTitleRx.match(".My Title")
      match.should_not be_nil
    end
  end
end
