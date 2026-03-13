require "../spec_helper"

describe "Preamble" do
  it "should create a preamble for a document that has a title and content before the first section" do
    input = "= Title\n\nPreamble paragraph 1.\n\n== First Section\n\nSection paragraph 1."
    output = Asciidoctor.convert(input, {"standalone" => "true", "attributes" => "sectids"})
    output.scan("<p>").size.should eq(2)
    output.should contain("<div id=\"preamble\">")
    output.should contain("<h2 id=\"_first_section\">First Section</h2>")
  end

  it "should render a document with a title and content before the first section" do
    input = "= Title\n\nPreamble paragraph 1.\n\n== First Section\n\nSection paragraph 1."
    output = Asciidoctor.convert(input, {"standalone" => "true"})
    output.scan("<p>").size.should eq(2)
    output.should contain("Preamble paragraph 1.")
    output.should contain("First Section")
    output.should contain("Section paragraph 1.")
  end

  it "title of preface is blank by default in DocBook output" do
    input = "= Document Title\n:doctype: book\n\nPreface content.\n\n== First Section\n\nSection content."
    output = Asciidoctor.convert(input, {"backend" => "docbook5", "attributes" => "doctype=book"})
    output.should contain("<preface>")
    output.should contain("<title></title>")
  end

  it "preface-title attribute is assigned as title of preface in DocBook output" do
    input = "= Document Title\n:doctype: book\n:preface-title: Preface\n\nPreface content.\n\n== First Section\n\nSection content."
    output = Asciidoctor.convert(input, {"backend" => "docbook5", "attributes" => "doctype=book,preface-title=Preface"})
    output.should contain("<title>Preface</title>")
  end

  it "should create a preamble for a document that has a title and a multi-paragraph preamble" do
    input = "= Title\n\nPreamble paragraph 1.\n\nPreamble paragraph 2.\n\n== First Section\n\nSection paragraph 1."
    output = Asciidoctor.convert(input, {"standalone" => "true", "attributes" => "sectids"})
    output.scan("<p>").size.should eq(3)
    output.should contain("<div id=\"preamble\">")
  end

  it "should render a document with a title and multi-paragraph preamble" do
    input = "= Title\n\nPreamble paragraph 1.\n\nPreamble paragraph 2.\n\n== First Section\n\nSection paragraph 1."
    output = Asciidoctor.convert(input, {"standalone" => "true"})
    output.scan("<p>").size.should eq(3)
    output.should contain("Preamble paragraph 1.")
    output.should contain("Preamble paragraph 2.")
    output.should contain("Section paragraph 1.")
  end

  it "should not wrap content in preamble if document has title but no sections" do
    input = "= Title\n\nparagraph"
    output = Asciidoctor.convert(input, {"standalone" => "true"})
    output.scan("<p>").size.should eq(1)
    output.should_not contain("<div id=\"preamble\">")
  end

  it "should render content after title when document has no sections" do
    input = "= Title\n\nparagraph"
    output = Asciidoctor.convert(input, {"standalone" => "true"})
    output.scan("<p>").size.should eq(1)
    output.should contain("paragraph")
  end

  it "should not create a preamble if there is no content before the first section" do
    input = "= Title\n\n== First Section\n\nSection paragraph 1."
    output = Asciidoctor.convert(input, {"standalone" => "true", "attributes" => "sectids"})
    output.scan("<p>").size.should eq(1)
    output.should_not contain("<div id=\"preamble\">")
  end

  it "should render a document with title and section but no preamble content" do
    input = "= Title\n\n== First Section\n\nSection paragraph 1."
    output = Asciidoctor.convert(input, {"standalone" => "true"})
    output.scan("<p>").size.should eq(1)
    output.should contain("First Section")
    output.should contain("Section paragraph 1.")
  end

  it "should not create a preamble if the document has no title" do
    input = "Preamble paragraph 1.\n\n== First Section\n\nSection paragraph 1."
    output = Asciidoctor.convert(input, {"standalone" => "true", "attributes" => "sectids"})
    output.scan("<p>").size.should eq(2)
    output.should_not contain("<div id=\"preamble\">")
  end

  it "should render a document without title that has content before first section" do
    input = "Preamble paragraph 1.\n\n== First Section\n\nSection paragraph 1."
    output = Asciidoctor.convert(input, {"standalone" => "true"})
    output.scan("<p>").size.should eq(2)
    output.should contain("Preamble paragraph 1.")
    output.should contain("Section paragraph 1.")
  end

  it "should create a preamble for a book doctype" do
    input = "= Book\n:doctype: book\n\nBack then...\n\n= Chapter One\n\n[partintro]\nIt was a dark and stormy night...\n\n== Scene One\n\nSomeone's gonna get axed.\n\n= Chapter Two\n\n[partintro]\nThey couldn't believe their eyes when...\n\n== Scene One\n\nThe axe came swinging."
    output = Asciidoctor.convert(input, {"standalone" => "true", "attributes" => "doctype=book"})
    output.should contain("<div id=\"preamble\">")
    output.should contain("Back then")
  end

  it "should output table of contents in preamble if toc-placement attribute value is preamble" do
    input = "= Article\n:toc:\n:toc-placement: preamble\n\nOnce upon a time...\n\n== Section One\n\nIt was a dark and stormy night...\n\n== Section Two\n\nThey couldn't believe their eyes when..."
    output = Asciidoctor.convert(input, {"standalone" => "true", "attributes" => "toc,toc-placement=preamble"})
    output.should contain("<div id=\"preamble\">\n<div id=\"toc\" class=\"toc\">")
  end

  it "should move abstract in implicit preface to info tag when converting to DocBook" do
    # Convertisseur Crystal DocBook5 non encore testé pour les abstracts
    input = "= Document Title\n\n[abstract]\nThis is the abstract.\n\n== Fin"
    ["article", "book"].each do |doctype|
      output = Asciidoctor.convert(input, {"backend" => "docbook5", "attributes" => "doctype=#{doctype}"})
      output.should contain("<abstract>")
    end
  end

  it "should move abstract as first section to info tag when converting to DocBook" do
    # Convertisseur Crystal DocBook5 non encore testé pour les abstracts
    input = "= Document Title\n\n[abstract]\n== Abstract\n\nThis is the abstract.\n\n== Fin"
    output = Asciidoctor.convert(input, {"backend" => "docbook5"})
    output.should contain("<abstract>")
  end

  it "should move abstract in preface section to info tag when converting to DocBook" do
    # Convertisseur Crystal DocBook5 non encore testé pour les abstracts
    input = "= Document Title\n:doctype: book\n\n[preface]\n== Preface\n\n[abstract]\nThis is the abstract.\n\n== Fin"
    output = Asciidoctor.convert(input, {"backend" => "docbook5", "attributes" => "doctype=book"})
    output.should contain("<abstract>")
  end
end
