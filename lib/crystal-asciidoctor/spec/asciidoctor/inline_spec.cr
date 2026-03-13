require "../spec_helper"

describe Asciidoctor::Inline do
  describe "#initialize" do
    it "creates an inline node" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor, "text")
      inline.context.should eq(:anchor)
      inline.text.should eq("text")
      inline.node_name.should eq("inline_anchor")
    end

    it "creates an inline node with type and target" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor, "text", type: :xref, target: "#section")
      inline.type.should eq(:xref)
      inline.target.should eq("#section")
    end
  end

  describe "#block?" do
    it "returns false" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor)
      inline.block?.should be_false
    end
  end

  describe "#inline?" do
    it "returns true" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor)
      inline.inline?.should be_true
    end
  end

  describe "#content" do
    it "returns the text" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor, "Hello")
      inline.content.should eq("Hello")
    end
  end

  describe "#reftext?" do
    it "returns true for ref type with text" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor, "ref text", type: :ref)
      inline.reftext?.should be_true
    end

    it "returns true for bibref type with text" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor, "bib text", type: :bibref)
      inline.reftext?.should be_true
    end

    it "returns false for xref type" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor, "xref text", type: :xref)
      inline.reftext?.should be_false
    end

    it "returns false when text is nil" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      inline = Asciidoctor::Inline.new(block, :anchor, nil, type: :ref)
      inline.reftext?.should be_false
    end
  end
end
