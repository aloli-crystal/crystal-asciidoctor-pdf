require "../spec_helper"

private def create_block(source : String = "") : Asciidoctor::Block
  doc = Asciidoctor::Document.new
  Asciidoctor::Block.new(doc, :paragraph, source: source.empty? ? nil : source.split("\n"))
end

describe Asciidoctor::Substitutors do
  describe "#apply_header_subs" do
    it "applies specialcharacters and attributes substitutions" do
      block = create_block
      result = block.apply_header_subs("Hello <World>")
      result.should contain("&lt;World&gt;")
    end

    it "substitutes attribute references" do
      doc = Asciidoctor::Document.new
      doc.attributes["name"] = "AsciiDoc"
      block = Asciidoctor::Block.new(doc, :paragraph)
      result = block.apply_header_subs("Hello {name}")
      result.should eq("Hello AsciiDoc")
    end
  end

  describe "#apply_normal_subs" do
    it "applies all normal substitutions" do
      block = create_block
      result = block.apply_normal_subs("Hello <World>")
      result.should contain("&lt;World&gt;")
    end

    it "processes bold text" do
      block = create_block
      result = block.apply_normal_subs("This is *bold* text")
      # Bold text should be processed through quotes substitution
      # The result should contain the word 'bold' in some form (possibly wrapped in tags)
      result.should_not eq("This is *bold* text")
    end
  end

  describe "#apply_reftext_subs" do
    it "applies specialcharacters, quotes, and replacements" do
      block = create_block
      result = block.apply_reftext_subs("Hello <World>")
      result.should contain("&lt;World&gt;")
    end
  end

  describe "#extract_callouts" do
    it "extracts callout markers from source" do
      block = create_block
      source = "puts 'hello' <1>\nputs 'world' <2>"
      result, marks = block.extract_callouts(source)
      marks.should_not be_nil
      if marks
        marks.size.should eq(2)
        marks[1]?.should_not be_nil
        marks[2]?.should_not be_nil
      end
    end

    it "returns nil marks when no callouts present" do
      block = create_block
      source = "puts 'hello'\nputs 'world'"
      result, marks = block.extract_callouts(source)
      marks.should be_nil
    end

    it "handles auto-numbered callouts" do
      block = create_block
      source = "line 1 <.>\nline 2 <.>"
      result, marks = block.extract_callouts(source)
      marks.should_not be_nil
      if marks
        marks[1]?.should_not be_nil
        first_mark = marks[1]?.not_nil!
        first_mark[0][1].should eq("1")
      end
    end

    it "strips callout markers from the source" do
      block = create_block
      source = "puts 'hello' <1>"
      result, marks = block.extract_callouts(source)
      result.should_not contain("<1>")
    end
  end

  describe "#resolve_lines_to_highlight" do
    it "resolves a single line number" do
      block = create_block
      result = block.resolve_lines_to_highlight("line1\nline2\nline3", "2")
      result.should eq([2])
    end

    it "resolves a range of lines" do
      block = create_block
      result = block.resolve_lines_to_highlight("line1\nline2\nline3", "1-3")
      result.should eq([1, 2, 3])
    end

    it "resolves a range with double dot notation" do
      block = create_block
      result = block.resolve_lines_to_highlight("line1\nline2\nline3", "1..3")
      result.should eq([1, 2, 3])
    end

    it "resolves negated lines" do
      block = create_block
      result = block.resolve_lines_to_highlight("line1\nline2\nline3", "1-3,!2")
      result.should eq([1, 3])
    end

    it "resolves comma-separated lines" do
      block = create_block
      result = block.resolve_lines_to_highlight("line1\nline2\nline3", "1,3")
      result.should eq([1, 3])
    end

    it "resolves semicolon-separated lines" do
      block = create_block
      result = block.resolve_lines_to_highlight("line1\nline2\nline3", "1;3")
      result.should eq([1, 3])
    end

    it "applies start offset" do
      block = create_block
      result = block.resolve_lines_to_highlight("line1\nline2\nline3", "5,7", start: 5)
      result.should eq([1, 3])
    end

    it "returns sorted results" do
      block = create_block
      result = block.resolve_lines_to_highlight("line1\nline2\nline3", "3,1,2")
      result.should eq([1, 2, 3])
    end
  end

  describe "#restore_callouts" do
    it "restores callout markers into highlighted source" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :listing)
      # Register callouts so read_next_id works
      doc.callouts.register(1)
      doc.callouts.register(2)
      doc.callouts.rewind

      marks = {} of Int32 => Array(Tuple(String?, String))
      marks[1] = [{nil.as(String?), "1"}]
      marks[2] = [{nil.as(String?), "2"}]
      source = "puts 'hello'\nputs 'world'"
      # Should not raise - the method processes callout marks
      result = block.restore_callouts(source, marks)
      result.should be_a(String)
      # After processing, the marks hash should be emptied for matched lines
      marks.has_key?(1).should be_false
      marks.has_key?(2).should be_false
    end
  end

  describe "#highlight_source" do
    it "applies special chars when no syntax highlighter" do
      block = create_block
      result = block.highlight_source("<code>", false)
      result.should eq("&lt;code&gt;")
    end

    it "processes callouts when requested" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :listing)
      doc.callouts.register(1)
      doc.callouts.rewind
      result = block.highlight_source("code <1>", true)
      result.should_not be_empty
    end
  end
end
