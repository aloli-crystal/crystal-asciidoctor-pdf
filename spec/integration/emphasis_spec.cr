require "./spec_helper"

describe "Inline emphasis" do
  it "renders bold text" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      Some *bold word* in a sentence.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("bold")
    text.should contain("word")
    text.should contain("sentence")
    File.delete(pdf)
  end

  it "renders italic text" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      Some _italic word_ in a sentence.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("italic")
    text.should contain("word")
    File.delete(pdf)
  end

  it "renders monospaced text" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      Inline `code snippet` here.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("code")
    text.should contain("snippet")
    File.delete(pdf)
  end
end
