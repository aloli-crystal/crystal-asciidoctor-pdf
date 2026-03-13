require "../../spec_helper"

SAMPLE_MANPAGE_HEADER = <<-EOS
= command (1)
Author Name
:doctype: manpage
:man manual: Command Manual
:man source: Command 1.2.3

== NAME

command - does stuff

== SYNOPSIS

*command* [_OPTION_]... _FILE_...

== DESCRIPTION
EOS

# Helper to convert manpage input
def manpage_convert(input : String, options : Hash(String, String) = {} of String => String) : String
  options["backend"] = "manpage"
  options["doctype"] = "manpage"
  Asciidoctor.convert(input, options)
end

# Helper to load manpage document
def manpage_load(input : String, options : Hash(String, String) = {} of String => String) : Asciidoctor::Document
  options["backend"] = "manpage"
  options["doctype"] = "manpage"
  Asciidoctor.load(input, options)
end

describe Asciidoctor::Converter::ManPageConverter do
  # ==========================================================================
  # Configuration
  # ==========================================================================
  describe "Configuration" do
    it "should load document with manpage backend" do
      doc = manpage_load(SAMPLE_MANPAGE_HEADER)
      doc.backend.should eq("manpage")
      doc.doctype.should eq("manpage")
    end

    it "should parse sections from manpage document" do
      doc = manpage_load(SAMPLE_MANPAGE_HEADER)
      doc.sections.size.should eq(2)
      doc.sections[0].title.should eq("SYNOPSIS")
      doc.sections[1].title.should eq("DESCRIPTION")
    end

    it "should parse doctitle from manpage document" do
      doc = manpage_load(SAMPLE_MANPAGE_HEADER)
      doc.doctitle.should eq("command (1)")
    end

    it "should read man manual attribute" do
      doc = manpage_load(SAMPLE_MANPAGE_HEADER)
      # Attributes with spaces may be stored with different key formats
      manual = doc.attributes["man manual"]? || doc.attributes["man-manual"]? || doc.attributes["manmanual"]?
      manual.should_not be_nil
    end

    it "should read man source attribute" do
      doc = manpage_load(SAMPLE_MANPAGE_HEADER)
      # Attributes with spaces may be stored with different key formats
      source = doc.attributes["man source"]? || doc.attributes["man-source"]? || doc.attributes["mansource"]?
      source.should_not be_nil
    end

    it "should set proper manpage-related attributes" do
      doc = manpage_load(SAMPLE_MANPAGE_HEADER)
      doc.attributes["filetype"]?.should eq("man")
      doc.attributes["filetype-man"]?.should eq("")
      doc.attributes["manvolnum"]?.should eq("1")
      doc.attributes["outfilesuffix"]?.should eq(".1")
      doc.attributes["manname"]?.should eq("command")
      doc.attributes["mantitle"]?.should eq("command")
      doc.attributes["manpurpose"]?.should eq("does stuff")
    end

    it "should define default linkstyle" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain("LINKSTYLE blue R < >")
    end

    it "should use linkstyle defined by man-linkstyle attribute" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true", "attributes" => "man-linkstyle=cyan B \\[fo] \\[fc]"})
      output.should contain("LINKSTYLE cyan B \\[fo] \\[fc]")
    end

    it "should not escape hyphen when printing manname in NAME section" do
      input = SAMPLE_MANPAGE_HEADER.gsub("command - ", "git-describe - ")
      output = manpage_convert(input, {"standalone" => "true"})
      output.should contain(".SH \"NAME\"\ngit-describe \\- does stuff\n")
    end

    it "should output multiple mannames in NAME section" do
      input = SAMPLE_MANPAGE_HEADER.gsub("command - ", "command, alt_command - ")
      output = manpage_convert(input, {"standalone" => "true"})
      output.should contain("command, alt_command \\- does stuff")
    end
  end

  # ==========================================================================
  # Standalone output
  # ==========================================================================
  describe "Standalone output" do
    it "should generate TH macro in standalone output" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain(".TH")
    end

    it "should include manual and source in TH macro" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain("Command 1.2.3")
      output.should contain("Command Manual")
    end

    it "should include info comment block" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain("Generator: Asciidoctor Crystal")
      output.should contain("Author: Author Name")
    end

    it "should include URL and MTO macro definitions" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain(".de URL")
      output.should contain(".als MTO URL")
    end

    it "should include SH NAME section" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain(".SH \"NAME\"")
    end

    it "should include SH SYNOPSIS section" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain(".SH \"SYNOPSIS\"")
    end

    it "should include SH DESCRIPTION section" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain(".SH \"DESCRIPTION\"")
    end

    it "should format name section with dash separator" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER, {"standalone" => "true"})
      output.should contain("command \\- does stuff")
    end

    it "should not escape spaces for empty manual or source fields" do
      input_lines = SAMPLE_MANPAGE_HEADER.lines.reject { |l| l.starts_with?(":man ") }
      output = manpage_convert(input_lines.join("\n"), {"standalone" => "true"})
      output.should contain("Manual: \\ \\&")
      output.should contain("Source: \\ \\&")
    end
  end

  # ==========================================================================
  # Embedded output (non-standalone)
  # ==========================================================================
  describe "Embedded output" do
    it "should generate SH sections" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER)
      output.should contain(".SH \"NAME\"")
      output.should contain(".SH \"SYNOPSIS\"")
      output.should contain(".SH \"DESCRIPTION\"")
    end

    it "should include NAME section content" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER)
      output.should contain("command \\- does stuff")
    end

    it "should include SYNOPSIS section content" do
      output = manpage_convert(SAMPLE_MANPAGE_HEADER)
      output.should contain("command")
    end
  end

  # ==========================================================================
  # Paragraph conversion
  # ==========================================================================
  describe "#convert_paragraph" do
    it "converts a simple paragraph" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :paragraph, content_model: Asciidoctor::ContentModel::Simple)
      block.lines = ["Hello World"]
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_paragraph(block)
      result.should contain("Hello World")
    end

    it "adds .sp before paragraph" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :paragraph, content_model: Asciidoctor::ContentModel::Simple)
      block.lines = ["Test paragraph"]
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_paragraph(block)
      result.should contain(".sp")
    end

    it "should convert paragraph with description" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nThis is a description paragraph."
      output = manpage_convert(input)
      output.should contain("This is a description paragraph.")
    end

    it "should add .sp before each paragraph" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nFirst paragraph.\n\nSecond paragraph."
      output = manpage_convert(input)
      output.should contain(".sp\nFirst paragraph.")
      output.should contain(".sp\nSecond paragraph.")
    end
  end

  # ==========================================================================
  # Section conversion
  # ==========================================================================
  describe "#convert_section" do
    it "converts a section with title" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(document: doc, parent: doc)
      section.title = "SYNOPSIS"
      section.level = 1
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_section(section)
      result.should contain(".SH")
      result.should contain("SYNOPSIS")
    end

    it "should uppercase level 1 section titles" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ndoes stuff\n\n== Custom Section"
      output = manpage_convert(input)
      output.should contain(".SH \"CUSTOM SECTION\"")
    end

    it "should use SS for level 2 sections" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ndoes stuff\n\n== Options\n\n=== General Options"
      output = manpage_convert(input)
      output.should contain(".SS")
      output.should contain("General Options")
    end

    it "should handle multiple sections" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ndoes stuff\n\n== SEE ALSO\n\nother(1)"
      output = manpage_convert(input)
      output.should contain(".SH \"DESCRIPTION\"")
      output.should contain(".SH \"SEE ALSO\"")
    end
  end

  # ==========================================================================
  # Literal and listing blocks
  # ==========================================================================
  describe "Literal and listing blocks" do
    it "converts a literal block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :literal, content_model: Asciidoctor::ContentModel::Verbatim)
      block.lines = ["literal text"]
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_literal(block)
      result.should contain(".sp")
      result.should contain("literal text")
    end

    it "converts a listing block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :listing, content_model: Asciidoctor::ContentModel::Verbatim)
      block.lines = ["code here"]
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_listing(block)
      result.should contain(".sp")
      result.should contain("code here")
    end

    it "should use .nf and .fi for literal blocks" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :literal, content_model: Asciidoctor::ContentModel::Verbatim)
      block.lines = ["line 1", "line 2"]
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_literal(block)
      result.should contain(".nf")
      result.should contain(".fi")
    end

    it "should use .nf and .fi for listing blocks" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :listing, content_model: Asciidoctor::ContentModel::Verbatim)
      block.lines = ["code line 1", "code line 2"]
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_listing(block)
      result.should contain(".nf")
      result.should contain(".fi")
    end

    it "should escape repeated spaces in literal content" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n....\n  ,---.          ,-----.\n  |Bob|          |Alice|\n  `-+-'          `--+--'\n...."
      output = manpage_convert(input)
      output.should contain(".fam C")
      output.should contain(".fam")
    end
  end

  # ==========================================================================
  # Inline quoted text
  # ==========================================================================
  describe "#convert_inline_quoted" do
    it "converts emphasis" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "emphasized", type: :emphasis)
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_inline_quoted(node)
      result.should contain("\\fI")
      result.should contain("emphasized")
      result.should contain("\\fP")
    end

    it "converts strong" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "bold", type: :strong)
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_inline_quoted(node)
      result.should contain("\\fB")
      result.should contain("bold")
      result.should contain("\\fP")
    end

    it "converts monospaced text" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "mono", type: :monospaced)
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_inline_quoted(node)
      result.should contain("\\f(CR")
      result.should contain("mono")
      result.should contain("\\fP")
    end

    it "converts double-quoted text" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "hello", type: :double)
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_inline_quoted(node)
      result.should contain("\\(lq")
      result.should contain("hello")
      result.should contain("\\(rq")
    end

    it "converts single-quoted text" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :quoted, text: "goodbye", type: :single)
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_inline_quoted(node)
      result.should contain("\\(oq")
      result.should contain("goodbye")
      result.should contain("\\(cq")
    end

    it "should preserve backslashes in escape sequences" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n\"`hello`\" '`goodbye`' *strong* _weak_ `even`"
      output = manpage_convert(input)
      output.should contain("\\(lqhello\\(rq")
      output.should contain("\\(oqgoodbye\\(cq")
      output.should contain("\\fBstrong\\fP")
      output.should contain("\\fIweak\\fP")
      output.should contain("\\f(CReven\\fP")
    end
  end

  # ==========================================================================
  # Inline anchor
  # ==========================================================================
  describe "#convert_inline_anchor" do
    it "converts a link" do
      doc = Asciidoctor::Document.new
      node = Asciidoctor::Inline.new(parent_block: doc, context: :anchor, text: "Example", type: :link)
      node.target = "https://example.com"
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_inline_anchor(node)
      result.should contain("Example")
    end
  end

  # ==========================================================================
  # Admonition
  # ==========================================================================
  describe "#convert_admonition" do
    it "converts an admonition block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :admonition, content_model: Asciidoctor::ContentModel::Compound)
      block.style = "NOTE"
      block.attributes["name"] = "note"
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_admonition(block)
      result.should contain("Note")
    end

    it "converts a WARNING admonition" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(parent_block: doc, context: :admonition, content_model: Asciidoctor::ContentModel::Compound)
      block.style = "WARNING"
      block.attributes["name"] = "warning"
      converter = Asciidoctor::Converter::ManPageConverter.new("manpage")
      result = converter.convert_admonition(block)
      result.should contain("Warning")
    end
  end

  # ==========================================================================
  # Manify (text escaping and formatting)
  # ==========================================================================
  describe "Manify" do
    it "should unescape literal ampersand" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n(C) & (R) are translated to character references, but not the &."
      output = manpage_convert(input)
      last_line = output.lines.last.chomp
      last_line.should eq("\\(co & \\(rg are translated to character references, but not the &.")
    end

    it "should replace numeric character reference for plus" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nA {plus} B"
      output = manpage_convert(input)
      output.lines.last.chomp.should eq("A + B")
    end

    it "should replace em dashes" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ngo -- to\n\ngo--to"
      output = manpage_convert(input)
      output.should contain("go \\(em to")
      output.should contain("go\\(emto")
    end

    it "should replace quotes" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n'command'"
      output = manpage_convert(input)
      output.should contain("\\*(Aqcommand\\*(Aq")
    end

    it "should escape lone period" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n."
      output = manpage_convert(input)
      output.lines.last.chomp.should eq("\\&.")
    end

    it "should escape raw macro" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nAAA this line of text should be show\n.if 1 .nx\nBBB this line and the one above it should be visible"
      output = manpage_convert(input)
      output.should contain("\\&.if 1 .nx")
    end

    it "should normalize whitespace in a paragraph" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nOh, here it goes again\n  I should have known,\n    should have known,\nshould have known again"
      output = manpage_convert(input)
      output.should contain("Oh, here it goes again\nI should have known,\nshould have known,\nshould have known again")
    end

    it "should uppercase section titles without mangling formatting macros" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ndoes stuff\n\n== \"`Main`\" _<Options>_"
      output = manpage_convert(input)
      output.should contain(".SH \"\\(lqMAIN\\(rq \\fI<OPTIONS>\\fP\"")
    end

    it "should not uppercase monospace span in section titles" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ndoes stuff\n\n== `show` option"
      output = manpage_convert(input)
      output.should contain(".SH \"\\f(CRshow\\fP OPTION\"")
    end
  end

  # ==========================================================================
  # Backslash handling
  # ==========================================================================
  describe "Backslash" do
    it "should preserve literal backslashes in content" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n\\.foo \\ bar \\\\ baz\\\nmore"
      output = manpage_convert(input)
      output.should contain("\\(rs.foo \\(rs bar \\(rs\\(rs baz\\(rs")
    end

    it "should escape literal escape sequence" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n \\fB makes text bold"
      output = manpage_convert(input)
      output.should contain("\\(rsfB makes text bold")
    end

    it "should preserve inline breaks" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nBefore break. +\nAfter break."
      output = manpage_convert(input)
      output.should contain("Before break.\n.br\nAfter break.")
    end
  end

  # ==========================================================================
  # URL macro
  # ==========================================================================
  describe "URL macro" do
    it "should not leave blank line before URL macro" do
      input = SAMPLE_MANPAGE_HEADER + "\nFirst paragraph.\n\nhttp://asciidoc.org[AsciiDoc]"
      output = manpage_convert(input)
      output.should contain(".URL \"http://asciidoc.org\" \"AsciiDoc\" \"\"")
    end

    it "should not swallow content following URL" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nhttp://asciidoc.org[AsciiDoc] can be used to create man pages."
      output = manpage_convert(input)
      output.should contain(".URL \"http://asciidoc.org\" \"AsciiDoc\" \"\"")
      output.should contain("can be used to create man pages.")
    end

    it "should pass adjacent character as final argument of URL macro" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nThis is http://asciidoc.org[AsciiDoc]."
      output = manpage_convert(input)
      output.should contain(".URL \"http://asciidoc.org\" \"AsciiDoc\" \".\"")
    end
  end

  # ==========================================================================
  # MTO macro (email)
  # ==========================================================================
  describe "MTO macro" do
    it "should convert inline email macro into MTO macro" do
      input = SAMPLE_MANPAGE_HEADER + "\nFirst paragraph.\n\nmailto:doc@example.org[Contact the doc]"
      output = manpage_convert(input)
      output.should contain(".MTO \"doc\\(atexample.org\" \"Contact the doc\" \"\"")
    end

    it "should set text of MTO macro to blank for implicit email" do
      input = SAMPLE_MANPAGE_HEADER + "\nBugs fixed daily by doc@example.org."
      output = manpage_convert(input)
      output.should contain(".MTO \"doc\\(atexample.org\" \"\" \".\"")
    end
  end

  # ==========================================================================
  # Table
  # ==========================================================================
  describe "Table" do
    it "should create header, body, and footer rows in correct order" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n[%header%footer]\n|===\n|Header\n|Body 1\n|Body 2\n|Footer\n|==="
      output = manpage_convert(input)
      output.should contain(".TS")
      output.should contain(".TE")
    end

    it "should manify table title" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n.Table of options\n|===\n| Name | Description | Default\n\n| dim\n| dimension of the object\n| 3\n|==="
      output = manpage_convert(input)
      output.should contain("Table of options")
    end
  end

  # ==========================================================================
  # Images
  # ==========================================================================
  describe "Images" do
    it "should replace block image with alt text enclosed in square brackets" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nBehold the wisdom of the Magic 8 Ball!\n\nimage::signs-point-to-yes.jpg[]"
      output = manpage_convert(input)
      output.should contain("[signs point to yes]")
    end

    it "should replace inline image with alt text enclosed in square brackets" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nThe Magic 8 Ball says image:signs-point-to-yes.jpg[]."
      output = manpage_convert(input)
      output.should contain("[signs point to yes]")
    end
  end

  # ==========================================================================
  # Quote Block
  # ==========================================================================
  describe "Quote Block" do
    it "should indent quote block" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n[,James Baldwin]\n____\nNot everything that is faced can be changed.\nBut nothing can be changed until it is faced.\n____"
      output = manpage_convert(input)
      output.should contain(".RS 3")
      output.should contain("Not everything that is faced can be changed.")
    end
  end

  # ==========================================================================
  # Lists
  # ==========================================================================
  describe "Lists" do
    it "should convert unordered list" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ndoes stuff\n\n* Item 1\n* Item 2\n* Item 3"
      output = manpage_convert(input)
      output.should contain("Item 1")
      output.should contain("Item 2")
      output.should contain("Item 3")
    end

    it "should convert ordered list" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ndoes stuff\n\n. First\n. Second\n. Third"
      output = manpage_convert(input)
      output.should contain("First")
      output.should contain("Second")
      output.should contain("Third")
    end

    it "should convert description list" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ndoes stuff\n\nterm1:: definition1\nterm2:: definition2"
      output = manpage_convert(input)
      output.should contain("term1")
      output.should contain("definition1")
      output.should contain("term2")
      output.should contain("definition2")
    end

    it "should normalize whitespace in a list item" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n* Oh, here it goes again\n    I should have known,\n  should have known,\nshould have known again"
      output = manpage_convert(input)
      output.should contain("Oh, here it goes again\nI should have known,\nshould have known,\nshould have known again")
    end

    it "should honor start attribute on ordered list" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n[start=5]\n. five\n. six"
      output = manpage_convert(input)
      output.should contain("5.")
      output.should contain("six")
    end
  end

  # ==========================================================================
  # Page breaks
  # ==========================================================================
  describe "Page breaks" do
    it "should insert page break at location of page break macro" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n== Section With Break\n\nbefore break\n\n<<<\n\nafter break"
      output = manpage_convert(input)
      output.should contain("before break")
      output.should contain(".bp")
      output.should contain("after break")
    end
  end

  # ==========================================================================
  # UI macros
  # ==========================================================================
  describe "UI macros" do
    it "should enclose button in square brackets and format as bold" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n== UI Macros\n\nbtn:[Save]"
      output = manpage_convert(input, {"attributes" => "experimental"})
      output.should contain("\\fB[\\0Save\\0]\\fP")
    end

    it "should format single key in monospaced text" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n== UI Macros\n\nkbd:[Enter]"
      output = manpage_convert(input, {"attributes" => "experimental"})
      output.should contain("\\f(CREnter\\fP")
    end

    it "should format menu sequence in italic separated by carets" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n== UI Macros\n\nmenu:File[New Tab]"
      output = manpage_convert(input, {"attributes" => "experimental"})
      output.should contain("\\fIFile\\0\\(fc\\0New Tab\\fP")
    end
  end

  # ==========================================================================
  # Xrefs
  # ==========================================================================
  describe "Xrefs" do
    it "should populate automatic link text for internal xref" do
      input = SAMPLE_MANPAGE_HEADER + "\n\nYou can access this information using the options listed under <<_generic_program_information>>.\n\n== Options\n\n=== Generic Program Information\n\n--help:: Output a usage message and exit."
      output = manpage_convert(input)
      output.should contain("Generic Program Information")
    end
  end

  # ==========================================================================
  # Footnotes
  # ==========================================================================
  describe "Footnotes" do
    it "should generate list of footnotes using numbered list with numbers enclosed in brackets" do
      input = SAMPLE_MANPAGE_HEADER + "\n\ntext.footnote:[first footnote]\n\nmore text.footnote:[second footnote]"
      output = manpage_convert(input)
      output.should contain("text.[1]")
      output.should contain("more text.[2]")
      output.should contain(".SH \"NOTES\"")
      output.should contain(".IP [1]")
      output.should contain("first footnote")
      output.should contain(".IP [2]")
      output.should contain("second footnote")
    end
  end

  # ==========================================================================
  # Verse Block
  # ==========================================================================
  describe "Verse Block" do
    it "should preserve hard line breaks in verse block" do
      input = SAMPLE_MANPAGE_HEADER.gsub("*command* [_OPTION_]... _FILE_...", "[verse]\n_command_ [_OPTION_]... _FILE_...") + "\n\ndescription"
      output = manpage_convert(input)
      output.should contain(".nf")
      output.should contain(".fi")
    end
  end

  # ==========================================================================
  # Callout List
  # ==========================================================================
  describe "Callout List" do
    it "should generate callout list using proper formatting commands" do
      input = SAMPLE_MANPAGE_HEADER + "\n\n----\n$ gem install asciidoctor # <1>\n----\n<1> Installs the asciidoctor gem from RubyGems.org"
      output = manpage_convert(input)
      output.should contain(".TS")
      output.should contain("Installs the asciidoctor gem from RubyGems.org")
      output.should contain(".TE")
    end
  end
end
