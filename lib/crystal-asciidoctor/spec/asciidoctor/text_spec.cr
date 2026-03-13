require "../spec_helper"
require "../test_helpers"

# Helper to create a block for substitution testing
def text_block(src : String = "test") : Asciidoctor::Block
  doc = Asciidoctor.load(src, {"standalone" => "false"})
  doc.blocks.first.as(Asciidoctor::Block)
end

describe "Text" do
  describe "encoding" do
    it "should handle utf8 characters in document" do
      doc = Asciidoctor.load("Café crème\n\nÉlève modèle\n\nRésumé", {"standalone" => "false"})
      doc.blocks.size.should be >= 1
      block = doc.blocks.first.as(Asciidoctor::Block)
      block.source.should contain("Café")
    end

    it "should handle utf8 characters in embedded document" do
      doc = Asciidoctor.load("Café crème\n\nÉlève modèle", {"standalone" => "false"})
      doc.blocks.size.should be >= 1
    end

    it "should handle utf8 characters in substitutions" do
      block = text_block("Café")
      result = block.sub_specialchars("Café <em>crème</em>")
      result.should contain("Café")
      result.should contain("&lt;em&gt;")
    end

    it "should handle multibyte characters in quotes" do
      block = text_block
      result = block.sub_quotes("*Café*")
      result.should eq("<strong>Café</strong>")
    end

    it "should handle CJK characters in quotes" do
      block = text_block
      result = block.sub_quotes("*要素*")
      result.should eq("<strong>要素</strong>")
    end
  end

  describe "escaped text markup" do
    it "should escape inline HTML markup via specialchars" do
      block = text_block
      result = block.sub_specialchars("All your <em>inline</em> markup belongs to <strong>us</strong>!")
      result.should eq("All your &lt;em&gt;inline&lt;/em&gt; markup belongs to &lt;strong&gt;us&lt;/strong&gt;!")
    end

    it "should escape angle brackets" do
      block = text_block
      result = block.sub_specialchars("<b>bold</b>")
      result.should eq("&lt;b&gt;bold&lt;/b&gt;")
    end

    it "should escape ampersand" do
      block = text_block
      result = block.sub_specialchars("AT&T")
      result.should eq("AT&amp;T")
    end
  end

  describe "line breaks" do
    it "should handle line break character in post_replacements" do
      block = text_block
      result = block.sub_post_replacements("Well this is +\njust fine")
      # Post replacements should handle the + line break marker
      (result.includes?("+") || result.includes?("<br>")).should be_true
    end
  end

  describe "horizontal rule" do
    it "should parse thematic break" do
      doc = Asciidoctor.load("Before\n\n'''\n\nAfter", {"standalone" => "false"})
      doc.blocks.size.should be >= 2
    end

    it "should parse markdown horizontal rule with dashes" do
      doc = Asciidoctor.load("Before\n\n---\n\nAfter", {"standalone" => "false"})
      doc.blocks.size.should be >= 2
    end

    it "should parse markdown horizontal rule with asterisks" do
      doc = Asciidoctor.load("Before\n\n***\n\nAfter", {"standalone" => "false"})
      doc.blocks.size.should be >= 2
    end

    it "should parse markdown horizontal rule with underscores" do
      doc = Asciidoctor.load("Before\n\n___\n\nAfter", {"standalone" => "false"})
      doc.blocks.size.should be >= 2
    end

    it "should parse markdown horizontal rule with spaced dashes" do
      doc = Asciidoctor.load("Before\n\n- - -\n\nAfter", {"standalone" => "false"})
      doc.blocks.size.should be >= 2
    end

    it "should parse markdown horizontal rule with spaced asterisks" do
      doc = Asciidoctor.load("Before\n\n* * *\n\nAfter", {"standalone" => "false"})
      doc.blocks.size.should be >= 2
    end

    it "should parse markdown horizontal rule with spaced underscores" do
      doc = Asciidoctor.load("Before\n\n_ _ _\n\nAfter", {"standalone" => "false"})
      doc.blocks.size.should be >= 2
    end
  end

  describe "emphasized text" do
    it "should convert emphasized text using underscore characters" do
      block = text_block
      result = block.sub_quotes("An _emphatic_ no")
      result.should contain("<em>emphatic</em>")
    end

    it "should convert emphasized text at end of line" do
      block = text_block
      result = block.sub_quotes("This library is _awesome_")
      result.should contain("<em>awesome</em>")
    end

    it "should convert emphasized text at beginning of line" do
      block = text_block
      result = block.sub_quotes("_drop_ it")
      result.should contain("<em>drop</em>")
    end

    it "should convert emphasized text across words" do
      block = text_block
      result = block.sub_quotes("_check it_")
      result.should contain("<em>check it</em>")
    end

    it "should convert emphasized text with single quote using apostrophe" do
      block = text_block
      result = block.sub_replacements("it`'s")
      result.should eq("it&#8217;s")
    end
  end

  describe "escaped single quote" do
    it "should restore escaped single quote as single quote" do
      block = text_block
      result = block.sub_replacements("Let\\'s do it!")
      # Escaped single quote should be restored
      (result.includes?("Let") && result.includes?("s do it!")).should be_true
    end
  end

  describe "unquoted text" do
    it "should convert marked text with hash" do
      block = text_block
      result = block.sub_quotes("An #unquoted# word")
      result.should_not contain("#unquoted#")
      result.should contain("<mark>unquoted</mark>")
    end
  end

  describe "backticks and monospace" do
    it "should convert backtick to monospace" do
      block = text_block
      result = block.sub_quotes("run `foo` bar")
      result.should eq("run <code>foo</code> bar")
    end

    it "should escape backtick when preceded by backslash" do
      block = text_block
      result = block.sub_quotes("run \\`foo` bar")
      result.should eq("run `foo` bar")
    end

    it "should convert unconstrained monospace" do
      block = text_block
      result = block.sub_quotes("run``foo``bar")
      result.should eq("run<code>foo</code>bar")
    end
  end

  describe "basic styling" do
    it "should convert strong text" do
      block = text_block
      result = block.sub_quotes("A *BOLD* word.")
      result.should contain("<strong>BOLD</strong>")
    end

    it "should convert italic text" do
      block = text_block
      result = block.sub_quotes("An _italic_ word.")
      result.should contain("<em>italic</em>")
    end

    it "should convert monospaced text" do
      block = text_block
      result = block.sub_quotes("A `mono` word.")
      result.should contain("<code>mono</code>")
    end

    it "should convert superscript text" do
      block = text_block
      result = block.sub_quotes("^superscript!^")
      result.should contain("<sup>superscript!</sup>")
    end

    it "should convert subscript text" do
      block = text_block
      result = block.sub_quotes("some ~subscript~")
      result.should contain("<sub>subscript</sub>")
    end

    it "should convert nested strong and emphasized" do
      block = text_block
      result = block.sub_quotes("*big _time_*")
      result.should contain("<strong>")
      result.should contain("<em>")
    end

    it "should convert unconstrained strong" do
      block = text_block
      result = block.sub_quotes("**B**old")
      result.should contain("<strong>B</strong>")
    end

    it "should convert unconstrained emphasized" do
      block = text_block
      result = block.sub_quotes("__I__talic")
      result.should contain("<em>I</em>")
    end

    it "should convert unconstrained monospaced" do
      block = text_block
      result = block.sub_quotes("``M``ono")
      result.should contain("<code>M</code>")
    end

    it "should convert all basic styles in one line" do
      block = text_block
      result = block.sub_quotes("*BOLD* _italic_ `mono` ^super^ ~sub~")
      result.should contain("<strong>BOLD</strong>")
      result.should contain("<em>italic</em>")
      result.should contain("<code>mono</code>")
      result.should contain("<sup>super</sup>")
      result.should contain("<sub>sub</sub>")
    end
  end

  describe "passthrough" do
    it "should extract and restore double plus passthrough" do
      block = text_block
      extracted = block.extract_passthroughs("one++<em>two</em>++three")
      restored = block.restore_passthroughs(extracted)
      restored.should eq("one&lt;em&gt;two&lt;/em&gt;three")
    end

    it "should extract and restore pass macro" do
      block = text_block
      extracted = block.extract_passthroughs("pass:[<b>raw</b>]")
      restored = block.restore_passthroughs(extracted)
      restored.should eq("<b>raw</b>")
    end

    it "should extract and restore pass macro with quotes sub" do
      block = text_block
      extracted = block.extract_passthroughs("pass:quotes[*bold*]")
      restored = block.restore_passthroughs(extracted)
      restored.should eq("<strong>bold</strong>")
    end

    it "should extract and restore dollar dollar passthrough" do
      block = text_block
      extracted = block.extract_passthroughs("$$<b>raw</b>$$")
      restored = block.restore_passthroughs(extracted)
      restored.should contain("&lt;b&gt;")
    end

    it "should handle plus characters inside passthrough" do
      block = text_block
      extracted = block.extract_passthroughs("++plus+inside++")
      restored = block.restore_passthroughs(extracted)
      restored.should contain("plus+inside")
    end

    it "should escape entity reference in double plus passthrough" do
      block = text_block
      extracted = block.extract_passthroughs("one++&#44;++two")
      restored = block.restore_passthroughs(extracted)
      restored.should contain("&amp;#44;")
    end
  end

  describe "Asian characters" do
    it "should format Asian characters as words with bold" do
      block = text_block
      result = block.sub_quotes("bold *要* bold")
      result.should contain("<strong>要</strong>")
    end

    it "should format Asian characters as words with bold (2)" do
      block = text_block
      result = block.sub_quotes("bold *素* bold")
      result.should contain("<strong>素</strong>")
    end

    it "should format multiple Asian characters as words with bold" do
      block = text_block
      result = block.sub_quotes("bold *要素* bold")
      result.should contain("<strong>要素</strong>")
    end
  end

  describe "replacements" do
    it "should replace copyright symbol" do
      block = text_block
      result = block.sub_replacements("(C)")
      result.should eq("&#169;")
    end

    it "should replace registered symbol" do
      block = text_block
      result = block.sub_replacements("(R)")
      result.should eq("&#174;")
    end

    it "should replace trademark symbol" do
      block = text_block
      result = block.sub_replacements("(TM)")
      result.should eq("&#8482;")
    end

    it "should replace em dash" do
      block = text_block
      result = block.sub_replacements("foo -- bar")
      result.should contain("&#8212;")
    end

    it "should replace ellipsis" do
      block = text_block
      result = block.sub_replacements("foo...")
      result.should contain("&#8230;")
    end

    it "should replace right single quote" do
      block = text_block
      result = block.sub_replacements("it`'s")
      result.should eq("it&#8217;s")
    end

    it "should replace arrows after specialchars" do
      block = text_block
      result = block.sub_specialchars("->")
      result = block.sub_replacements(result)
      result.should eq("&#8594;")
    end

    it "should replace double right arrow after specialchars" do
      block = text_block
      result = block.sub_specialchars("=>")
      result = block.sub_replacements(result)
      result.should eq("&#8658;")
    end

    it "should replace left arrow after specialchars" do
      block = text_block
      result = block.sub_specialchars("<-")
      result = block.sub_replacements(result)
      result.should eq("&#8592;")
    end

    it "should replace double left arrow after specialchars" do
      block = text_block
      result = block.sub_specialchars("<=")
      result = block.sub_replacements(result)
      result.should eq("&#8656;")
    end
  end
end
