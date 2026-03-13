require "../spec_helper"

# Helper methods used across section tests
def convert_string(input : String, options : Hash(String, String) = {} of String => String) : String
  options["standalone"] = "true" unless options.has_key?("standalone")
  Asciidoctor.convert(input, options)
end

def convert_string_to_embedded(input : String, options : Hash(String, String) = {} of String => String) : String
  options["standalone"] = "false"
  Asciidoctor.convert(input, options)
end

def document_from_string(input : String, options : Hash(String, String) = {} of String => String) : Asciidoctor::Document
  Asciidoctor.load(input, options)
end

def block_from_string(input : String, options : Hash(String, String) = {} of String => String) : Asciidoctor::AbstractBlock
  doc = document_from_string(input, options)
  doc.blocks.first? || doc.header.not_nil!
end

describe Asciidoctor::Section do
  # ==========================================================================
  # Ids
  # ==========================================================================
  describe "Ids" do
    it "synthetic id is generated when sectids is set" do
      sec = block_from_string(":sectids:\n\n== Section One")
      sec.id.should eq("_section_one")
    end

    it "synthetic id is not generated when sectids is unset" do
      sec = block_from_string(":sectids!:\n\n== Section One")
      sec.id.should be_nil
    end

    it "synthetic id removes non-word characters" do
      sec = block_from_string(":sectids:\n\n== Were back")
      sec.id.should eq("_were_back")
    end

    it "synthetic id collapses repeating spaces" do
      sec = block_from_string(":sectids:\n\n== Go    Far")
      sec.id.should eq("_go_far")
    end

    it "synthetic id prefix can be customized" do
      sec = block_from_string(":sectids:\n:idprefix: id_\n\n== Section One")
      sec.id.should eq("id_section_one")
    end

    it "synthetic id prefix can be set to blank" do
      sec = block_from_string(":sectids:\n:idprefix:\n\n== Section One")
      sec.id.should eq("section_one")
    end

    it "synthetic id separator can be customized" do
      sec = block_from_string(":sectids:\n:idseparator: -\n\n== Section One")
      sec.id.should eq("_section-one")
    end

    it "synthetic id separator can be set to blank" do
      sec = block_from_string(":sectids:\n:idseparator:\n\n== Section One")
      sec.id.should eq("_sectionone")
    end

    it "synthetic id separator can be set to blank when idprefix is blank" do
      sec = block_from_string(":sectids:\n:idprefix:\n:idseparator:\n\n== Section One")
      sec.id.should eq("sectionone")
    end

    it "explicit id in anchor above section title overrides synthetic id" do
      sec = block_from_string(":sectids:\n\n[[one]]\n== Section One")
      sec.id.should eq("one")
    end

    it "explicit id in block attributes above section title overrides synthetic id" do
      sec = block_from_string(":sectids:\n\n[id=one]\n== Section One")
      sec.id.should eq("one")
    end

    it "explicit id set using shorthand in style above section title overrides synthetic id" do
      sec = block_from_string(":sectids:\n\n[#one]\n== Section One")
      sec.id.should eq("one")
    end

    it "title substitutions are applied before generating id" do
      sec = block_from_string(":sectids:\n\n== Section{sp}One\n")
      sec.id.should eq("_section_one")
    end

    it "duplicate synthetic id is automatically enumerated" do
      doc = document_from_string(":sectids:\n\n== Section One\n\n== Section One")
      doc.blocks.size.should eq(2)
      doc.blocks[0].id.should eq("_section_one")
      doc.blocks[1].id.should eq("_section_one_2")
    end

    it "explicit id can be defined using an embedded anchor" do
      sec = block_from_string(":sectids:\n\n== Section One [[one]] ==")
      sec.id.should eq("one")
      sec.title.should eq("Section One")
    end
  end

  # ==========================================================================
  # Levels
  # ==========================================================================
  describe "Levels" do
    describe "Document Title (Level 0)" do
      it "document title with atx syntax" do
        output = convert_string("= My Title")
        output.should contain("My Title")
      end

      it "document title with symmetric syntax" do
        output = convert_string("= My Title =")
        output.should contain("My Title")
      end
    end

    describe "Level 1" do
      it "with atx syntax" do
        output = convert_string(":sectids:\n\n== My Title")
        output.should contain("My Title")
        output.should contain("<h2")
      end

      it "with trailing whitespace" do
        output = convert_string(":sectids:\n\n== My Title ")
        output.should contain("My Title")
      end

      it "with custom blank idprefix" do
        output = convert_string(":sectids:\n:idprefix:\n\n== My Title")
        output.should contain("my_title")
      end

      it "with custom non-blank idprefix" do
        output = convert_string(":sectids:\n:idprefix: ref_\n\n== My Title")
        output.should contain("ref_my_title")
      end
    end

    describe "Level 2" do
      it "with atx line syntax" do
        output = convert_string_to_embedded(":sectids:\n\n== Parent\n\n=== My Title")
        output.should contain("My Title")
        output.should contain("<h3")
      end
    end

    describe "Level 3" do
      it "with atx line syntax" do
        output = convert_string_to_embedded(":sectids:\n\n== Parent\n\n=== Parent2\n\n==== My Title")
        output.should contain("My Title")
        output.should contain("<h4")
      end
    end

    describe "Level 4" do
      it "with atx line syntax" do
        output = convert_string_to_embedded(":sectids:\n\n== P1\n\n=== P2\n\n==== P3\n\n===== My Title")
        output.should contain("My Title")
        output.should contain("<h5")
      end
    end

    describe "Level 5" do
      it "with atx line syntax" do
        output = convert_string_to_embedded(":sectids:\n\n== P1\n\n=== P2\n\n==== P3\n\n===== P4\n\n====== My Title")
        output.should contain("My Title")
        output.should contain("<h6")
      end
    end
  end

  # ==========================================================================
  # Nesting
  # ==========================================================================
  describe "Nesting" do
    it "should parse nested sections correctly" do
      input = "= Document Title\n\n== Section A\n\n=== Nested Section\n\ncontent\n\n== Section B\n\ncontent"
      doc = document_from_string(input)
      doc.blocks.size.should eq(2)
    end

    it "should parse deeply nested sections" do
      input = "= Document Title\n\n== Level 1\n\n=== Level 2\n\n==== Level 3\n\ncontent"
      doc = document_from_string(input)
      doc.blocks.size.should eq(1)
      sect1 = doc.blocks[0]
      sect1.should be_a(Asciidoctor::Section)
      sect1.level.should eq(1)
    end

    it "should have correct number of child sections" do
      input = "= Document Title\n\n== Section A\n\n=== Nested A1\n\n=== Nested A2\n\ncontent"
      doc = document_from_string(input)
      sect_a = doc.blocks[0]
      sect_a.should be_a(Asciidoctor::Section)
      if sect_a.is_a?(Asciidoctor::Section)
        sect_a.sections?.should be_true
        child_sections = sect_a.blocks.select { |b| b.is_a?(Asciidoctor::Section) }
        child_sections.size.should eq(2)
      end
    end
  end

  # ==========================================================================
  # Markdown-style headings
  # ==========================================================================
  describe "Markdown-style headings" do
    it "atx document title with leading marker" do
      output = convert_string("# Document Title")
      output.should contain("Document Title")
    end

    it "atx section title with leading marker" do
      input = ":sectids:\n\n## Section One\n\nblah blah"
      output = convert_string(input)
      output.should contain("Section One")
    end

    it "atx section title with symmetric markers" do
      input = ":sectids:\n\n## Section One ##\n\nblah blah"
      output = convert_string(input)
      output.should contain("Section One")
    end

    it "generates correct id for markdown heading" do
      doc = document_from_string(":sectids:\n\n## Section One\n\nblah blah")
      doc.blocks[0].id.should eq("_section_one")
    end
  end

  # ==========================================================================
  # Discrete Heading
  # ==========================================================================
  describe "Discrete Heading" do
    it "should create discrete heading instead of section if style is discrete" do
      input = "[discrete]\n=== Independent Heading!\n\nnot in section"
      output = convert_string_to_embedded(input)
      output.should contain("Independent Heading!")
      output.should contain("discrete")
    end

    it "should create discrete heading instead of section if style is float" do
      input = "[float]\n= Independent Heading!\n\nnot in section"
      output = convert_string_to_embedded(input)
      output.should contain("Independent Heading!")
    end

    it "discrete heading should be a block with context floating_title" do
      input = "[float]\n=== Independent Heading!\n\nnot in section"
      doc = document_from_string(input)
      heading = doc.blocks.first
      heading.should be_a(Asciidoctor::Block)
      heading.context.should eq(:floating_title)
    end

    it "can assign explicit id to discrete heading" do
      input = "[[unchained]]\n[float]\n=== Independent Heading!\n\nnot in section"
      doc = document_from_string(input)
      heading = doc.blocks.first
      heading.id.should eq("unchained")
    end
  end

  # ==========================================================================
  # Level offset
  # ==========================================================================
  describe "Level offset" do
    it "should add level offset to section level" do
      input = "= Main Document\nDoc Writer\n\nMain document written by {author}.\n\n:leveloffset: 1\n\n= Standalone Document\n:author: Junior Writer\n\nStandalone document written by {author}.\n\n== Section in Standalone\n\nStandalone section text.\n\n:leveloffset!:\n\n== Section in Main\n\nMain section text."
      output = convert_string(input)
      output.should contain("Standalone Document")
      output.should contain("Section in Main")
    end
  end

  # ==========================================================================
  # Section Numbering
  # ==========================================================================
  describe "Section Numbering" do
    it "should create section number with one entry for level 1" do
      doc = Asciidoctor::Document.new
      sect1 = Asciidoctor::Section.new(doc, numbered: true)
      sect1.numeral = "1"
      doc << sect1
      sect1.sectnum.should eq("1.")
    end

    it "should create section number with two entries for level 2" do
      doc = Asciidoctor::Document.new
      sect1 = Asciidoctor::Section.new(doc, numbered: true)
      sect1.numeral = "1"
      doc << sect1
      sect1_1 = Asciidoctor::Section.new(doc, parent: sect1, numbered: true)
      sect1_1.numeral = "1"
      sect1 << sect1_1
      sect1_1.sectnum.should eq("1.1.")
    end

    it "should create section number with three entries for level 3" do
      doc = Asciidoctor::Document.new
      sect1 = Asciidoctor::Section.new(doc, numbered: true)
      sect1.numeral = "1"
      doc << sect1
      sect1_1 = Asciidoctor::Section.new(doc, parent: sect1, numbered: true)
      sect1_1.numeral = "1"
      sect1 << sect1_1
      sect1_1_1 = Asciidoctor::Section.new(doc, parent: sect1_1, numbered: true)
      sect1_1_1.numeral = "1"
      sect1_1 << sect1_1_1
      sect1_1_1.sectnum.should eq("1.1.1.")
    end

    it "should create section number for second section in level" do
      doc = Asciidoctor::Document.new
      sect1 = Asciidoctor::Section.new(doc, numbered: true)
      sect1.numeral = "1"
      doc << sect1
      sect1_1 = Asciidoctor::Section.new(doc, parent: sect1, numbered: true)
      sect1_1.numeral = "1"
      sect1 << sect1_1
      sect1_2 = Asciidoctor::Section.new(doc, parent: sect1, numbered: true)
      sect1_2.numeral = "2"
      sect1 << sect1_2
      sect1_2.sectnum.should eq("1.2.")
    end

    it "sectnum should use specified delimiter and append string" do
      doc = Asciidoctor::Document.new
      sect1 = Asciidoctor::Section.new(doc, numbered: true)
      sect1.numeral = "1"
      doc << sect1
      sect1_1 = Asciidoctor::Section.new(doc, parent: sect1, numbered: true)
      sect1_1.numeral = "1"
      sect1 << sect1_1
      sect1_1_1 = Asciidoctor::Section.new(doc, parent: sect1_1, numbered: true)
      sect1_1_1.numeral = "1"
      sect1_1 << sect1_1_1
      sect1_1_1.sectnum(",").should eq("1,1,1,")
      sect1_1_1.sectnum(":", "").should eq("1:1:1")
    end

    it "should output section numbers when sectnums attribute is set" do
      input = "= Title\n:sectnums:\n:sectids:\n\n== Section_1\n\ntext\n\n=== Section_1_1\n\ntext\n\n== Section_2\n\ntext"
      output = convert_string(input)
      output.should contain("1. Section_1")
      output.should contain("1.1. Section_1_1")
    end

    it "should output section numbers when numbered attribute is set" do
      input = "= Title\n:numbered:\n:sectids:\n\n== Section_1\n\ntext\n\n=== Section_1_1\n\ntext"
      output = convert_string(input)
      output.should contain("1. Section_1")
      output.should contain("1.1. Section_1_1")
    end

    it "blocks should have level" do
      input = "= Title\n\npreamble\n\n== Section 1\n\nparagraph\n\n=== Section 1.1\n\nparagraph"
      doc = document_from_string(input)
      # First block is preamble (level 0), second is section (level 1)
      doc.blocks[0].level.should eq(0)
      doc.blocks[1].level.should eq(1)
    end

    it "second section should have correct numeral" do
      input = "= Title\n:sectnums:\n\n== Section_1\n\ntext\n\n== Section_2\n\ntext"
      doc = document_from_string(input)
      sect1 = doc.blocks[0].as(Asciidoctor::Section)
      sect2 = doc.blocks[1].as(Asciidoctor::Section)
      sect1.numeral.should eq("1")
      sect2.numeral.should eq("2")
    end

    it "section numbers should not increment when numbered attribute is turned off within document" do
      input = "= Document Title\n:numbered:\n\n:numbered!:\n\n== Colophon Section\n\n== Another Colophon Section\n\n:numbered:\n\n== Section One\n\n=== Section One Subsection\n\n== Section Two\n\n== Section Three"
      output = convert_string(input)
      output.should contain("Colophon Section")
      output.should contain("1. Section One")
      output.should contain("1.1. Section One Subsection")
      output.should contain("2. Section Two")
      output.should contain("3. Section Three")
    end
  end

  # ==========================================================================
  # Links and anchors
  # ==========================================================================
  describe "Links and anchors" do
    it "should include anchor if sectanchors document attribute is set" do
      input = ":sectids:\n:sectanchors:\n\n== Installation\n\nInstallation section.\n\n=== Linux\n\nLinux installation instructions."
      output = convert_string_to_embedded(input)
      output.should contain("anchor")
      output.should contain("_installation")
    end

    it "should have anchor with href to section id" do
      input = ":sectids:\n:sectanchors:\n\n== Installation\n\nInstallation section."
      output = convert_string_to_embedded(input)
      output.should contain("#_installation")
    end

    it "should link section if sectlinks document attribute is set" do
      input = ":sectids:\n:sectlinks:\n\n== Installation\n\nInstallation section."
      output = convert_string_to_embedded(input)
      output.should contain("class=\"link\"")
      output.should contain("#_installation")
    end
  end

  # ==========================================================================
  # Special sections
  # ==========================================================================
  describe "Special sections" do
    it "should assign appendix sectname" do
      input = ":sectids:\n\n[appendix]\n== Attribute Options\n\nDetails"
      sec = block_from_string(input)
      sec.should be_a(Asciidoctor::Section)
      if sec.is_a?(Asciidoctor::Section)
        sec.sectname.should eq("appendix")
        sec.numbered.should be_true
      end
    end

    it "should prefix appendix title by numbered label even when section numbering is disabled" do
      input = ":sectids:\n\n[appendix]\n== Attribute Options\n\nDetails"
      output = convert_string_to_embedded(input)
      output.should contain("Appendix A")
      output.should contain("Attribute Options")
    end

    it "should use custom appendix caption if specified" do
      input = ":sectids:\n:appendix-caption: App\n\n[appendix]\n== Attribute Options\n\nDetails"
      output = convert_string_to_embedded(input)
      output.should contain("App A")
      output.should contain("Attribute Options")
    end

    it "should increment appendix number for each appendix section" do
      input = ":sectids:\n\n[appendix]\n== Attribute Options\n\nDetails\n\n[appendix]\n== Migration\n\nDetails"
      output = convert_string_to_embedded(input)
      output.should contain("Appendix A")
      output.should contain("Appendix B")
    end

    it "should continue numbering after appendix" do
      input = ":numbered:\n:sectids:\n\n== First Section\n\ncontent\n\n[appendix]\n== Attribute Options\n\ncontent\n\n== Migration\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("1. First Section")
      output.should contain("Appendix A")
      output.should contain("2. Migration")
    end

    it "should number appendix subsections using appendix letter" do
      input = ":numbered:\n:sectids:\n\n[appendix]\n== Attribute Options\n\nDetails\n\n=== Optional Attributes\n\nDetails"
      output = convert_string_to_embedded(input)
      output.should contain("Appendix A")
      output.should contain("A.1. Optional Attributes")
    end

    it "should not number level 4 section by default" do
      input = ":numbered:\n:sectids:\n\n== Level_1\n\n=== Level_2\n\n==== Level_3\n\n===== Level_4\n\ntext"
      output = convert_string_to_embedded(input)
      output.should contain("Level_4")
    end

    it "should only number levels up to value defined by sectnumlevels attribute" do
      input = ":numbered:\n:sectnumlevels: 2\n:sectids:\n\n== Level_1\n\n=== Level_2\n\n==== Level_3\n\n===== Level_4\n\ntext"
      output = convert_string_to_embedded(input)
      output.should contain("1. Level_1")
      output.should contain("1.1. Level_2")
      # Level_3 should not be numbered
    end

    it "should recognize glossary special section" do
      input = ":sectids:\n\n[glossary]\n== Terms\n\nDetails"
      doc = document_from_string(input)
      sect = doc.blocks[0]
      if sect.is_a?(Asciidoctor::Section)
        sect.sectname.should eq("glossary")
      end
    end

    it "should recognize bibliography special section" do
      input = ":sectids:\n\n[bibliography]\n== References\n\nDetails"
      doc = document_from_string(input)
      sect = doc.blocks[0]
      if sect.is_a?(Asciidoctor::Section)
        sect.sectname.should eq("bibliography")
      end
    end

    it "should recognize preface special section in book doctype" do
      input = ":sectids:\n\n[preface]\n== Preface\n\nDetails"
      doc = document_from_string(input, {"doctype" => "book"})
      sect = doc.blocks[0]
      if sect.is_a?(Asciidoctor::Section)
        sect.sectname.should eq("preface")
        sect.special.should be_true
      end
    end
  end

  # ==========================================================================
  # Table of Contents
  # ==========================================================================
  describe "Table of Contents" do
    it "should output table of contents in header if toc attribute is set" do
      input = "= Article\n:toc:\n:sectids:\n\n== Section One\n\nIt was a dark and stormy night...\n\n== Section Two\n\nThey couldn't believe their eyes when...\n\n=== Interlude\n\nWhile they were waiting...\n\n== Section Three\n\nThat's all she wrote!"
      output = convert_string(input)
      output.should contain("toc")
      output.should contain("toctitle")
      output.should contain("Section One")
      output.should contain("Section Two")
      output.should contain("Interlude")
      output.should contain("Section Three")
    end

    it "should contain links to sections in toc" do
      input = "= Article\n:toc:\n:sectids:\n\n== Section One\n\ntext\n\n== Section Two\n\ntext"
      output = convert_string(input)
      output.should contain("_section_one")
      output.should contain("_section_two")
    end

    it "should not display a table of contents if document has no sections" do
      input = "= Document Title\n:toc:\n\nThis document has no sections.\n\nIt only has content."
      output = convert_string(input)
      output.should_not contain("id=\"toctitle\"")
    end

    it "should use document attributes toc-title to create toc" do
      input = "= Article\n:toc:\n:toc-title: Contents\n:sectids:\n\n== Section 1\n\n== Section 2\n\nFin."
      output = convert_string(input)
      output.should contain("Contents")
    end

    it "should set toc placement to preamble if toc attribute is set to preamble" do
      input = "= Article\n:toc: preamble\n:sectids:\n\nYada yada\n\n== Section One\n\ntext\n\n== Section Two\n\ntext"
      output = convert_string(input)
      output.should contain("preamble")
      output.should contain("toc")
    end

    it "should not output table of contents if toc-placement attribute is unset" do
      input = "= Article\n:toc:\n:toc-placement!:\n:sectids:\n\n== Section One\n\ntext"
      output = convert_string(input)
      output.should_not contain("id=\"toc\"")
    end

    it "should output numbered table of contents if toc and numbered attributes are set" do
      input = "= Article\n:toc:\n:numbered:\n:sectids:\n\n== Section One\n\ntext\n\n== Section Two\n\ntext\n\n=== Interlude\n\ntext\n\n== Section Three\n\ntext"
      output = convert_string(input)
      output.should contain("1. Section One")
      output.should contain("2.1. Interlude")
      output.should contain("3. Section Three")
    end
  end

  # ==========================================================================
  # book doctype
  # ==========================================================================
  describe "book doctype" do
    it "document title with level 0 headings" do
      input = "= Book\nDoc Writer\n:doctype: book\n:sectids:\n\n= Chapter One\n\n== Scene One\n\nSomeone's gonna get axed.\n\n= Chapter Two\n\n== Interlude\n\nWhile they were waiting..."
      output = convert_string(input)
      output.should contain("book")
      output.should contain("Chapter One")
      output.should contain("Chapter Two")
    end

    it "should assign correct sectname for book sections" do
      input = "= Book Title\n:doctype: book\n:sectids:\n\n= Part Title\n\n== Chapter Title\n\n=== Section Title\n\ncontent"
      doc = document_from_string(input, {"doctype" => "book"})
      doc.blocks.size.should be >= 1
      part = doc.blocks[0]
      if part.is_a?(Asciidoctor::Section)
        part.sectname.should eq("part")
        part.level.should eq(0)
      end
    end

    it "should parse chapters in book doctype" do
      input = "= Book\n:doctype: book\n:sectids:\n\n== Chapter 1\n\ncontent\n\n== Chapter 2\n\ncontent"
      doc = document_from_string(input, {"doctype" => "book"})
      doc.blocks.size.should eq(2)
      ch1 = doc.blocks[0]
      if ch1.is_a?(Asciidoctor::Section)
        ch1.sectname.should eq("chapter")
        ch1.level.should eq(1)
      end
    end

    it "should number chapters sequentially even when divided into parts" do
      input = "= Document Title\n:doctype: book\n:numbered:\n:sectids:\n\n== Chapter 1\n\ncontent\n\n= Part 1\n\n== Chapter 2\n\ncontent\n\n= Part 2\n\n== Chapter 3\n\ncontent\n\n== Chapter 4\n\ncontent"
      output = convert_string(input)
      output.should contain("1. Chapter 1")
      output.should contain("2. Chapter 2")
      output.should contain("3. Chapter 3")
      output.should contain("4. Chapter 4")
    end

    it "should not number parts when doctype is book" do
      input = "= Document Title\n:doctype: book\n:numbered:\n:sectids:\n\n= Part 1\n\n== Chapter 1\n\ncontent\n\n= Part 2\n\n== Chapter 2\n\ncontent"
      output = convert_string(input)
      output.should contain("Part 1")
      output.should contain("Part 2")
    end

    it "should add class matching role to part" do
      input = "= Book Title\n:doctype: book\n:sectids:\n\n[.newbie]\n= Part 1\n\n== Chapter A\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("newbie")
    end
  end

  # ==========================================================================
  # heading patterns in blocks
  # ==========================================================================
  describe "heading patterns in blocks" do
    it "should not interpret a listing block as a heading" do
      input = ":sectids:\n\n== Section\n\n----\ncode\n----\n\nfin."
      output = convert_string(input)
      output.should contain("Section")
      output.should contain("code")
    end

    it "should not interpret an open block as a heading" do
      input = ":sectids:\n\n== Section\n\n--\nha\n--\n\nfin."
      output = convert_string(input)
      output.should contain("Section")
    end

    it "should not match a heading in a block" do
      input = "====\n\n== not a heading\n\n===="
      output = convert_string(input)
      output.should contain("== not a heading")
    end

    it "should not match a heading in a description list" do
      input = ":sectids:\n\n== Section\n\nterm1:: def1\nterm2:: def2\n\nfin."
      output = convert_string(input)
      output.should contain("Section")
      output.should contain("term1")
    end
  end

  # ==========================================================================
  # Setext-style headings
  # ==========================================================================
  describe "Setext-style headings" do
    it "should handle setext-style section titles" do
      input = ":sectids:\n\nSection Title\n-------------\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("Section Title")
      output.should contain("<h2")
    end
  end

  # ==========================================================================
  # #initialize
  # ==========================================================================
  describe "#initialize" do
    it "creates a section with default values" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.context.should eq(:section)
      section.level.should eq(1)
      section.numbered.should be_false
      section.special.should be_false
      section.index.should eq(0)
    end

    it "creates a section with custom level" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, level: 2)
      section.level.should eq(2)
    end

    it "creates a numbered section" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, numbered: true)
      section.numbered.should be_true
    end

    it "inherits level from parent section" do
      doc = Asciidoctor::Document.new
      parent = Asciidoctor::Section.new(doc, level: 1)
      child = Asciidoctor::Section.new(doc, parent: parent)
      child.level.should eq(2)
    end

    it "inherits special from parent section" do
      doc = Asciidoctor::Document.new
      parent = Asciidoctor::Section.new(doc, level: 1)
      parent.special = true
      child = Asciidoctor::Section.new(doc, parent: parent)
      child.special.should be_true
    end

    it "sets parent reference" do
      doc = Asciidoctor::Document.new
      parent = Asciidoctor::Section.new(doc, level: 1)
      child = Asciidoctor::Section.new(doc, parent: parent)
      child.parent.should eq(parent)
    end
  end

  # ==========================================================================
  # #<<
  # ==========================================================================
  describe "#<<" do
    it "appends a block to the section" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      block = Asciidoctor::Block.new(doc, :paragraph, source: "Hello")
      section << block
      section.blocks.size.should eq(1)
    end

    it "assigns numeral to child sections" do
      doc = Asciidoctor::Document.new
      parent = Asciidoctor::Section.new(doc, level: 1, numbered: true)
      parent.numeral = "1"
      child1 = Asciidoctor::Section.new(doc, parent: parent, numbered: true)
      parent << child1
      child1.index.should eq(0)
    end
  end

  # ==========================================================================
  # #block?
  # ==========================================================================
  describe "#block?" do
    it "returns true" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.block?.should be_true
    end
  end

  # ==========================================================================
  # #generate_id
  # ==========================================================================
  describe "#generate_id" do
    it "generates an id from the title" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.title = "My First Section"
      section.generate_id.should eq("_my_first_section")
    end

    it "returns nil when no title" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.generate_id.should be_nil
    end
  end

  # ==========================================================================
  # .generate_id
  # ==========================================================================
  describe ".generate_id" do
    it "generates an id from a title string" do
      doc = Asciidoctor::Document.new
      Asciidoctor::Section.generate_id("Hello World", doc).should eq("_hello_world")
    end

    it "respects custom idprefix" do
      doc = Asciidoctor::Document.new
      doc.attributes["idprefix"] = "id-"
      Asciidoctor::Section.generate_id("Hello World", doc).should eq("id-hello_world")
    end

    it "respects custom idseparator" do
      doc = Asciidoctor::Document.new
      doc.attributes["idseparator"] = "-"
      Asciidoctor::Section.generate_id("Hello World", doc).should eq("_hello-world")
    end

    it "lowercases the title" do
      doc = Asciidoctor::Document.new
      Asciidoctor::Section.generate_id("HELLO WORLD", doc).should eq("_hello_world")
    end

    it "removes special characters" do
      doc = Asciidoctor::Document.new
      Asciidoctor::Section.generate_id("Hello! World?", doc).should eq("_hello_world")
    end

    it "handles empty idprefix" do
      doc = Asciidoctor::Document.new
      doc.attributes["idprefix"] = ""
      Asciidoctor::Section.generate_id("Hello World", doc).should eq("hello_world")
    end

    it "handles empty idseparator" do
      doc = Asciidoctor::Document.new
      doc.attributes["idseparator"] = ""
      Asciidoctor::Section.generate_id("Hello World", doc).should eq("_helloworld")
    end
  end

  # ==========================================================================
  # #name
  # ==========================================================================
  describe "#name" do
    it "returns the title" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.title = "Introduction"
      section.name.should eq("Introduction")
    end
  end

  # ==========================================================================
  # #sectnum
  # ==========================================================================
  describe "#sectnum" do
    it "returns the section number with delimiter" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, numbered: true)
      section.numeral = "1"
      section.sectnum.should eq("1.")
    end

    it "returns nested section number" do
      doc = Asciidoctor::Document.new
      parent = Asciidoctor::Section.new(doc, level: 1, numbered: true)
      parent.numeral = "1"
      child = Asciidoctor::Section.new(doc, parent: parent, numbered: true)
      child.numeral = "2"
      child.sectnum.should eq("1.2.")
    end

    it "supports custom delimiter" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, numbered: true)
      section.numeral = "1"
      section.sectnum("-").should eq("1-")
    end

    it "supports custom append" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, numbered: true)
      section.numeral = "1"
      section.sectnum(".", "").should eq("1")
    end

    it "returns deeply nested section number" do
      doc = Asciidoctor::Document.new
      s1 = Asciidoctor::Section.new(doc, level: 1, numbered: true)
      s1.numeral = "2"
      s1_1 = Asciidoctor::Section.new(doc, parent: s1, numbered: true)
      s1_1.numeral = "3"
      s1_1_1 = Asciidoctor::Section.new(doc, parent: s1_1, numbered: true)
      s1_1_1.numeral = "4"
      s1_1_1.sectnum.should eq("2.3.4.")
    end
  end

  # ==========================================================================
  # #sections?
  # ==========================================================================
  describe "#sections?" do
    it "returns false when no child sections" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.sections?.should be_false
    end

    it "returns true when child sections exist" do
      doc = Asciidoctor::Document.new
      parent = Asciidoctor::Section.new(doc)
      child = Asciidoctor::Section.new(doc, parent: parent)
      parent << child
      parent.sections?.should be_true
    end

    it "returns false when only non-section blocks exist" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      block = Asciidoctor::Block.new(doc, :paragraph, source: "Hello")
      section << block
      section.sections?.should be_false
    end
  end

  # ==========================================================================
  # #xreftext
  # ==========================================================================
  describe "#xreftext" do
    it "returns reftext when set" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.set_attr("reftext", "See here")
      section.xreftext.should eq("See here")
    end

    it "returns title when no reftext and no xrefstyle" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.title = "Introduction"
      section.xreftext.should eq("Introduction")
    end

    it "returns full xreftext with numbered section" do
      doc = Asciidoctor::Document.new
      doc.attributes["section-refsig"] = "Section"
      section = Asciidoctor::Section.new(doc, numbered: true)
      section.title = "Introduction"
      section.numeral = "1"
      section.sectname = "section"
      section.xreftext("full").should eq("Section 1, \"Introduction\"")
    end

    it "returns short xreftext with numbered section" do
      doc = Asciidoctor::Document.new
      doc.attributes["section-refsig"] = "Section"
      section = Asciidoctor::Section.new(doc, numbered: true)
      section.title = "Introduction"
      section.numeral = "1"
      section.sectname = "section"
      section.xreftext("short").should eq("Section 1")
    end

    it "returns basic xreftext (title only)" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.title = "Introduction"
      section.xreftext("basic").should eq("Introduction")
    end

    it "returns title when xrefstyle is full but section is not numbered" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc)
      section.title = "Introduction"
      section.xreftext("full").should eq("\"Introduction\"")
    end
  end

  # ==========================================================================
  # Integration tests with parsing
  # ==========================================================================
  describe "Integration" do
    it "should parse a document with multiple sections" do
      input = "= Document Title\n\n== First Section\n\nFirst content.\n\n== Second Section\n\nSecond content.\n\n== Third Section\n\nThird content."
      doc = document_from_string(input)
      doc.blocks.size.should eq(3)
      doc.blocks[0].should be_a(Asciidoctor::Section)
      doc.blocks[1].should be_a(Asciidoctor::Section)
      doc.blocks[2].should be_a(Asciidoctor::Section)
    end

    it "should parse nested sections with correct levels" do
      input = "= Document Title\n\n== Level 1\n\n=== Level 2\n\n==== Level 3\n\ncontent"
      doc = document_from_string(input)
      sect1 = doc.blocks[0]
      sect1.should be_a(Asciidoctor::Section)
      sect1.level.should eq(1)
      if sect1.is_a?(Asciidoctor::Section)
        sect1.sections?.should be_true
      end
    end

    it "should assign correct ids to all sections when sectids is set" do
      input = ":sectids:\n\n== First\n\n== Second\n\n== Third"
      doc = document_from_string(input)
      doc.blocks[0].id.should eq("_first")
      doc.blocks[1].id.should eq("_second")
      doc.blocks[2].id.should eq("_third")
    end

    it "should convert sections to HTML with correct heading tags" do
      input = ":sectids:\n\n== Level 1\n\ncontent\n\n=== Level 2\n\ncontent\n\n==== Level 3\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("<h2")
      output.should contain("<h3")
      output.should contain("<h4")
    end

    it "should handle document with no sections" do
      input = "= Document Title\n\nJust a paragraph."
      doc = document_from_string(input)
      doc.blocks.size.should eq(1)
      # Without sections, no preamble is created - content is directly in the document
      doc.blocks[0].context.should eq(:paragraph)
    end

    it "should parse section with attribute references in title" do
      input = "= Document Title\n:product: Crystal\n\n== About {product}\n\ncontent"
      doc = document_from_string(input)
      sect = doc.blocks[0]
      sect.should be_a(Asciidoctor::Section)
      if sect.is_a?(Asciidoctor::Section)
        sect.title.should eq("About Crystal")
      end
    end

    it "should handle multiple sections at different levels" do
      input = "= Title\n\n== A\n\n=== A.1\n\n=== A.2\n\n== B\n\n=== B.1\n\n==== B.1.1\n\n== C"
      doc = document_from_string(input)
      doc.blocks.size.should eq(3)
    end

    it "should convert book doctype with parts" do
      input = "= Book Title\n:doctype: book\n:sectids:\n\n= Part One\n\n== Chapter 1\n\ncontent\n\n= Part Two\n\n== Chapter 2\n\ncontent"
      output = convert_string(input)
      output.should contain("Part One")
      output.should contain("Part Two")
      output.should contain("Chapter 1")
      output.should contain("Chapter 2")
    end

    it "should handle section with role" do
      input = ":sectids:\n\n[.special]\n== My Section\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("special")
      output.should contain("My Section")
    end

    it "should handle section with id shorthand" do
      input = ":sectids:\n\n[#my-id]\n== My Section\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("my-id")
      output.should contain("My Section")
    end

    it "should parse document with preamble and sections" do
      input = "= Title\n\nPreamble text.\n\n== Section One\n\nSection content."
      doc = document_from_string(input)
      doc.blocks.size.should eq(2)
      # With header, parser creates a preamble block wrapping the paragraph
      doc.blocks[0].context.should eq(:preamble)
      doc.blocks[1].context.should eq(:section)
    end

    it "should handle section title with inline formatting" do
      input = ":sectids:\n\n== Section with *bold* text\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("bold")
      output.should contain("<strong>")
    end

    it "should output sect1 class for level 1 section" do
      input = ":sectids:\n\n== My Section\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("sect1")
    end

    it "should output sect2 class for level 2 section" do
      input = ":sectids:\n\n== Parent\n\n=== Child\n\ncontent"
      output = convert_string_to_embedded(input)
      output.should contain("sect2")
    end

    it "should convert document with doctitle" do
      input = "= My Document Title\n\n== Section\n\ncontent"
      doc = document_from_string(input)
      doc.doctitle.should eq("My Document Title")
    end

    it "should convert document with doctype article by default" do
      input = "= My Document\n\n== Section\n\ncontent"
      doc = document_from_string(input)
      doc.doctype.should eq("article")
    end
  end
end
