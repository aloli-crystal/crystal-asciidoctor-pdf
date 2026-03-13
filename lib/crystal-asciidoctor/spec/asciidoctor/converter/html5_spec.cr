require "../../spec_helper"

describe Asciidoctor::Converter::Html5Converter do
  converter = Asciidoctor::Converter::Html5Converter.new

  describe "#initialize" do
    it "creates an HTML5 converter with default settings" do
      c = Asciidoctor::Converter::Html5Converter.new
      c.backend.should eq "html5"
      c.backend_traits.basebackend.should eq "html"
      c.backend_traits.filetype.should eq "html"
      c.backend_traits.htmlsyntax.should eq "html"
    end

    it "creates an XHTML converter" do
      c = Asciidoctor::Converter::Html5Converter.new(htmlsyntax: "xml")
      c.backend_traits.htmlsyntax.should eq "xml"
    end
  end

  describe "#convert_paragraph" do
    it "converts a simple paragraph" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.lines = ["Hello world"]
      result = converter.convert_paragraph(block)
      result.should contain "<p>"
      result.should contain %( class="paragraph")
    end

    it "converts a paragraph with an id" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.id = "my-para"
      block.lines = ["Hello world"]
      result = converter.convert_paragraph(block)
      result.should contain %(id="my-para")
      result.should contain %(class="paragraph")
    end

    it "converts a paragraph with a role" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.attributes["role"] = "lead"
      block.lines = ["Hello world"]
      result = converter.convert_paragraph(block)
      result.should contain %(class="paragraph lead")
    end

    it "converts a paragraph with a title" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.title = "My Title"
      block.lines = ["Hello world"]
      result = converter.convert_paragraph(block)
      result.should contain %(<div class="title">My Title</div>)
    end
  end

  describe "#convert_section" do
    it "converts a level 1 section" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, level: 1)
      section.id = "sect1"
      section.title = "My Section"
      result = converter.convert_section(section)
      result.should contain %(class="sect1")
      result.should contain %(<h2 id="sect1">My Section</h2>)
      result.should contain %(class="sectionbody")
    end

    it "converts a level 2 section" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, level: 2)
      section.id = "sect2"
      section.title = "Subsection"
      result = converter.convert_section(section)
      result.should contain %(class="sect2")
      result.should contain %(<h3 id="sect2">Subsection</h3>)
    end

    it "converts a level 0 section (part)" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, level: 0)
      section.id = "part1"
      section.title = "Part One"
      result = converter.convert_section(section)
      result.should contain %(<h1 id="part1")
      result.should contain %(class="sect0")
    end

    it "adds sectanchors when enabled" do
      doc = Asciidoctor::Document.new
      doc.attributes["sectanchors"] = "true"
      section = Asciidoctor::Section.new(doc, level: 1)
      section.id = "anchored"
      section.title = "Anchored"
      result = converter.convert_section(section)
      result.should contain %(class="anchor")
      result.should contain %(href="#anchored")
    end

    it "adds sectlinks when enabled" do
      doc = Asciidoctor::Document.new
      doc.attributes["sectlinks"] = "true"
      section = Asciidoctor::Section.new(doc, level: 1)
      section.id = "linked"
      section.title = "Linked"
      result = converter.convert_section(section)
      result.should contain %(class="link")
      result.should contain %(href="#linked")
    end

    it "adds section numbering when numbered" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, level: 1)
      section.id = "numbered"
      section.title = "Numbered"
      section.numbered = true
      section.numeral = "1"
      result = converter.convert_section(section)
      result.should contain "1."
    end
  end

  describe "#convert_admonition" do
    it "converts an admonition block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :admonition)
      block.attributes["name"] = "note"
      block.attributes["textlabel"] = "Note"
      block.lines = ["This is a note."]
      result = converter.convert_admonition(block)
      result.should contain %(class="admonitionblock note")
      result.should contain "Note"
    end

    it "uses font icons when icons=font" do
      doc = Asciidoctor::Document.new
      doc.attributes["icons"] = "font"
      block = Asciidoctor::Block.new(doc, :admonition)
      block.attributes["name"] = "warning"
      block.attributes["textlabel"] = "Warning"
      block.lines = ["Be careful!"]
      result = converter.convert_admonition(block)
      result.should contain %(class="fa icon-warning")
    end
  end

  describe "#convert_listing" do
    it "converts a listing block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :listing)
      block.lines = ["puts 'hello'"]
      result = converter.convert_listing(block)
      result.should contain %(class="listingblock")
      result.should contain "<pre"
    end

    it "converts a source listing block with language" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :listing)
      block.style = "source"
      block.attributes["language"] = "ruby"
      block.lines = ["puts 'hello'"]
      result = converter.convert_listing(block)
      result.should contain %(class="language-ruby")
      result.should contain %(data-lang="ruby")
    end
  end

  describe "#convert_literal" do
    it "converts a literal block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :literal)
      block.lines = ["literal text"]
      result = converter.convert_literal(block)
      result.should contain %(class="literalblock")
      result.should contain "<pre"
    end
  end

  describe "#convert_example" do
    it "converts an example block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :example)
      block.lines = ["Example content"]
      result = converter.convert_example(block)
      result.should contain %(class="exampleblock")
    end

    it "converts a collapsible example block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :example)
      block.attributes["collapsible-option"] = ""
      block.lines = ["Hidden content"]
      result = converter.convert_example(block)
      result.should contain "<details"
      result.should contain "<summary"
    end
  end

  describe "#convert_sidebar" do
    it "converts a sidebar block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :sidebar)
      block.lines = ["Sidebar content"]
      result = converter.convert_sidebar(block)
      result.should contain %(class="sidebarblock")
    end
  end

  describe "#convert_quote" do
    it "converts a quote block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :quote)
      block.lines = ["To be or not to be"]
      result = converter.convert_quote(block)
      result.should contain %(class="quoteblock")
      result.should contain "<blockquote>"
    end

    it "converts a quote block with attribution" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :quote)
      block.attributes["attribution"] = "Shakespeare"
      block.attributes["citetitle"] = "Hamlet"
      block.lines = ["To be or not to be"]
      result = converter.convert_quote(block)
      result.should contain "Shakespeare"
      result.should contain "<cite>Hamlet</cite>"
    end
  end

  describe "#convert_verse" do
    it "converts a verse block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :verse)
      block.lines = ["Roses are red"]
      result = converter.convert_verse(block)
      result.should contain %(class="verseblock")
      result.should contain %(<pre class="content">)
    end
  end

  describe "#convert_open" do
    it "converts an open block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :open)
      block.lines = ["Open content"]
      result = converter.convert_open(block)
      result.should contain %(class="openblock")
    end

    it "converts an abstract open block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :open)
      block.style = "abstract"
      block.lines = ["Abstract content"]
      result = converter.convert_open(block)
      result.should contain %(class="quoteblock abstract")
      result.should contain "<blockquote>"
    end
  end

  describe "#convert_ulist" do
    it "converts an unordered list" do
      doc = Asciidoctor::Document.new
      list = Asciidoctor::List.new(doc, :ulist)
      item1 = Asciidoctor::ListItem.new(list, "First item")
      item2 = Asciidoctor::ListItem.new(list, "Second item")
      list.items << item1
      list.items << item2
      result = converter.convert_ulist(list)
      result.should contain %(class="ulist")
      result.should contain "<ul"
      result.should contain "First item"
      result.should contain "Second item"
    end
  end

  describe "#convert_olist" do
    it "converts an ordered list" do
      doc = Asciidoctor::Document.new
      list = Asciidoctor::List.new(doc, :olist)
      item1 = Asciidoctor::ListItem.new(list, "Step one")
      item2 = Asciidoctor::ListItem.new(list, "Step two")
      list.items << item1
      list.items << item2
      result = converter.convert_olist(list)
      result.should contain %(class="olist)
      result.should contain "<ol"
      result.should contain "Step one"
      result.should contain "Step two"
    end
  end

  describe "#convert_image" do
    it "converts an image block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :image)
      block.attributes["target"] = "photo.jpg"
      block.attributes["alt"] = "A photo"
      result = converter.convert_image(block)
      result.should contain %(class="imageblock")
      result.should contain %(<img src=")
      result.should contain %(alt="A photo")
    end

    it "converts an image block with a link" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :image)
      block.attributes["target"] = "photo.jpg"
      block.attributes["alt"] = "A photo"
      block.attributes["link"] = "https://example.com"
      result = converter.convert_image(block)
      result.should contain %(<a class="image" href="https://example.com">)
    end
  end

  describe "#convert_page_break" do
    it "converts a page break" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :page_break)
      result = converter.convert_page_break(block)
      result.should eq %(<div class="page-break"></div>)
    end
  end

  describe "#convert_thematic_break" do
    it "converts a thematic break" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :thematic_break)
      result = converter.convert_thematic_break(block)
      result.should contain "<hr"
    end
  end

  describe "#convert_inline_quoted" do
    it "converts strong text" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "bold text", type: :strong)
      result = converter.convert_inline_quoted(inline)
      result.should eq "<strong>bold text</strong>"
    end

    it "converts emphasis text" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "italic text", type: :emphasis)
      result = converter.convert_inline_quoted(inline)
      result.should eq "<em>italic text</em>"
    end

    it "converts monospaced text" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "code", type: :monospaced)
      result = converter.convert_inline_quoted(inline)
      result.should eq "<code>code</code>"
    end

    it "converts marked text" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "highlighted", type: :mark)
      result = converter.convert_inline_quoted(inline)
      result.should eq "<mark>highlighted</mark>"
    end

    it "converts superscript text" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "2", type: :superscript)
      result = converter.convert_inline_quoted(inline)
      result.should eq "<sup>2</sup>"
    end

    it "converts subscript text" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "2", type: :subscript)
      result = converter.convert_inline_quoted(inline)
      result.should eq "<sub>2</sub>"
    end

    it "converts double-quoted text" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "quoted", type: :double)
      result = converter.convert_inline_quoted(inline)
      result.should eq "&#8220;quoted&#8221;"
    end

    it "converts single-quoted text" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "quoted", type: :single)
      result = converter.convert_inline_quoted(inline)
      result.should eq "&#8216;quoted&#8217;"
    end

    it "adds role as class to tagged inline" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "bold", type: :strong)
      inline.attributes["role"] = "custom"
      result = converter.convert_inline_quoted(inline)
      result.should contain %(class="custom")
    end

    it "adds id to tagged inline" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :quoted, "bold", type: :strong)
      inline.id = "myid"
      result = converter.convert_inline_quoted(inline)
      result.should contain %(id="myid")
    end
  end

  describe "#convert_inline_anchor" do
    it "converts a link" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :anchor, "Example", type: :link, target: "https://example.com")
      result = converter.convert_inline_anchor(inline)
      result.should contain %(href="https://example.com")
      result.should contain "Example"
    end

    it "converts a xref" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :anchor, "See section", type: :xref, target: "#section1")
      result = converter.convert_inline_anchor(inline)
      result.should contain %(href="#section1")
      result.should contain "See section"
    end

    it "converts a ref (anchor)" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :anchor, "", type: :ref)
      inline.id = "myref"
      result = converter.convert_inline_anchor(inline)
      result.should contain %(id="myref")
    end

    it "converts a bibref" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :anchor, nil, type: :bibref)
      inline.id = "ref1"
      result = converter.convert_inline_anchor(inline)
      result.should contain %(id="ref1")
      result.should contain "[ref1]"
    end
  end

  describe "#convert_inline_break" do
    it "converts an inline break" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :break, "text")
      result = converter.convert_inline_break(inline)
      result.should contain "text"
      result.should contain "<br"
    end
  end

  describe "#convert_inline_button" do
    it "converts an inline button" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :button, "OK")
      result = converter.convert_inline_button(inline)
      result.should eq %(<b class="button">OK</b>)
    end
  end

  describe "#convert_inline_kbd" do
    it "converts a single key" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :kbd, "")
      inline.attributes["keys"] = "Ctrl"
      result = converter.convert_inline_kbd(inline)
      result.should eq "<kbd>Ctrl</kbd>"
    end

    it "converts a key sequence" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :kbd, "")
      inline.attributes["keys"] = "Ctrl+C"
      result = converter.convert_inline_kbd(inline)
      result.should contain %(class="keyseq")
      result.should contain "<kbd>Ctrl</kbd>+<kbd>C</kbd>"
    end
  end

  describe "#convert_inline_indexterm" do
    it "returns empty string for invisible indexterm" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :indexterm, "hidden", type: :invisible)
      result = converter.convert_inline_indexterm(inline)
      result.should eq ""
    end

    it "returns text for visible indexterm" do
      doc = Asciidoctor::Document.new
      inline = Asciidoctor::Inline.new(doc, :indexterm, "visible", type: :visible)
      result = converter.convert_inline_indexterm(inline)
      result.should eq "visible"
    end
  end

  describe "#convert_floating_title" do
    it "converts a floating title" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, level: 2)
      section.id = "float1"
      section.title = "Float Title"
      section.style = "discrete"
      result = converter.convert_floating_title(section)
      result.should contain "<h3"
      result.should contain %(id="float1")
      result.should contain "Float Title"
    end
  end

  describe "#convert_document" do
    it "generates a complete HTML5 document" do
      doc = Asciidoctor::Document.new
      doc.attributes["doctitle"] = "Test Document"
      doc.title = "Test Document"
      result = converter.convert_document(doc)
      result.should contain "<!DOCTYPE html>"
      result.should contain "<html"
      result.should contain "<head>"
      result.should contain "<body"
      result.should contain "</html>"
      result.should contain "Test Document"
    end
  end
end
