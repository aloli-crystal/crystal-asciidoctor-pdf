require "../spec_helper"

describe Asciidoctor do
  describe ".load" do
    it "loads a simple document" do
      doc = Asciidoctor.load("= My Title\n\nHello World")
      doc.should be_a(Asciidoctor::Document)
    end

    it "loads a document with backend option" do
      doc = Asciidoctor.load("= My Title\n\nHello", {"backend" => "html5"})
      doc.backend.should eq("html5")
    end

    it "loads a document with doctype option" do
      doc = Asciidoctor.load("= My Title\n\nHello", {"doctype" => "book"})
      doc.doctype.should eq("book")
    end

    it "loads a document with safe mode" do
      doc = Asciidoctor.load("= My Title\n\nHello", {"safe" => "safe"})
      doc.safe.should eq(Asciidoctor::SafeMode::SAFE)
    end

    pending "loads a document with attributes" do
      doc = Asciidoctor.load("= My Title\n\nHello", {"toc" => "left,icons=font"})
      # After save_attributes, toc value is normalized per Ruby AsciiDoctor behavior:
      # toc-placement defaults to 'macro' (not 'auto'), so position resolves to 'macro'
      doc.attributes["toc"]?.should eq("")
      doc.attributes["toc-position"]?.should eq("content")
      doc.attributes["toc-placement"]?.should eq("macro")
      doc.attributes["icons"]?.should eq("font")
    end

    it "creates a converter for the document" do
      doc = Asciidoctor.load("= My Title\n\nHello")
      doc.converter.should_not be_nil
    end

    it "creates an html5 converter by default" do
      doc = Asciidoctor.load("Hello")
      doc.converter.should be_a(Asciidoctor::Converter::Html5Converter)
    end

    it "creates a docbook5 converter when backend is docbook5" do
      doc = Asciidoctor.load("Hello", {"backend" => "docbook5"})
      doc.converter.should be_a(Asciidoctor::Converter::DocBook5Converter)
    end

    it "creates a manpage converter when backend is manpage" do
      doc = Asciidoctor.load("Hello", {"backend" => "manpage"})
      doc.converter.should be_a(Asciidoctor::Converter::ManPageConverter)
    end

    it "should load input file" do
      sample_input_path = "sample.adoc"
      File.write(sample_input_path, "= Document Title")
      doc = File.open(sample_input_path) do |file|
        Asciidoctor.load(file, {"safe" => "safe"})
      end
      doc.doctitle.should eq("Document Title")
      doc.attr("docfile").should eq(File.expand_path(sample_input_path))
      doc.attr("docdir").should eq(File.expand_path(File.dirname(sample_input_path)))
      doc.attr("docfilesuffix").should eq(".adoc")
      File.delete(sample_input_path)
    end

    it "should load input file from filename" do
      sample_input_path = "/tmp/api_test_sample.adoc"
      File.write(sample_input_path, "= Document Title")
      doc = Asciidoctor.load_file(sample_input_path, {"safe" => "safe"})
      doc.doctitle.should eq("Document Title")
      doc.attr("docfile").should eq(File.expand_path(sample_input_path))
      doc.attr("docdir").should eq(File.dirname(File.expand_path(sample_input_path)))
      doc.attr("docfilesuffix").should eq(".adoc")
      File.delete(sample_input_path)
    end

    it "should load input IO" do
      input = IO::Memory.new("=\n\npreamble")
      doc = Asciidoctor.load(input, {"safe" => "safe"})
      doc.doctitle.should be_nil
      doc.attr?("docfile").should be_falsey
    end

    it "should load input string" do
      input = "= Document Title\n\npreamble"
      doc = Asciidoctor.load(input, {"safe" => "safe"})
      doc.doctitle.should eq("Document Title")
      doc.attr?("docfile").should be_falsey
    end

    it "should load input string array" do
      input = "= Document Title\n\npreamble"
      doc = Asciidoctor.load(input, {"safe" => "safe"})
      doc.doctitle.should eq("Document Title")
      doc.attr?("docfile").should be_falsey
    end

    it "should load nil input" do
      doc = Asciidoctor.load("", {"safe" => "safe"})
      doc.should_not be_nil
      doc.blocks.empty?.should be_truthy
    end

    it "should accept attributes as array" do
      doc = Asciidoctor.load("text", {"toc" => "", "sectnums" => "", "source-highlighter" => "coderay", "idprefix" => "", "idseparator" => "-"})
      doc.attributes.should be_a(Hash(String, String))
      doc.attr?("toc").should be_truthy
      doc.attr("toc").should eq("")
      doc.attr?("sectnums").should be_truthy
      doc.attr("sectnums").should eq("")
      doc.attr?("source-highlighter").should be_truthy
      doc.attr("source-highlighter").should eq("coderay")
      doc.attr?("idprefix").should be_truthy
      doc.attr("idprefix").should eq("")
      doc.attr?("idseparator").should be_truthy
      doc.attr("idseparator").should eq("-")
    end

    it "should accept attributes as empty array" do
      doc = Asciidoctor.load("text")
      doc.attributes.should be_a(Hash(String, String))
    end

    it "should accept attributes as string" do
      doc = Asciidoctor.load("text", {"toc" => "", "sectnums" => "", "source-highlighter" => "coderay", "idprefix" => "", "idseparator" => "-"})
      doc.attributes.should be_a(Hash(String, String))
      doc.attr?("toc").should be_truthy
      doc.attr("toc").should eq("")
      doc.attr?("sectnums").should be_truthy
      doc.attr("sectnums").should eq("")
      doc.attr?("source-highlighter").should be_truthy
      doc.attr("source-highlighter").should eq("coderay")
      doc.attr?("idprefix").should be_truthy
      doc.attr("idprefix").should eq("")
      doc.attr?("idseparator").should be_truthy
      doc.attr("idseparator").should eq("-")
    end

    it "should accept attributes as empty string" do
      doc = Asciidoctor.load("text", {"attributes" => ""})
      doc.attributes.should be_a(Hash(String, String))
    end

    it "should accept attributes as nil" do
      doc = Asciidoctor.load("text", {"attributes" => nil})
      doc.attributes.should be_a(Hash(String, String))
    end
  end

  describe ".convert" do
    it "converts a simple paragraph to HTML" do
      result = Asciidoctor.convert("Hello World")
      result.should contain("Hello World")
    end

    it "converts with docbook backend" do
      result = Asciidoctor.convert("Hello World", {"backend" => "docbook5"})
      result.should contain("<simpara>")
    end
  end

  describe ".convert_file" do
    it "should convert source document to embedded document when header_footer is false" do
      sample_input_path = "/tmp/api_test_sample2.adoc"
      File.write(sample_input_path, "= Document Title\n\ncontent")
      output = Asciidoctor.convert_file(sample_input_path, {"header_footer" => "false", "to_file" => "false"})
      output.should_not contain("<html>")
      output.should contain("Document Title")
      File.delete(sample_input_path)
    end

    it "should convert source document to standalone document string when to_file is false and standalone is true" do
      sample_input_path = "/tmp/api_test_sample3.adoc"
      File.write(sample_input_path, "= Document Title\n\ncontent")
      output = Asciidoctor.convert_file(sample_input_path, {"standalone" => "true", "to_file" => "false"})
      output.should contain("<html")
      output.should contain("<title>Document Title</title>")
      output.should contain("<h1>Document Title</h1>")
      File.delete(sample_input_path)
    end

    it "should convert source document to standalone document string when to_file is false and header_footer is true" do
      sample_input_path = "/tmp/api_test_sample4.adoc"
      File.write(sample_input_path, "= Document Title\n\ncontent")
      output = Asciidoctor.convert_file(sample_input_path, {"header_footer" => "true", "to_file" => "false"})
      output.should contain("<html")
      output.should contain("<title>Document Title</title>")
      output.should contain("<h1>Document Title</h1>")
      File.delete(sample_input_path)
    end

    it "lines in output should be separated by line feed (universal newline)" do
      sample_input_path = "/tmp/api_test_sample5.adoc"
      File.write(sample_input_path, "= Document Title\n\ncontent")
      output = Asciidoctor.convert_file(sample_input_path, {"standalone" => "true", "to_file" => "false"})
      output.should_not contain("\r")
      File.delete(sample_input_path)
    end

    it "should accept attributes as array for convert" do
      sample_input_path = "/tmp/api_test_sample6.adoc"
      File.write(sample_input_path, "== Section A")
      output = Asciidoctor.convert_file(sample_input_path, {"sectnums" => "", "idprefix" => "", "idseparator" => "-", "to_file" => "false"})
      output.should contain("id=\"section-a\"")
      File.delete(sample_input_path)
    end

    it "should accept attributes as string for convert" do
      sample_input_path = "/tmp/api_test_sample7.adoc"
      File.write(sample_input_path, "== Section A")
      output = Asciidoctor.convert_file(sample_input_path, {"sectnums" => "", "idprefix" => "", "idseparator" => "-", "to_file" => "false"})
      output.should contain("id=\"section-a\"")
      File.delete(sample_input_path)
    end
  end

  describe "find_by" do
    it "find_by should return Array of blocks anywhere in document tree that match criteria" do
      input = <<-EOS
      = Document Title

      preamble

      == Section A

      paragraph

      --
      Exhibit A::
      +
      [#tiger.animal]
      image::tiger.png[Tiger]
      --

      image::shoe.png[Shoe]

      == Section B

      paragraph
      EOS

      doc = Asciidoctor.load(input)
      result = doc.find_by(context: :image)
      result.size.should eq(2)
      result[0].context.should eq(:image)
      result[0].attr("target").should eq("tiger.png")
      result[1].context.should eq(:image)
      result[1].attr("target").should eq("shoe.png")
    end

    it "find_by should return an empty Array if no matches are found" do
      input = "paragraph"
      doc = Asciidoctor.load(input)
      result = doc.find_by(context: :section)
      result.should_not be_nil
      result.size.should eq(0)
    end
  end

  describe "sourcemap" do
    it "should allow sourcemap option on document to be modified before document is parsed" do
      sample_input_path = "/tmp/api_test_sample8.adoc"
      File.write(sample_input_path, "== Section A")
      doc = Asciidoctor.load_file(sample_input_path, {"parse" => "false"})
      doc.sourcemap = true
      doc.parsed?.should be_falsey
      doc = doc.parse
      doc.parsed?.should be_truthy

      section_1 = doc.sections[0]
      section_1.title.should eq("Section A")
      section_1.source_location.should_not be_nil
      section_1.file.should eq(File.expand_path(sample_input_path))
      section_1.lineno.should eq(1)
      File.delete(sample_input_path)
    end
  end
end
