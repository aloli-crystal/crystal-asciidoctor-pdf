require "../spec_helper"

describe Asciidoctor::SourceLocation do
  describe "#initialize" do
    it "creates a source location with file and lineno" do
      loc = Asciidoctor::SourceLocation.new("test.adoc", 42)
      loc.file.should eq("test.adoc")
      loc.lineno.should eq(42)
    end

    it "creates a source location with nil file" do
      loc = Asciidoctor::SourceLocation.new(nil, 1)
      loc.file.should be_nil
      loc.lineno.should eq(1)
    end
  end

  describe "#advance" do
    it "advances the line number by 1 by default" do
      loc = Asciidoctor::SourceLocation.new("test.adoc", 10)
      loc.advance
      loc.lineno.should eq(11)
    end

    it "advances the line number by the specified count" do
      loc = Asciidoctor::SourceLocation.new("test.adoc", 10)
      loc.advance(5)
      loc.lineno.should eq(15)
    end
  end

  describe "#dup" do
    it "returns a copy of the source location" do
      loc = Asciidoctor::SourceLocation.new("test.adoc", 42, "/dir", "path")
      copy = loc.dup
      copy.file.should eq("test.adoc")
      copy.lineno.should eq(42)
      copy.dir.should eq("/dir")
      copy.path.should eq("path")
    end
  end

  describe "#to_s" do
    it "formats with file and line number" do
      loc = Asciidoctor::SourceLocation.new("test.adoc", 42)
      loc.to_s.should eq("test.adoc: line 42")
    end

    it "formats with only line number when file is nil" do
      loc = Asciidoctor::SourceLocation.new(nil, 42)
      loc.to_s.should eq("line 42")
    end
  end
end
