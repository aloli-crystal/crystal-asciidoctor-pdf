require "../spec_helper"

# Helper methods for tests
def convert_string_to_embedded(input : String) : String
  Asciidoctor.convert(input, {"backend" => "html5", "standalone" => "false"})
end

def convert_string(input : String) : String
  Asciidoctor.convert(input, {"standalone" => "true", "backend" => "html5", "attributes" => "linkcss"})
end

def convert_string_docbook(input : String) : String
  Asciidoctor.convert(input, {"backend" => "docbook5"})
end

def load_string(input : String) : Asciidoctor::Document
  Asciidoctor.load(input, {"backend" => "html5"})
end

describe "Blocks" do
  # =========================================================================
  # Layout Breaks
  # =========================================================================
  describe "Layout Breaks" do
    it "should render horizontal rule" do
      ["'''", "''''", "'''''"].each do |line|
        output = convert_string_to_embedded(line)
        output.should contain("<hr>")
      end
    end

    it "should not render horizontal rule for less than 3 chars" do
      ["'", "''"].each do |line|
        output = convert_string_to_embedded(line)
        output.should_not contain("<hr>")
      end
    end

    it "should render horizontal rule between blocks" do
      output = convert_string_to_embedded("Block above\n\n'''\n\nBlock below")
      output.should contain("<hr>")
      output.should contain("Block above")
      output.should contain("Block below")
    end

    it "should render page break" do
      output = convert_string_to_embedded("page 1\n\n<<<\n\npage 2")
      output.should contain("page-break")
      output.should contain("page 1")
      output.should contain("page 2")
    end
  end

  # =========================================================================
  # Comments
  # =========================================================================
  describe "Comments" do
    it "should not render line comment between paragraphs offset by blank lines" do
      input = "first paragraph\n\n// line comment\n\nsecond paragraph"
      output = convert_string_to_embedded(input)
      output.should_not contain("line comment")
      output.scan("<p>").size.should eq(2)
    end

    it "should not render adjacent line comment between paragraphs" do
      # TODO: line comments within paragraphs not yet stripped
      input = "first line\n// line comment\nsecond line"
      output = convert_string_to_embedded(input)
      output.should_not contain("line comment")
      output.scan("<p>").size.should eq(1)
    end

    it "should not render comment block between paragraphs offset by blank lines" do
      input = "first paragraph\n\n////\nblock comment\n////\n\nsecond paragraph"
      output = convert_string_to_embedded(input)
      output.should_not contain("block comment")
      output.scan("<p>").size.should eq(2)
    end

    it "should not render adjacent comment block between paragraphs" do
      # TODO: adjacent comment blocks not yet properly handled
      input = "first paragraph\n////\nblock comment\n////\nsecond paragraph"
      output = convert_string_to_embedded(input)
      output.should_not contain("block comment")
      output.scan("<p>").size.should eq(2)
    end

    it "can convert with block comment at end of document with trailing newlines" do
      input = "paragraph\n\n////\nblock comment\n////\n\n\n"
      output = convert_string_to_embedded(input)
      output.should_not contain("block comment")
    end

    it "line starting with three slashes should not be line comment" do
      input = "/// not a line comment"
      output = convert_string_to_embedded(input)
      output.strip.should_not be_empty
    end

    it "comment style on paragraph should only skip paragraph" do
      # TODO: [comment] style not yet implemented
      input = "[comment]\nskip\nthis paragraph\n\nnot this text"
      output = convert_string_to_embedded(input)
      output.scan("<p>").size.should eq(1)
      output.should contain("not this text")
    end

    it "comment style on open block should only skip block" do
      input = "[comment]\n--\nskip\n\nthis block\n--\n\nnot this text"
      output = convert_string_to_embedded(input)
      output.should contain("not this text")
    end
  end

  # =========================================================================
  # Sidebar Blocks
  # =========================================================================
  describe "Sidebar Blocks" do
    it "should parse sidebar block" do
      input = "== Section\n\n.Sidebar\n****\nContent goes here\n****"
      output = convert_string(input)
      output.should contain("sidebarblock")
    end
  end

  # =========================================================================
  # Quote and Verse Blocks
  # =========================================================================
  describe "Quote and Verse Blocks" do
    it "should render quote block with no attribution" do
      input = "____\nA famous quote.\n____"
      output = convert_string(input)
      output.should contain("quoteblock")
      output.should contain("<blockquote>")
      output.should contain("A famous quote.")
    end

    it "should render quote block with attribution" do
      # TODO: quote block attribution not yet rendered
      input = "[quote, Famous Person, Famous Book (1999)]\n____\nA famous quote.\n____"
      output = convert_string(input)
      output.should contain("quoteblock")
      output.should contain("attribution")
      output.should contain("Famous Person")
    end

    it "should render quote block with id and role shorthand" do
      input = "[quote#justice-to-all.solidarity, Martin Luther King, Jr.]\n____\nInjustice anywhere is a threat to justice everywhere.\n____"
      output = convert_string_to_embedded(input)
      output.should contain("quoteblock")
    end

    it "should render quote block with complex content" do
      # TODO: admonition inside quote block not yet supported
      input = "____\nA famous quote.\n\nNOTE: _That_ was inspiring.\n____"
      output = convert_string(input)
      output.should contain("quoteblock")
      output.should contain("admonitionblock")
    end

    it "should render markdown-style quote block with single paragraph and no attribution" do
      # TODO: markdown-style quote blocks not yet implemented
      input = "> A famous quote.\n> Some more inspiring words."
      output = convert_string(input)
      output.should contain("quoteblock")
    end

    it "should render lazy markdown-style quote block" do
      # TODO: markdown-style quote blocks not yet implemented
      input = "> A famous quote.\nSome more inspiring words."
      output = convert_string(input)
      output.should contain("quoteblock")
    end

    it "should render markdown-style quote block with multiple paragraphs" do
      # TODO: markdown-style quote blocks not yet implemented
      input = "> A famous quote.\n>\n> Some more inspiring words."
      output = convert_string(input)
      output.should contain("quoteblock")
    end

    it "should render markdown-style quote block with attribution" do
      # TODO: markdown-style quote blocks not yet implemented
      input = "> A famous quote.\n> -- Famous Person, Famous Source"
      output = convert_string(input)
      output.should contain("quoteblock")
      output.should contain("attribution")
    end

    it "should render markdown-style quote block with only attribution" do
      # TODO: markdown-style quote blocks not yet implemented
      input = "> -- Anonymous"
      output = convert_string(input)
      output.should contain("quoteblock")
      output.should contain("Anonymous")
    end

    it "should render quoted paragraph-style quote block with attribution" do
      # TODO: quoted paragraph-style quote blocks not yet implemented
      input = "\"A famous quote.\nSome more inspiring words.\"\n-- Famous Person, Famous Source"
      output = convert_string(input)
      output.should contain("quoteblock")
      output.should contain("attribution")
    end

    it "should render single-line verse block without attribution" do
      input = "[verse]\n____\nA famous verse.\n____"
      output = convert_string(input)
      output.should contain("verseblock")
      output.should contain("<pre")
      output.should contain("A famous verse.")
    end

    it "should render single-line verse block with attribution" do
      # TODO: verse block attribution not yet rendered
      input = "[verse, Famous Poet, Famous Poem]\n____\nA famous verse.\n____"
      output = convert_string(input)
      output.should contain("verseblock")
      output.should contain("attribution")
      output.should contain("Famous Poet")
    end

    it "should render multi-stanza verse block" do
      input = "[verse]\n____\nA famous verse.\n\nStanza two.\n____"
      output = convert_string(input)
      output.should contain("verseblock")
      output.should contain("A famous verse.")
      output.should contain("Stanza two.")
    end

    it "verse block does not contain block elements" do
      input = "[verse]\n____\nA famous verse.\n\n....\nnot a literal\n....\n____"
      output = convert_string_to_embedded(input)
      output.should contain("verseblock")
      output.should_not contain("literalblock")
    end
  end

  # =========================================================================
  # Example Blocks
  # =========================================================================
  describe "Example Blocks" do
    it "can convert example block" do
      input = "====\nThis is an example of an example block.\n\nHow crazy is that?\n===="
      output = convert_string(input)
      output.should contain("exampleblock")
    end

    it "should create details/summary set if collapsible option is set" do
      input = ".Toggle Me\n[%collapsible]\n====\nThis content is revealed when the user clicks the words \"Toggle Me\".\n===="
      output = convert_string_to_embedded(input)
      output.should contain("<details>")
      output.should contain("<summary")
      output.should contain("Toggle Me")
    end

    it "should open details/summary set if collapsible and open options are set" do
      input = ".Toggle Me\n[%collapsible%open]\n====\nThis content is revealed.\n===="
      output = convert_string_to_embedded(input)
      output.should contain("<details")
      output.should contain("open")
      output.should contain("<summary")
    end

    it "should add default summary element if collapsible option is set and title is not specified" do
      input = "[%collapsible]\n====\nThis content is revealed when the user clicks the words \"Details\".\n===="
      output = convert_string_to_embedded(input)
      output.should contain("<details>")
      output.should contain("Details")
    end

    it "should warn if example block is not terminated" do
      input = "outside\n\n====\ninside\n\nstill inside\n\neof"
      output = convert_string_to_embedded(input)
      output.should contain("exampleblock")
    end
  end

  # =========================================================================
  # Admonition Blocks
  # =========================================================================
  describe "Admonition Blocks" do
    it "should render note admonition" do
      input = "NOTE: Remember the oat milk."
      output = convert_string_to_embedded(input)
      output.should contain("admonitionblock")
      output.should contain("note")
      output.should contain("Remember the oat milk.")
    end

    it "should render tip admonition" do
      input = "TIP: Look for the warp under the bridge."
      output = convert_string_to_embedded(input)
      output.should contain("admonitionblock")
      output.should contain("tip")
    end

    it "should render important admonition" do
      input = "IMPORTANT: Don't forget the children!"
      output = convert_string_to_embedded(input)
      output.should contain("admonitionblock")
      output.should contain("important")
    end

    it "should render caution admonition" do
      input = "CAUTION: Slippery when wet."
      output = convert_string_to_embedded(input)
      output.should contain("admonitionblock")
      output.should contain("caution")
    end

    it "should render warning admonition" do
      input = "WARNING: The software has *not* been tested."
      output = convert_string_to_embedded(input)
      output.should contain("admonitionblock")
      output.should contain("warning")
    end

    it "can override caption of admonition block using document attribute" do
      # TODO: tip-caption attribute not yet supported
      input = ":tip-caption: Pro Tip\n\nTIP: Override the caption of an admonition block using an attribute entry"
      output = convert_string_to_embedded(input)
      output.should contain("Pro Tip")
    end

    it "blank caption document attribute should not blank admonition block caption" do
      # TODO: caption attribute handling not yet implemented
      input = ":caption:\n\nTIP: Override the caption of an admonition block using an attribute entry"
      output = convert_string_to_embedded(input)
      output.should contain("Tip")
    end
  end

  # =========================================================================
  # Preformatted Blocks
  # =========================================================================
  describe "Preformatted Blocks" do
    it "should separate adjacent paragraphs and listing into blocks" do
      # TODO: adjacent paragraph/listing separation not yet working
      input = "paragraph 1\n----\nlisting content\n----\nparagraph 2"
      output = convert_string_to_embedded(input)
      output.should contain("listingblock")
      output.scan("<p>").size.should eq(2)
    end

    it "should not crash when converting verbatim block that has no lines" do
      # TODO: empty verbatim blocks not yet handled
      ["----\n----", "....\n...."].each do |input|
        output = convert_string_to_embedded(input)
        output.should contain("<pre>")
      end
    end

    it "should preserve newlines in literal block" do
      # TODO: literal block rendering not yet complete
      input = "....\nline one\n\nline two\n\nline three\n...."
      output = convert_string_to_embedded(input)
      output.should contain("<pre>")
      output.should contain("line one")
      output.should contain("line two")
      output.should contain("line three")
    end

    it "should preserve newlines in listing block" do
      # TODO: listing block rendering not yet complete
      input = "----\nline one\n\nline two\n\nline three\n----"
      output = convert_string_to_embedded(input)
      output.should contain("<pre>")
      output.should contain("line one")
      output.should contain("line two")
      output.should contain("line three")
    end

    it "should process block with CRLF line endings" do
      input = "----\r\nsource line 1\r\nsource line 2\r\n----\r\n"
      output = convert_string_to_embedded(input)
      output.should contain("source line 1")
    end

    it "literal block should honor nowrap option" do
      input = "[options=\"nowrap\"]\n----\nDo not wrap me if I get too long.\n----"
      output = convert_string_to_embedded(input)
      output.should contain("nowrap")
    end

    it "literal block should set nowrap class if prewrap document attribute is disabled" do
      input = ":prewrap!:\n\n----\nDo not wrap me if I get too long.\n----"
      output = convert_string_to_embedded(input)
      output.should contain("nowrap")
    end

    it "should preserve guard in front of callout if icons are not enabled" do
      # TODO: callout rendering not yet implemented
      input = "----\nputs 'Hello, World!' # <1>\nputs 'Goodbye, World ;(' # <2>\n----"
      output = convert_string_to_embedded(input)
      output.should contain("conum")
      output.should contain("(1)")
      output.should contain("(2)")
    end

    it "first character of block title may be a period if not followed by space" do
      input = "..gitignore\n----\n/.bundle/\n/build/\n/Gemfile.lock\n----"
      output = convert_string_to_embedded(input)
      output.should contain(".gitignore")
    end

    it "should not prepend caption to title of listing block with title if listing-caption attribute is not set" do
      input = ".title\n----\nlisting block content\n----"
      output = convert_string_to_embedded(input)
      output.should contain("title")
      output.should_not contain("Listing 1")
    end

    it "should prepend caption specified by listing-caption attribute" do
      input = ":listing-caption: Listing\n\n.title\n----\nlisting block content\n----"
      output = convert_string_to_embedded(input)
      output.should contain("Listing 1. title")
    end

    it "should remove block indent if indent attribute is 0" do
      input = "[indent=\"0\"]\n----\n    def names\n\n      @names.split\n\n    end\n----"
      output = convert_string_to_embedded(input)
      output.should contain("listingblock")
    end
  end

  # =========================================================================
  # Open Blocks
  # =========================================================================
  describe "Open Blocks" do
    it "can convert open block" do
      input = "--\nThis is an open block.\n\nIt can span multiple lines.\n--"
      output = convert_string(input)
      output.should contain("openblock")
    end

    it "open block can contain another block" do
      input = "--\nThis is an open block.\n\nIt can span multiple lines.\n\n____\nIt can hold great quotes like this one.\n____\n--"
      output = convert_string(input)
      output.should contain("openblock")
      output.should contain("quoteblock")
    end
  end

  # =========================================================================
  # Passthrough Blocks
  # =========================================================================
  describe "Passthrough Blocks" do
    it "can parse a passthrough block" do
      input = "++++\nThis is a passthrough block.\n++++"
      doc = load_string(input)
      doc.blocks.size.should be >= 1
      block = doc.blocks[0].as(Asciidoctor::Block)
      block.source.should eq("This is a passthrough block.")
    end

    it "does not perform subs on a passthrough block by default" do
      input = ":type: passthrough\n\n++++\nThis is a '{type}' block.\nhttp://asciidoc.org\nimage:tiger.png[]\n++++"
      output = convert_string_to_embedded(input)
      output.should contain("This is a '{type}' block.")
      output.should contain("http://asciidoc.org")
      output.should contain("image:tiger.png[]")
    end

    it "should strip leading and trailing blank lines when converting raw block" do
      input = "++++\nline above\n++++\n\n++++\n\n\n  first line\n\nlast line\n\n\n++++\n\n++++\nline below\n++++"
      output = convert_string_to_embedded(input)
      output.should contain("line above")
      output.should contain("first line")
      output.should contain("last line")
      output.should contain("line below")
    end
  end

  # =========================================================================
  # Math Blocks
  # =========================================================================
  describe "Math blocks" do
    it "should not crash when converting stem block that has no lines" do
      input = "[stem]\n++++\n++++"
      output = convert_string_to_embedded(input)
      output.should contain("stemblock")
    end

    it "should add LaTeX math delimiters around latexmath block content" do
      input = "[latexmath]\n++++\n\\sqrt{3x-1}+(1+x)^2 < y\n++++"
      output = convert_string_to_embedded(input)
      output.should contain("stemblock")
      output.should contain("\\[")
    end

    it "should not add LaTeX math delimiters if already present" do
      input = "[latexmath]\n++++\n\\[\\sqrt{3x-1}+(1+x)^2 < y\\]\n++++"
      output = convert_string_to_embedded(input)
      output.should contain("stemblock")
    end

    it "should output title for latexmath block if defined" do
      input = ".The Lorenz Equations\n[latexmath]\n++++\n\\begin{aligned}\n\\dot{x} & = \\sigma(y-x)\n\\end{aligned}\n++++"
      output = convert_string_to_embedded(input)
      output.should contain("stemblock")
      output.should contain("The Lorenz Equations")
    end

    it "should output title for asciimath block if defined" do
      input = ".Simple fraction\n[asciimath]\n++++\na//b\n++++"
      output = convert_string_to_embedded(input)
      output.should contain("stemblock")
      output.should contain("Simple fraction")
    end

    it "should add AsciiMath delimiters around asciimath block content" do
      input = "[asciimath]\n++++\nsqrt(3x-1)+(1+x)^2 < y\n++++"
      output = convert_string_to_embedded(input)
      output.should contain("stemblock")
    end
  end

  # =========================================================================
  # Metadata
  # =========================================================================
  describe "Metadata" do
    it "block title above section gets carried over to first block in section" do
      input = ".Title\n== Section\n\nparagraph"
      output = convert_string(input)
      output.should contain("paragraph")
      output.should contain("Title")
    end

    it "empty attribute list should not appear in output" do
      input = "[]\n--\nBlock content\n--"
      output = convert_string_to_embedded(input)
      output.should contain("Block content")
      output.should_not contain("[]")
    end

    it "empty block anchor should not appear in output" do
      # TODO: empty block anchor handling not yet implemented
      input = "[[]]\n--\nBlock content\n--"
      output = convert_string_to_embedded(input)
      output.should contain("Block content")
      output.should_not contain("[[]]")
    end
  end

  # =========================================================================
  # Images
  # =========================================================================
  describe "Images" do
    it "can convert block image with alt text defined in macro" do
      # TODO: image block macro not yet fully rendering alt attribute
      input = "image::images/tiger.png[Tiger]"
      output = convert_string_to_embedded(input)
      output.should contain("imageblock")
      output.should contain("images/tiger.png")
      output.should contain("Tiger")
    end

    it "converts SVG image using img element by default" do
      # TODO: image block macro not yet fully rendering
      input = "image::tiger.svg[Tiger]"
      output = convert_string_to_embedded(input)
      output.should contain("imageblock")
      output.should contain("tiger.svg")
      output.should contain("Tiger")
    end

    it "can convert block image with alt text defined in block attribute above macro" do
      # TODO: image block macro not yet fully rendering
      input = "[Tiger]\nimage::images/tiger.png[]"
      output = convert_string_to_embedded(input)
      output.should contain("imageblock")
      output.should contain("Tiger")
    end

    it "alt text in macro overrides alt text above macro" do
      # TODO: image block macro not yet fully rendering
      input = "[Alt Text]\nimage::images/tiger.png[Tiger]"
      output = convert_string_to_embedded(input)
      output.should contain("Tiger")
    end

    it "should substitute attribute references in alt text defined in image block macro" do
      # TODO: image block macro not yet fully rendering
      input = ":alt-text: Tiger\n\nimage::images/tiger.png[{alt-text}]"
      output = convert_string_to_embedded(input)
      output.should contain("Tiger")
    end

    it "should set direction CSS class on image if float attribute is set" do
      # TODO: image block macro not yet fully rendering
      input = "[float=left]\nimage::images/tiger.png[Tiger]"
      output = convert_string_to_embedded(input)
      output.should contain("imageblock")
      output.should contain("left")
    end

    it "should set text alignment CSS class on image if align attribute is set" do
      # TODO: image block macro not yet fully rendering
      input = "[align=center]\nimage::images/tiger.png[Tiger]"
      output = convert_string_to_embedded(input)
      output.should contain("imageblock")
      output.should contain("text-center")
    end

    it "should pass through image that references uri" do
      # TODO: image block macro not yet fully rendering
      input = ":imagesdir: images\n\nimage::http://asciidoc.org/images/tiger.png[Tiger]"
      output = convert_string_to_embedded(input)
      output.should contain("http://asciidoc.org/images/tiger.png")
      output.should contain("Tiger")
    end

    it "can resolve image relative to imagesdir" do
      # TODO: image block macro not yet fully rendering
      input = ":imagesdir: images\n\nimage::tiger.png[Tiger]"
      output = convert_string_to_embedded(input)
      output.should contain("images/tiger.png")
      output.should contain("Tiger")
    end

    it "should render block image with title" do
      # TODO: image block macro not yet fully rendering
      input = ".A Tiger\nimage::images/tiger.png[Tiger]"
      output = convert_string_to_embedded(input)
      output.should contain("imageblock")
      output.should contain("A Tiger")
    end

    it "should render block image with link" do
      # TODO: image block macro not yet fully rendering
      input = "image::images/tiger.png[Tiger,link=http://example.org]"
      output = convert_string_to_embedded(input)
      output.should contain("imageblock")
      output.should contain("http://example.org")
    end

    it "should render block image with dimensions" do
      # TODO: image block macro not yet fully rendering
      input = "image::images/tiger.png[Tiger,200,100]"
      output = convert_string_to_embedded(input)
      output.should contain("imageblock")
      output.should contain("200")
      output.should contain("100")
    end
  end

  # =========================================================================
  # Media
  # =========================================================================
  describe "Media" do
    it "should detect and convert video macro" do
      input = "video::cats-vs-dogs.avi[]"
      output = convert_string_to_embedded(input)
      output.should contain("cats-vs-dogs.avi")
    end

    it "should detect and convert video macro with positional attributes for poster and dimensions" do
      # TODO: video macro positional attributes not yet fully rendered
      input = "video::cats-vs-dogs.avi[cats-and-dogs.png, 200, 300]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("cats-vs-dogs.avi")
      output.should contain("cats-and-dogs.png")
      output.should contain("200")
      output.should contain("300")
    end

    it "should set direction CSS class on video block if float attribute is set" do
      # TODO: video block float not yet implemented
      input = "video::cats-vs-dogs.avi[cats-and-dogs.png,float=right]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("right")
    end

    it "should set text alignment CSS class on video block if align attribute is set" do
      # TODO: video block align not yet implemented
      input = "video::cats-vs-dogs.avi[cats-and-dogs.png,align=center]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("text-center")
    end

    it "video macro should honor all options" do
      # TODO: video macro options not yet fully implemented
      input = "video::cats-vs-dogs.avi[options=\"autoplay,muted,nocontrols,loop\",preload=\"metadata\"]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("autoplay")
      output.should contain("muted")
      output.should contain("loop")
    end

    it "video macro should add time range anchor with start time if start attribute is set" do
      # TODO: video time range not yet implemented
      input = "video::cats-vs-dogs.avi[start=\"30\"]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("#t=30")
    end

    it "video macro should add time range anchor with end time if end attribute is set" do
      # TODO: video time range not yet implemented
      input = "video::cats-vs-dogs.avi[end=\"30\"]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("#t=,30")
    end

    it "video macro should add time range anchor with start and end time" do
      # TODO: video time range not yet implemented
      input = "video::cats-vs-dogs.avi[start=\"30\",end=\"60\"]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("#t=30,60")
    end

    it "video macro should use imagesdir attribute to resolve target and poster" do
      # TODO: video imagesdir resolution not yet implemented
      input = ":imagesdir: assets\n\nvideo::cats-vs-dogs.avi[cats-and-dogs.png, 200, 300]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("assets/cats-vs-dogs.avi")
    end

    it "video macro should not use imagesdir attribute to resolve target if target is a URL" do
      # TODO: video URL handling not yet implemented
      input = ":imagesdir: assets\n\nvideo::http://example.org/videos/cats-vs-dogs.avi[]"
      output = convert_string_to_embedded(input)
      output.should contain("<video")
      output.should contain("http://example.org/videos/cats-vs-dogs.avi")
    end

    it "video macro should output custom HTML with iframe for vimeo service" do
      # TODO: vimeo service not yet implemented
      input = "video::67480300[vimeo, 400, 300, start=60, options=\"autoplay,muted\"]"
      output = convert_string_to_embedded(input)
      output.should contain("<iframe")
      output.should contain("vimeo.com")
    end

    it "video macro should output custom HTML with iframe for youtube service" do
      # TODO: youtube service not yet implemented
      input = "video::U8GBXvdmHT4[youtube, 640, 360, start=60, options=\"autoplay,muted,modest\"]"
      output = convert_string_to_embedded(input)
      output.should contain("<iframe")
      output.should contain("youtube.com")
    end

    it "should detect and convert audio macro" do
      input = "audio::podcast.mp3[]"
      output = convert_string_to_embedded(input)
      output.should contain("podcast.mp3")
    end

    it "audio macro should resolve relative to imagesdir" do
      # TODO: audio imagesdir resolution not yet implemented
      input = ":imagesdir: assets\n\naudio::podcast.mp3[]"
      output = convert_string_to_embedded(input)
      output.should contain("<audio")
      output.should contain("assets/podcast.mp3")
    end
  end

  # =========================================================================
  # Source Code
  # =========================================================================
  describe "Source code" do
    it "should support fenced code block using backticks" do
      # TODO: fenced code blocks not yet fully implemented
      input = "```\nputs \"Hello, World!\"\n```"
      output = convert_string_to_embedded(input)
      output.should contain("listingblock")
      output.should contain("<code")
    end

    it "should not recognize fenced code blocks with more than three delimiters" do
      # TODO: fenced code block delimiter validation not yet implemented
      input = "````ruby\nputs \"Hello, World!\"\n````\n\n~~~~ javascript\nalert(\"Hello, World!\")\n~~~~"
      output = convert_string_to_embedded(input)
      output.should_not contain("listingblock")
    end

    it "should support fenced code blocks with languages" do
      # TODO: fenced code blocks with languages not yet implemented
      input = "```ruby\nputs \"Hello, World!\"\n```\n\n``` javascript\nalert(\"Hello, World!\")\n```"
      output = convert_string_to_embedded(input)
      output.should contain("listingblock")
      output.should contain("language-ruby")
      output.should contain("language-javascript")
    end

    it "should support fenced code blocks with languages and numbering" do
      # TODO: fenced code blocks with numbering not yet implemented
      input = "```ruby,numbered\nputs \"Hello, World!\"\n```"
      output = convert_string_to_embedded(input)
      output.should contain("listingblock")
      output.should contain("language-ruby")
    end

    it "should allow source style to be specified on literal block" do
      input = "[source]\n....\nconsole.log('Hello, World!')\n...."
      output = convert_string_to_embedded(input)
      output.should contain("listingblock")
    end

    it "should allow source style and language to be specified on literal block" do
      input = "[source,js]\n....\nconsole.log('Hello, World!')\n...."
      output = convert_string_to_embedded(input)
      output.should contain("listingblock")
    end

    it "listing block without an explicit style and with a second positional argument should be promoted to a source block" do
      # TODO: source block promotion not yet implemented
      input = "[,ruby]\n----\nputs 'Hello, Ruby!'\n----"
      doc = load_string(input)
      matches = doc.find_by(context: :listing, style: "source")
      matches.size.should eq(1)
    end

    it "listing block with an explicit style should not be promoted to a source block" do
      input = "[listing,ruby]\n----\nputs 'Hello, Ruby!'\n----"
      doc = load_string(input)
      matches = doc.find_by(context: :listing)
      matches.size.should eq(1)
    end
  end

  # =========================================================================
  # Abstract and Part Intro
  # =========================================================================
  describe "Abstract and Part Intro" do
    it "should make abstract on open block without title a quote block for article" do
      # TODO: abstract block style not yet implemented
      input = "= Article\n\n[abstract]\n--\nThis article is about stuff.\n\nAnd other stuff.\n--\n\n== Section One\n\ncontent"
      output = convert_string(input)
      output.should contain("quoteblock")
      output.should contain("abstract")
    end

    it "should make abstract on open block with title a quote block with title for article" do
      input = "= Article\n\n.My abstract\n[abstract]\n--\nThis article is about stuff.\n--\n\n== Section One\n\ncontent"
      output = convert_string(input)
      output.should contain("abstract")
    end

    it "should allow abstract in document with title if doctype is book" do
      # TODO: abstract block style not yet implemented for book doctype
      input = "= Book\n:doctype: book\n\n[abstract]\nAbstract for book with title is valid"
      output = convert_string(input)
      output.should contain("abstract")
    end
  end

  # =========================================================================
  # Substitutions
  # =========================================================================
  describe "Substitutions" do
    it "processor should not crash if subs are empty" do
      input = "[subs=\",\"]\n....\ncontent\n...."
      doc = load_string(input)
      doc.blocks.size.should be >= 1
    end
  end

  # =========================================================================
  # References
  # =========================================================================
  describe "References" do
    it "should not recognize block anchor that starts with digit" do
      input = "[[3-blind-mice]]\n--\nsee how they run\n--"
      output = convert_string_to_embedded(input)
      output.should contain("3-blind-mice")
    end

    it "should recognize block anchor that starts with colon" do
      input = "[[:idname]]\n--\ncontent\n--"
      output = convert_string_to_embedded(input)
      output.should contain(":idname")
    end
  end

  # =========================================================================
  # Block model tests
  # =========================================================================
  describe "#initialize" do
    it "creates a block with default content model for paragraph" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.context.should eq(:paragraph)
      block.content_model.should eq(Asciidoctor::ContentModel::Simple)
      block.lines.should be_empty
    end

    it "creates a block with default content model for listing" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :listing)
      block.content_model.should eq(Asciidoctor::ContentModel::Verbatim)
    end

    it "creates a block with default content model for image" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :image)
      block.content_model.should eq(Asciidoctor::ContentModel::Empty)
    end

    it "creates a block with source string" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, source: "Hello World")
      block.lines.should eq(["Hello World"])
    end

    it "creates a block with source array" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, source: ["line 1", "line 2"])
      block.lines.should eq(["line 1", "line 2"])
    end

    it "creates a block with custom content model" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :open, content_model: Asciidoctor::ContentModel::Simple)
      block.content_model.should eq(Asciidoctor::ContentModel::Simple)
    end
  end

  describe "#block?" do
    it "returns true" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.block?.should be_true
    end
  end

  describe "#inline?" do
    it "returns false" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.inline?.should be_false
    end
  end

  describe "#source" do
    it "returns the joined lines" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, source: ["line 1", "line 2"])
      block.source.should eq("line 1\nline 2")
    end
  end

  describe "#content" do
    it "returns joined lines for simple content model" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, source: ["Hello", "World"])
      block.content.should eq("Hello\nWorld")
    end

    it "returns nil for empty content model" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :image)
      block.content.should be_nil
    end

    it "strips leading and trailing blank lines for verbatim content" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :listing, source: ["", "code here", "more code", ""])
      block.content.should eq("code here\nmore code")
    end
  end

  describe "#document" do
    it "returns the parent document" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.document.should eq(doc)
    end
  end

  describe "#level" do
    it "inherits level from parent" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.level.should eq(0)
    end
  end
end
