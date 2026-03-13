require "./spec_helper"

describe AsciidoctorPDF::Converter do
  it "should convert a simple paragraph" do
    input = "Hello, World."
    output_path = "spec/output/simple_paragraph.pdf"

    doc = Asciidoctor.load(input, options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0

    # Clean up
    File.delete(output_path)
  end
end

  it "should convert a section" do
    input = "== My Section\n\nThis is the content."
    output_path = "spec/output/section.pdf"

    doc = Asciidoctor.load(input, options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0

    # Clean up
    File.delete(output_path)
  end

  it "should convert an unordered list" do
    input = "* one\n* two\n* three"
    output_path = "spec/output/ulist.pdf"

    doc = Asciidoctor.load(input, options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0

    # Clean up
    File.delete(output_path)
  end

  it "should convert an ordered list" do
    input = ". one\. two\. three"
    output_path = "spec/output/olist.pdf"

    doc = Asciidoctor.load(input, options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0

    # Clean up
    File.delete(output_path)
  end

  it "should convert a table" do
    input = "|===\n| Col A | Col B\n| 1     | 2    \n|==="
    output_path = "spec/output/table.pdf"

    doc = Asciidoctor.load(input, options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0

    # Clean up
    File.delete(output_path)
  end
