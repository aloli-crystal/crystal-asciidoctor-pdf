require "./spec_helper"

describe "Document title and PDF /Info" do
  it "writes the plain-text title to the PDF /Info dictionary" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Architecture multi-société

      Content.
      ADOC
    title = IntegrationHelper.title(pdf)
    title.should_not be_nil
    title.not_nil!.should contain("Architecture")
    title.not_nil!.should contain("multi-société")
    title.not_nil!.should_not contain("&amp;")
    title.not_nil!.should_not contain("&lt;")
    File.delete(pdf)
  end

  it "decodes HTML entities in the title (smart apostrophe, em dash)" do
    # Crystal-asciidoctor turns the ASCII apostrophe into &#8217;
    # during HTML rendering. The PDF title must carry the decoded
    # character, not the entity.
    pdf = IntegrationHelper.convert(<<-ADOC)
      = L'héritage d'une entreprise

      Content.
      ADOC
    title = IntegrationHelper.title(pdf)
    title.should_not be_nil
    title.not_nil!.should_not contain("&#8217;")
    title.not_nil!.should_not contain("&amp;")
    File.delete(pdf)
  end

  it "renders the title on the cover page" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Mon Super Document

      Content.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Mon")
    text.should contain("Super")
    text.should contain("Document")
    File.delete(pdf)
  end
end
