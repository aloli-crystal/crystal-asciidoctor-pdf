require "./spec_helper"

describe "Section headings" do
  it "renders a simple section title" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Document Title

      == A First Section

      Body content.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("First")
    text.should contain("Section")
    File.delete(pdf)
  end

  it "wraps long titles onto multiple lines instead of truncating" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      == Synthèse : quel hébergeur pour quel usage face aux nouveaux défis réglementaires et techniques
      ADOC
    text = IntegrationHelper.text(pdf)
    # The last word ("techniques") must make it into the PDF, which it
    # would not if the title were truncated at the margin.
    text.should contain("techniques")
    File.delete(pdf)
  end

  it "numbers sections when :sectnums: is enabled" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test
      :sectnums:

      == First

      == Second
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("First")
    text.should contain("Second")
    text.should match(/[12]\b/)
    File.delete(pdf)
  end
end
