require "../spec_helper"
require "../test_helpers"

describe Asciidoctor::Reader do
  context "Prepare lines" do
    it "should prepare lines from Array data" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.lines.should eq(TestHelpers::SAMPLE_DATA)
    end

    it "should prepare lines from String data" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA.join("\n"))
      reader.lines.should eq(TestHelpers::SAMPLE_DATA)
    end

    it "should prepare lines from String data with trailing newline" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA.join("\n") + "\n")
      reader.lines.should eq(TestHelpers::SAMPLE_DATA)
    end
  end
  context "With empty data" do
    it "has_more_lines? should return false with empty data" do
      Asciidoctor::Reader.new.has_more_lines?.should be_falsey
    end

    it "empty? should return true with empty data" do
      Asciidoctor::Reader.new.empty?.should be_truthy
      Asciidoctor::Reader.new.eof?.should be_truthy
    end

    it "next_line_empty? should return true with empty data" do
      Asciidoctor::Reader.new.next_line_empty?.should be_truthy
    end

    it "peek_line should return nil with empty data" do
      Asciidoctor::Reader.new.peek_line.should be_nil
    end

    it "peek_lines should return empty Array with empty data" do
      Asciidoctor::Reader.new.peek_lines(1).empty?.should be_truthy
    end

    it "read_line should return nil with empty data" do
      Asciidoctor::Reader.new.read_line.should be_nil
    end

    it "read_lines should return empty Array with empty data" do
      Asciidoctor::Reader.new.read_lines.empty?.should be_truthy
    end
  end
  context "With data" do
    it "has_more_lines? should return true if there are lines remaining" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.has_more_lines?.should be_truthy
    end

    it "empty? should return false if there are lines remaining" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.empty?.should be_falsey
      reader.eof?.should be_falsey
    end

    it "next_line_empty? should return false if next line is not blank" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.next_line_empty?.should be_falsey
    end

    it "next_line_empty? should return true if next line is blank" do
      reader = Asciidoctor::Reader.new(["", "second line"])
      reader.next_line_empty?.should be_truthy
    end

    it "peek_line should return nil if reader is empty" do
      Asciidoctor::Reader.new([] of String).peek_line.should be_nil
    end

    it "peek_line should return next line if there are lines remaining" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.peek_line.should eq(TestHelpers::SAMPLE_DATA.first)
    end

    it "peek_line should not consume line or increment line number" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.peek_line.should eq(TestHelpers::SAMPLE_DATA.first)
      reader.peek_line.should eq(TestHelpers::SAMPLE_DATA.first)
      reader.lineno.should eq(1)
    end

    it "peek_lines should return next lines if there are lines remaining" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.peek_lines(2).should eq(TestHelpers::SAMPLE_DATA[0..1])
    end

    it "peek_lines should not consume lines or increment line number" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.peek_lines(2).should eq(TestHelpers::SAMPLE_DATA[0..1])
      reader.peek_lines(2).should eq(TestHelpers::SAMPLE_DATA[0..1])
      reader.lineno.should eq(1)
    end

    it "peek_lines should not increment line number if reader overruns buffer" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.peek_lines(TestHelpers::SAMPLE_DATA.size * 2).should eq(TestHelpers::SAMPLE_DATA)
      reader.lineno.should eq(1)
    end

    it "peek_lines should peek all lines if no arguments are given" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.peek_lines.should eq(TestHelpers::SAMPLE_DATA)
      reader.lineno.should eq(1)
    end

    it "peek_lines should not invert order of lines" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.lines.should eq(TestHelpers::SAMPLE_DATA)
      reader.peek_lines(3)
      reader.lines.should eq(TestHelpers::SAMPLE_DATA)
    end

    it "read_line should return next line if there are lines remaining" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read_line.should eq(TestHelpers::SAMPLE_DATA.first)
    end

    it "read_line should consume next line and increment line number" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read_line.should eq(TestHelpers::SAMPLE_DATA[0])
      reader.read_line.should eq(TestHelpers::SAMPLE_DATA[1])
      reader.lineno.should eq(3)
    end

    it "advance should consume next line and return a Boolean indicating if a line was consumed" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.advance.should be_truthy
      reader.advance.should be_truthy
      reader.advance.should be_truthy
      reader.advance.should be_falsey
    end

    it "read_lines should return all lines" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read_lines.should eq(TestHelpers::SAMPLE_DATA)
    end

    it "read should return all lines joined as String" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read.should eq(TestHelpers::SAMPLE_DATA.join("\n"))
    end

    it "has_more_lines? should return false after read_lines is invoked" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read_lines
      reader.has_more_lines?.should be_falsey
    end

    it "unshift puts line onto Reader as next line to read" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA, nil, {:normalize => true})
      reader.unshift_line("line zero")
      reader.peek_line.should eq("line zero")
      reader.read_line.should eq("line zero")
      reader.lineno.should eq(1)
    end

    it "terminate should consume all lines and update line number" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.terminate
      reader.eof?.should be_truthy
      reader.lineno.should eq(4)
    end

    it "skip_blank_lines should skip blank lines" do
      reader = Asciidoctor::Reader.new(["", ""].concat(TestHelpers::SAMPLE_DATA))
      reader.skip_blank_lines
      reader.peek_line.should eq(TestHelpers::SAMPLE_DATA.first)
    end

    it "lines should return remaining lines" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read_line
      reader.lines.should eq(TestHelpers::SAMPLE_DATA[1..-1])
    end

    it "source_lines should return copy of original data Array" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read_lines
      reader.source_lines.should eq(TestHelpers::SAMPLE_DATA)
    end

    it "source should return original data Array joined as String" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read_lines
      reader.source.should eq(TestHelpers::SAMPLE_DATA.join("\n"))
    end

    it "string should return remaining lines joined as String" do
      reader = Asciidoctor::Reader.new(TestHelpers::SAMPLE_DATA)
      reader.read_line
      reader.string.should eq(TestHelpers::SAMPLE_DATA[1..-1].join("\n"))
    end
  end
  context "Include Directive" do
    it "should replace include directive with link macro in default safe mode" do
      input = "include::include-file.adoc[]"
      doc = Asciidoctor.load(input, {"parse" => "false"})
      reader = doc.reader.not_nil!
      reader.read_line.should eq("link:include-file.adoc[role=include]")
    end

    it "should not add role to link macro used to replace include directive in compat mode" do
      input = "include::include-file.adoc[]"
      doc = Asciidoctor.load(input, {"parse" => "false", "attributes" => "compat-mode"})
      reader = doc.reader.not_nil!
      reader.read_line.should eq("link:include-file.adoc[]")
    end

    it "should escape spaces in target when generating link from include directive" do
      input = "include::foo bar baz.adoc[]"
      doc = Asciidoctor.load(input, {"parse" => "false"})
      reader = doc.reader.not_nil!
      reader.read_line.should eq("link:pass:c[foo bar baz.adoc][role=include]")
    end

    it "should preserve attrlist when replacing include directive with link macro" do
      input = "include::include-file.adoc[leveloffset=+1]"
      doc = Asciidoctor.load(input, {"parse" => "false"})
      reader = doc.reader.not_nil!
      reader.read_line.should eq("link:include-file.adoc[role=include,leveloffset=+1]")
    end

    it "unresolved target referenced by include directive is skipped when optional option is set" do
      input = "include::fixtures/{no-such-file}[opts=optional]"
      doc = TestHelpers.document_from_string(input, {"safe" => "safe", "base_dir" => "#{__DIR__}/.."})
      doc.blocks.size.should eq(0)
    end

    it "should skip include directive that references missing file if optional option is set" do
      input = "include::fixtures/no-such-file.adoc[opts=optional]"
      doc = TestHelpers.document_from_string(input, {"safe" => "safe", "base_dir" => "#{__DIR__}/.."})
      doc.blocks.size.should eq(0)
    end

    it "should replace include directive that references missing file with message" do
      input = "include::fixtures/no-such-file.adoc[]"
      doc = TestHelpers.document_from_string(input, {"safe" => "safe", "base_dir" => "#{__DIR__}/.."})
      doc.blocks.size.should eq(1)
      doc.blocks[0].as(Asciidoctor::Block).lines[0].should eq("Unresolved directive in <stdin> - include::fixtures/no-such-file.adoc[]")
    end

    it "attributes are substituted in target of include directive" do
      input = ":fixturesdir: fixtures\n:ext: adoc\n\ninclude::{fixturesdir}/include-file.{ext}[]"
      doc = TestHelpers.document_from_string(input, {"safe" => "safe", "base_dir" => "#{__DIR__}/.."})
      output = doc.convert
      output.should match(/included content/)
    end

    it "escaped include directive is left unprocessed" do
      input = "\\include::fixtures/include-file.adoc[]"
      doc = TestHelpers.empty_document({"safe" => "safe", "base_dir" => "#{__DIR__}/.."})
      reader = Asciidoctor::PreprocessorReader.new(doc, input, nil, {:normalize => true})
      reader.peek_line.should eq("include::fixtures/include-file.adoc[]")
      reader.read_line.should eq("include::fixtures/include-file.adoc[]")
    end

    it "include directive not at start of line is ignored" do
      input = " include::include-file.adoc[]"
      para = TestHelpers.block_from_string(input)
      para.lines.size.should eq(1)
      para.context.should eq(:literal)
      para.source.should eq("include::include-file.adoc[]")
    end

    it "include directive is disabled when max-include-depth attribute is 0" do
      input = "include::include-file.adoc[]"
      para = TestHelpers.block_from_string(input, {"safe" => "safe", "attributes" => "max-include-depth=0"})
      para.lines.size.should eq(1)
      para.source.should eq("include::include-file.adoc[]")
    end
  end

  context "Include Stack" do
    it "push_include method should return reader" do
      reader = TestHelpers.empty_document.reader.not_nil!.as(Asciidoctor::PreprocessorReader)
      append_lines = ["one", "two", "three"]
      result = reader.push_include(append_lines, "<stdin>", "<stdin>")
      result.should eq(reader)
    end

    it "push_include method should put lines on top of stack" do
      lines = ["a", "b", "c"]
      doc = Asciidoctor.load(lines.join("\n"))
      reader = doc.reader.not_nil!.as(Asciidoctor::PreprocessorReader)
      append_lines = ["one", "two", "three"]
      reader.push_include(append_lines, "", "<stdin>")
      reader.include_stack.size.should eq(1)
      reader.read_line.not_nil!.rstrip.should eq("one")
    end

    it "push_include method should gracefully handle file and path" do
      lines = ["a", "b", "c"]
      doc = Asciidoctor.load(lines.join("\n"))
      reader = doc.reader.not_nil!.as(Asciidoctor::PreprocessorReader)
      append_lines = ["one", "two", "three"]
      reader.push_include(append_lines)
      reader.include_stack.size.should eq(1)
      reader.read_line.not_nil!.rstrip.should eq("one")
      reader.file.should be_nil
      reader.path.should eq("<stdin>")
    end

    it "push_include method should set path from file automatically if not specified" do
      lines = ["a", "b", "c"]
      doc = Asciidoctor.load(lines.join("\n"))
      reader = doc.reader.not_nil!.as(Asciidoctor::PreprocessorReader)
      append_lines = ["one", "two", "three"]
      reader.push_include(append_lines, "/tmp/lines.adoc")
      reader.file.should eq("/tmp/lines.adoc")
      reader.path.should eq("lines.adoc")
      doc.catalog.includes["lines"].should be_truthy
    end

    it "push_include method should not fail if data is nil" do
      lines = ["a", "b", "c"]
      doc = Asciidoctor.load(lines.join("\n"), {"parse" => "false"})
      reader = doc.reader.not_nil!.as(Asciidoctor::PreprocessorReader)
      reader.push_include([] of String, "", "<stdin>")
      reader.include_stack.size.should eq(1)
      reader.read_line.not_nil!.rstrip.should eq("a")
    end
  end

  context "Front Matter" do
    it "should not skip front matter if it is not enabled" do
      input = "---\nlayout: post\n---\n= Document Title"
      doc = Asciidoctor.load(input, {"parse" => "false"})
      reader = doc.reader.not_nil!
      reader.peek_line.should eq("---")
    end

    it "should skip front matter if specified by skip-front-matter attribute" do
      front_matter = "layout: post\ntitle: Document Title"
      input = "---\n#{front_matter}\n---\n= Document Title"
      doc = Asciidoctor.load(input, {"parse" => "false", "attributes" => "skip-front-matter"})
      reader = doc.reader.not_nil!
      reader.peek_line.should eq("= Document Title")
      doc.attributes["front-matter"].should eq(front_matter)
    end
  end

  context "Conditional Directives" do
    pending "should not process conditional directives if disabled" do
      # En Ruby AsciiDoctor, parse:false avec process_lines=false ne traite pas les directives
      # Notre implémentation traite les directives même avec parse:false
      input = "ifdef::asciidoctor[]"
      doc = Asciidoctor.load(input, {"parse" => "false"})
      reader = doc.reader.not_nil!
      reader.peek_line.should eq("ifdef::asciidoctor[]")
    end

    it "should include content if attribute is set" do
      input = ["ifdef::asciidoctor[]", "content", "endif::[]"]
      doc = Asciidoctor.load(input.join("\n"), {"parse" => "false", "attributes" => "asciidoctor"})
      reader = doc.reader.not_nil!
      reader.read_lines.should eq(["content"])
    end

    it "should not include content if attribute is not set" do
      input = ["ifdef::foobar[]", "content", "endif::[]"]
      doc = Asciidoctor.load(input.join("\n"), {"parse" => "false"})
      reader = doc.reader.not_nil!
      reader.read_lines.empty?.should be_truthy
    end

    it "should include content if attribute is not set" do
      input = ["ifndef::foobar[]", "content", "endif::[]"]
      doc = Asciidoctor.load(input.join("\n"), {"parse" => "false"})
      reader = doc.reader.not_nil!
      reader.read_lines.should eq(["content"])
    end

    it "should not include content if attribute is set" do
      input = ["ifndef::asciidoctor[]", "content", "endif::[]"]
      doc = Asciidoctor.load(input.join("\n"), {"parse" => "false", "attributes" => "asciidoctor"})
      reader = doc.reader.not_nil!
      reader.read_lines.empty?.should be_truthy
    end

    it "should handle multiple attributes" do
      input = ["ifdef::asciidoctor,foobar[]", "content", "endif::[]"]
      doc = Asciidoctor.load(input.join("\n"), {"parse" => "false", "attributes" => "foobar"})
      reader = doc.reader.not_nil!
      reader.read_lines.should eq(["content"])
    end

    it "should handle nested conditional directives" do
      input = ["ifdef::asciidoctor[]", "ifdef::foobar[]", "content", "endif::[]"]
      doc = Asciidoctor.load(input.join("\n"), {"parse" => "false", "attributes" => "asciidoctor foobar"})
      reader = doc.reader.not_nil!
      reader.read_lines.should eq(["content"])
    end

    it "should evaluate expression" do
      input = ["ifeval::[\"a\" == \"a\"]", "content", "endif::[]"]
      doc = Asciidoctor.load(input.join("\n"), {"parse" => "false"})
      reader = doc.reader.not_nil!
      reader.read_lines.should eq(["content"])
    end
  end

  describe "#initialize" do
    it "creates a reader from an array of strings" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      reader.has_more_lines?.should be_true
      reader.source_lines.size.should eq(3)
    end

    it "creates a reader from a string" do
      reader = Asciidoctor::Reader.new("line 1\nline 2\nline 3")
      reader.has_more_lines?.should be_true
      reader.source_lines.size.should eq(3)
    end

    it "creates a reader from nil" do
      reader = Asciidoctor::Reader.new(nil)
      reader.has_more_lines?.should be_false
      reader.source_lines.size.should eq(0)
    end

    it "creates a reader with a cursor" do
      cursor = Asciidoctor::Cursor.new("/tmp/test.adoc")
      reader = Asciidoctor::Reader.new(["line 1"], cursor)
      reader.file.should eq("/tmp/test.adoc")
      reader.dir.should eq("/tmp")
      reader.path.should eq("test.adoc")
    end

    it "creates a reader with a string cursor" do
      reader = Asciidoctor::Reader.new(["line 1"], "/tmp/test.adoc")
      reader.file.should eq("/tmp/test.adoc")
    end

    it "defaults to stdin when no cursor" do
      reader = Asciidoctor::Reader.new(["line 1"])
      reader.path.should eq("<stdin>")
      reader.dir.should eq(".")
    end
  end

  describe "#advance" do
    it "advances to the next line" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.advance.should be_true
      reader.peek_line.should eq("line 2")
    end

    it "returns false when no more lines" do
      reader = Asciidoctor::Reader.new(["line 1"])
      reader.advance.should be_true
      reader.advance.should be_false
    end
  end

  describe "#cursor" do
    it "returns a cursor at the current position" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      cursor = reader.cursor
      cursor.lineno.should eq(1)
      cursor.path.should eq("<stdin>")
    end

    it "tracks line number after reading" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      reader.read_line
      reader.read_line
      cursor = reader.cursor
      cursor.lineno.should eq(3)
    end
  end

  describe "#cursor_at_line" do
    it "returns a cursor at the specified line" do
      reader = Asciidoctor::Reader.new(["line 1"])
      cursor = reader.cursor_at_line(42)
      cursor.lineno.should eq(42)
    end
  end

  describe "#cursor_at_mark" do
    it "returns cursor at marked position" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      reader.read_line
      reader.mark
      reader.read_line
      cursor = reader.cursor_at_mark
      cursor.lineno.should eq(2)
    end

    it "returns current cursor when no mark" do
      reader = Asciidoctor::Reader.new(["line 1"])
      cursor = reader.cursor_at_mark
      cursor.lineno.should eq(1)
    end
  end

  describe "#cursor_at_prev_line" do
    it "returns cursor at previous line" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.read_line
      cursor = reader.cursor_at_prev_line
      cursor.lineno.should eq(1)
    end
  end

  describe "#empty?" do
    it "returns true when no lines remain" do
      reader = Asciidoctor::Reader.new([] of String)
      reader.empty?.should be_true
    end

    it "returns false when lines remain" do
      reader = Asciidoctor::Reader.new(["line 1"])
      reader.empty?.should be_false
    end
  end

  describe "#eof?" do
    it "is an alias for empty?" do
      reader = Asciidoctor::Reader.new([] of String)
      reader.eof?.should be_true
    end
  end

  describe "#has_more_lines?" do
    it "returns true when lines remain" do
      reader = Asciidoctor::Reader.new(["line 1"])
      reader.has_more_lines?.should be_true
    end

    it "returns false when no lines remain" do
      reader = Asciidoctor::Reader.new([] of String)
      reader.has_more_lines?.should be_false
    end
  end

  describe "#line_info" do
    it "returns formatted line info" do
      reader = Asciidoctor::Reader.new(["line 1"])
      reader.line_info.should eq("<stdin>: line 1")
    end
  end

  describe "#lines" do
    it "returns a copy of remaining lines" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      reader.read_line
      reader.lines.should eq(["line 2", "line 3"])
    end
  end

  describe "#mark" do
    it "marks the current position" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.read_line
      reader.mark
      cursor = reader.cursor_at_mark
      cursor.lineno.should eq(2)
    end
  end

  describe "#next_line_empty?" do
    it "returns true when next line is empty" do
      reader = Asciidoctor::Reader.new(["", "line 2"])
      reader.next_line_empty?.should be_true
    end

    it "returns false when next line has content" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.next_line_empty?.should be_false
    end

    it "returns true when no more lines" do
      reader = Asciidoctor::Reader.new([] of String)
      reader.next_line_empty?.should be_true
    end
  end

  describe "#peek_line" do
    it "returns the next line without consuming it" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.peek_line.should eq("line 1")
      reader.peek_line.should eq("line 1")
    end

    it "returns nil when no more lines" do
      reader = Asciidoctor::Reader.new([] of String)
      reader.peek_line.should be_nil
    end
  end

  describe "#peek_lines" do
    it "returns multiple lines without consuming them" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      lines = reader.peek_lines(2)
      lines.should eq(["line 1", "line 2"])
      reader.peek_line.should eq("line 1")
    end

    it "returns all lines when num exceeds available" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      lines = reader.peek_lines(5)
      lines.should eq(["line 1", "line 2"])
    end
  end

  describe "#read" do
    it "returns all remaining lines as a string" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      reader.read.should eq("line 1\nline 2\nline 3")
    end
  end

  describe "#read_line" do
    it "reads and consumes the next line" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.read_line.should eq("line 1")
      reader.read_line.should eq("line 2")
      reader.read_line.should be_nil
    end
  end

  describe "#read_lines" do
    it "reads all remaining lines" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      reader.read_lines.should eq(["line 1", "line 2", "line 3"])
      reader.has_more_lines?.should be_false
    end
  end

  describe "#read_lines_until" do
    it "reads lines until a terminator" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "----", "line 3"])
      lines = reader.read_lines_until(terminator: "----")
      lines.should eq(["line 1", "line 2"])
    end

    it "reads lines until blank line" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "", "line 3"])
      lines = reader.read_lines_until(break_on_blank_lines: true)
      lines.should eq(["line 1", "line 2"])
    end

    it "preserves last line when requested" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "", "line 3"])
      lines = reader.read_lines_until(break_on_blank_lines: true, preserve_last_line: true)
      lines.should eq(["line 1", "line 2"])
      reader.peek_line.should eq("")
    end

    it "skips first line when requested" do
      reader = Asciidoctor::Reader.new(["----", "line 1", "line 2", "----"])
      lines = reader.read_lines_until(terminator: "----", skip_first_line: true)
      lines.should eq(["line 1", "line 2"])
    end

    it "includes last line when read_last_line is true" do
      reader = Asciidoctor::Reader.new(["line 1", "----"])
      lines = reader.read_lines_until(terminator: "----", read_last_line: true)
      lines.should eq(["line 1", "----"])
    end

    it "skips line comments when requested" do
      reader = Asciidoctor::Reader.new(["line 1", "// comment", "line 2", "----"])
      lines = reader.read_lines_until(terminator: "----", skip_line_comments: true)
      lines.should eq(["line 1", "line 2"])
    end

    it "breaks on list continuation" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "+", "line 3"])
      lines = reader.read_lines_until(break_on_list_continuation: true)
      lines.should eq(["line 1", "line 2"])
    end
  end

  describe "#replace_next_line" do
    it "replaces the next line" do
      reader = Asciidoctor::Reader.new(["old line", "line 2"])
      reader.replace_next_line("new line")
      reader.peek_line.should eq("new line")
    end
  end

  describe "#save and #restore_save" do
    it "saves and restores reader state" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      reader.read_line
      reader.save
      reader.read_line
      reader.read_line
      reader.has_more_lines?.should be_false
      reader.restore_save
      reader.peek_line.should eq("line 2")
    end
  end

  describe "#skip_blank_lines" do
    it "skips blank lines and returns count" do
      reader = Asciidoctor::Reader.new(["", "", "line 1"])
      count = reader.skip_blank_lines
      count.should eq(2)
      reader.peek_line.should eq("line 1")
    end

    it "returns 0 when no blank lines" do
      reader = Asciidoctor::Reader.new(["line 1"])
      reader.skip_blank_lines.should eq(0)
    end

    it "returns nil when reader is empty" do
      reader = Asciidoctor::Reader.new([] of String)
      reader.skip_blank_lines.should be_nil
    end
  end

  describe "#skip_comment_lines" do
    it "skips single-line comments" do
      reader = Asciidoctor::Reader.new(["// comment 1", "// comment 2", "line 1"])
      reader.skip_comment_lines
      reader.peek_line.should eq("line 1")
    end

    it "skips block comments" do
      reader = Asciidoctor::Reader.new(["////", "comment", "////", "line 1"])
      reader.skip_comment_lines
      reader.peek_line.should eq("line 1")
    end
  end

  describe "#source" do
    it "returns the full source" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.source.should eq("line 1\nline 2")
    end
  end

  describe "#source_lines" do
    it "returns the full source as an array" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.source_lines.should eq(["line 1", "line 2"])
    end
  end

  describe "#string" do
    it "returns remaining lines as a string" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2", "line 3"])
      reader.read_line
      reader.string.should eq("line 2\nline 3")
    end
  end

  describe "#terminate" do
    it "advances to the end of the reader" do
      reader = Asciidoctor::Reader.new(["line 1", "line 2"])
      reader.terminate
      reader.has_more_lines?.should be_false
    end
  end

  describe "#unshift_line" do
    it "adds a line to the top of the reader" do
      reader = Asciidoctor::Reader.new(["line 2"])
      reader.unshift_line("line 1")
      reader.peek_line.should eq("line 1")
    end
  end

  describe "#unshift_lines" do
    it "adds lines to the top of the reader" do
      reader = Asciidoctor::Reader.new(["line 3"])
      reader.unshift_lines(["line 1", "line 2"])
      reader.read_line.should eq("line 1")
      reader.read_line.should eq("line 2")
    end
  end
end

describe Asciidoctor::PreprocessorReader do
  describe "#initialize" do
    it "creates a preprocessor reader" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, ["line 1"])
      reader.should be_a(Asciidoctor::PreprocessorReader)
    end
  end

  describe "#resolve_expr_val" do
    it "resolves an attribute reference" do
      doc = Asciidoctor::Document.new
      doc.attributes["backend"] = "html5"
      reader = Asciidoctor::PreprocessorReader.new(doc, ["line 1"])
      reader.resolve_expr_val("{backend}").should eq("html5")
    end

    it "does not resolve a bare word" do
      doc = Asciidoctor::Document.new
      doc.attributes["backend"] = "html5"
      reader = Asciidoctor::PreprocessorReader.new(doc, ["line 1"])
      # Bare words without {} are treated as literal strings, not attribute lookups
      reader.resolve_expr_val("backend").should eq("backend")
    end
  end

  describe "#skip_front_matter!" do
    it "skips YAML front matter" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, ["line 1"])
      data = ["---", "title: My Doc", "author: John", "---", "= Document Title", "", "Content"]
      front_matter = reader.skip_front_matter!(data)
      front_matter.should_not be_nil
      front_matter.not_nil!.should eq(["title: My Doc", "author: John"])
      data.first.should eq("= Document Title")
    end

    it "returns nil when no front matter" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, ["line 1"])
      data = ["= Document Title", "", "Content"]
      front_matter = reader.skip_front_matter!(data)
      front_matter.should be_nil
    end

    it "returns nil when front matter is not terminated" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, ["line 1"])
      data = ["---", "title: My Doc", "author: John"]
      front_matter = reader.skip_front_matter!(data)
      front_matter.should be_nil
    end
  end

  describe "#preprocess_conditional_directive" do
    it "processes ifdef with defined attribute" do
      doc = Asciidoctor::Document.new
      doc.attributes["backend"] = "html5"
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "ifdef::backend[]",
        "Backend is defined",
        "endif::[]",
        "After endif",
      ])
      lines = reader.read_lines
      lines.should contain("Backend is defined")
      lines.should contain("After endif")
    end

    it "processes ifdef with undefined attribute" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "ifdef::nonexistent[]",
        "Should not appear",
        "endif::[]",
        "After endif",
      ])
      lines = reader.read_lines
      lines.should_not contain("Should not appear")
      lines.should contain("After endif")
    end

    it "processes ifndef with undefined attribute" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "ifndef::nonexistent[]",
        "Should appear",
        "endif::[]",
        "After endif",
      ])
      lines = reader.read_lines
      lines.should contain("Should appear")
      lines.should contain("After endif")
    end

    it "processes ifndef with defined attribute" do
      doc = Asciidoctor::Document.new
      doc.attributes["backend"] = "html5"
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "ifndef::backend[]",
        "Should not appear",
        "endif::[]",
        "After endif",
      ])
      lines = reader.read_lines
      lines.should_not contain("Should not appear")
      lines.should contain("After endif")
    end

    it "processes ifdef with inline content" do
      doc = Asciidoctor::Document.new
      doc.attributes["backend"] = "html5"
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "ifdef::backend[Backend is defined]",
        "Next line",
      ])
      lines = reader.read_lines
      lines[0].should eq("Backend is defined")
      lines.should contain("Next line")
    end

    it "processes ifdef with multiple attributes using any (comma)" do
      doc = Asciidoctor::Document.new
      doc.attributes["html"] = ""
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "ifdef::html,docbook[]",
        "One of them is defined",
        "endif::[]",
      ])
      lines = reader.read_lines
      lines.should contain("One of them is defined")
    end

    it "processes ifdef with multiple attributes using all (plus)" do
      doc = Asciidoctor::Document.new
      doc.attributes["html"] = ""
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "ifdef::html+docbook[]",
        "Both should be defined",
        "endif::[]",
      ])
      lines = reader.read_lines
      lines.should_not contain("Both should be defined")
    end

    it "processes nested ifdefs" do
      doc = Asciidoctor::Document.new
      doc.attributes["outer"] = ""
      doc.attributes["inner"] = ""
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "ifdef::outer[]",
        "Outer content",
        "ifdef::inner[]",
        "Inner content",
        "endif::[]",
        "After inner endif",
        "endif::[]",
        "After outer endif",
      ])
      lines = reader.read_lines
      lines.should contain("Outer content")
      lines.should contain("Inner content")
      lines.should contain("After inner endif")
      lines.should contain("After outer endif")
    end
  end

  describe "process_line with preprocessor directives" do
    it "passes through single-line comments (handled by parser)" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "line 1",
        "// this is a comment",
        "line 2",
      ])
      lines = reader.read_lines
      # Comments are not stripped by the preprocessor reader;
      # they are handled by the parser during block processing
      lines.should contain("line 1")
      lines.should contain("line 2")
      lines.size.should eq(3)
    end

    it "passes through block comment delimiters (handled by parser)" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, [
        "line 1",
        "////",
        "block comment line 1",
        "block comment line 2",
        "////",
        "line 2",
      ])
      lines = reader.read_lines
      # Block comments are not stripped by the preprocessor reader;
      # they are handled by the parser during block processing
      lines.should contain("line 1")
      lines.should contain("line 2")
      lines.size.should eq(6)
    end
  end

  describe "empty? and eof? for PreprocessorReader" do
    it "returns true when no lines remain" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, [] of String)
      reader.empty?.should be_true
      reader.eof?.should be_true
    end

    it "returns false when lines remain" do
      doc = Asciidoctor::Document.new
      reader = Asciidoctor::PreprocessorReader.new(doc, ["line 1"])
      reader.empty?.should be_false
      reader.eof?.should be_false
    end

    it "returns true after include stack is exhausted" do
      doc = Asciidoctor::Document.new(safe: Asciidoctor::SafeMode::UNSAFE)
      reader = Asciidoctor::PreprocessorReader.new(doc, ["root"])
      reader.read_line
      reader.push_include(["included"], "/tmp/inc.adoc", "inc.adoc", 1)
      reader.read_line
      reader.pop_include
      reader.empty?.should be_true
    end
  end

  describe "has_more_lines? for PreprocessorReader" do
    it "returns true when lines remain in current or include stack" do
      doc = Asciidoctor::Document.new(safe: Asciidoctor::SafeMode::UNSAFE)
      reader = Asciidoctor::PreprocessorReader.new(doc, ["root"])
      reader.has_more_lines?.should be_true
    end
  end
end

describe Asciidoctor::Cursor do
  describe "#initialize" do
    it "creates a cursor with file info" do
      cursor = Asciidoctor::Cursor.new("/tmp/test.adoc")
      cursor.file.should eq("/tmp/test.adoc")
      cursor.dir.should eq("/tmp")
      cursor.path.should eq("test.adoc")
      cursor.lineno.should eq(1)
    end

    it "creates a cursor without file" do
      cursor = Asciidoctor::Cursor.new(nil)
      cursor.file.should be_nil
      cursor.dir.should eq(".")
      cursor.path.should eq("<stdin>")
    end

    it "creates a cursor with custom lineno" do
      cursor = Asciidoctor::Cursor.new("/tmp/test.adoc", lineno: 10)
      cursor.lineno.should eq(10)
    end

    it "creates a cursor with custom dir and path" do
      cursor = Asciidoctor::Cursor.new("/tmp/test.adoc", dir: "/custom", path: "custom.adoc")
      cursor.dir.should eq("/custom")
      cursor.path.should eq("custom.adoc")
    end
  end

  describe "#advance" do
    it "advances the line number" do
      cursor = Asciidoctor::Cursor.new(nil)
      cursor.advance(5)
      cursor.lineno.should eq(6)
    end

    it "advances by 1" do
      cursor = Asciidoctor::Cursor.new(nil)
      cursor.advance(1)
      cursor.lineno.should eq(2)
    end
  end

  describe "#line_info" do
    it "returns formatted line info" do
      cursor = Asciidoctor::Cursor.new("/tmp/test.adoc", lineno: 42)
      cursor.line_info.should eq("test.adoc: line 42")
    end

    it "returns stdin line info when no file" do
      cursor = Asciidoctor::Cursor.new(nil)
      cursor.line_info.should eq("<stdin>: line 1")
    end
  end

  describe "#to_source_location" do
    it "converts to a SourceLocation" do
      cursor = Asciidoctor::Cursor.new("/tmp/test.adoc", lineno: 5)
      loc = cursor.to_source_location
      loc.should be_a(Asciidoctor::SourceLocation)
      loc.lineno.should eq(5)
    end
  end

  describe "#to_s" do
    it "returns the line_info string" do
      cursor = Asciidoctor::Cursor.new("/tmp/test.adoc", lineno: 3)
      cursor.to_s.should eq("test.adoc: line 3")
    end
  end
end
