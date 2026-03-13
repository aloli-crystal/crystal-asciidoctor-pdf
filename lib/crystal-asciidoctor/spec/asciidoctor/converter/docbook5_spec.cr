require "../../spec_helper"

describe Asciidoctor::Converter::DocBook5Converter do
  converter = Asciidoctor::Converter::DocBook5Converter.new("docbook5")

  describe "#convert_paragraph" do
    it "converts a simple paragraph" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :paragraph, content_model: Asciidoctor::ContentModel::Simple)
      block.lines = ["Hello World"]
      result = converter.convert_paragraph(block)
      result.should contain("<simpara>Hello World</simpara>")
    end
  end

  describe "#convert_section" do
    it "converts a section with title" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(document: doc, parent: doc)
      section.title = "My Section"
      section.level = 1
      section.id = "_my_section"
      result = converter.convert_section(section)
      result.should contain("<section")
      result.should contain("xml:id=\"_my_section\"")
      result.should contain("<title>My Section</title>")
    end
  end

  describe "#convert_admonition" do
    it "converts an admonition block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :admonition, content_model: Asciidoctor::ContentModel::Compound)
      block.attributes["style"] = "NOTE"
      block.attributes["name"] = "note"
      block.title = "Important Note"
      result = converter.convert_admonition(block)
      result.should contain("<note>")
      result.should contain("<title>Important Note</title>")
    end
  end

  describe "#convert_listing" do
    it "converts a listing block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :listing, content_model: Asciidoctor::ContentModel::Verbatim)
      block.lines = ["puts 'hello'"]
      result = converter.convert_listing(block)
      result.should contain("<screen")
      result.should contain("puts 'hello'")
    end

    it "converts a source code listing" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :listing, content_model: Asciidoctor::ContentModel::Verbatim)
      block.style = "source"
      block.attributes["language"] = "ruby"
      block.lines = ["puts 'hello'"]
      result = converter.convert_listing(block)
      result.should contain("<programlisting")
      result.should contain("language=\"ruby\"")
    end
  end

  describe "#convert_literal" do
    it "converts a literal block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :literal, content_model: Asciidoctor::ContentModel::Verbatim)
      block.lines = ["literal text"]
      result = converter.convert_literal(block)
      result.should contain("<literallayout")
      result.should contain("literal text")
    end
  end

  describe "#convert_sidebar" do
    it "converts a sidebar block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :sidebar, content_model: Asciidoctor::ContentModel::Compound)
      result = converter.convert_sidebar(block)
      result.should contain("<sidebar>")
    end
  end

  describe "#convert_example" do
    it "converts an example block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :example, content_model: Asciidoctor::ContentModel::Compound)
      block.title = "My Example"
      result = converter.convert_example(block)
      result.should contain("<example>")
    end
  end

  describe "#convert_quote" do
    it "converts a quote block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :quote, content_model: Asciidoctor::ContentModel::Compound)
      block.attributes["attribution"] = "Albert Einstein"
      result = converter.convert_quote(block)
      result.should contain("<blockquote>")
      result.should contain("<attribution>")
      result.should contain("Albert Einstein")
    end
  end

  describe "#convert_verse" do
    it "converts a verse block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :verse, content_model: Asciidoctor::ContentModel::Verbatim)
      block.attributes["attribution"] = "Shakespeare"
      block.lines = ["To be or not to be"]
      result = converter.convert_verse(block)
      result.should contain("<blockquote>")
      result.should contain("Shakespeare")
      result.should contain("To be or not to be")
    end
  end

  describe "#convert_inline_quoted" do
    it "converts emphasis" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "emphasized", type: :emphasis)
      result = converter.convert_inline_quoted(node)
      result.should eq("<emphasis>emphasized</emphasis>")
    end

    it "converts strong" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "bold", type: :strong)
      result = converter.convert_inline_quoted(node)
      result.should contain("<emphasis role=\"strong\">bold</emphasis>")
    end

    it "converts monospaced" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "code", type: :monospaced)
      result = converter.convert_inline_quoted(node)
      result.should contain("<literal>code</literal>")
    end
  end

  describe "#convert_inline_anchor" do
    it "converts an xref without text" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :anchor, text: nil, type: :xref)
      node.attributes["refid"] = "section-1"
      node.target = "section-1"
      result = converter.convert_inline_anchor(node)
      result.should contain("<xref")
      result.should contain("linkend=\"section-1\"")
    end

    it "converts an xref with text" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :anchor, text: "Section 1", type: :xref)
      node.attributes["refid"] = "section-1"
      node.target = "section-1"
      result = converter.convert_inline_anchor(node)
      result.should contain("<link")
      result.should contain("linkend=\"section-1\"")
    end

    it "converts a link" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :anchor, text: "Example", type: :link)
      node.target = "https://example.com"
      result = converter.convert_inline_anchor(node)
      result.should contain("<link")
      result.should contain("xl:href=\"https://example.com\"")
    end
  end

  describe "#convert_inline_break" do
    it "converts a line break" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :break, text: "text")
      result = converter.convert_inline_break(node)
      result.should contain("text")
      result.should contain("<?asciidoc-br?>")
    end
  end
end
