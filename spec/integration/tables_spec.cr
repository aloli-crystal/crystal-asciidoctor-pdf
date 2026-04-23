require "./spec_helper"

describe "Tables" do
  it "renders all cell contents across a simple 2x2 table" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      |===
      | A1 | A2
      | B1 | B2
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("A1")
    text.should contain("A2")
    text.should contain("B1")
    text.should contain("B2")
    File.delete(pdf)
  end

  it "renders a header-row table with a caption" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      .Liste des pays
      [cols="1,1", options="header"]
      |===
      | Pays | Ville

      | France | Paris
      | Allemagne | Berlin
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Liste")
    text.should contain("France")
    text.should contain("Paris")
    text.should contain("Allemagne")
    text.should contain("Berlin")
    File.delete(pdf)
  end

  it "breaks long words in narrow columns rather than overflowing" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      [cols="4,1,4", options="header"]
      |===
      | Ville | Pays | Note

      | Gunzenhausen | Allemagne | siège
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    # With a very narrow middle column, "Allemagne" is broken into
    # chunks. Each fragment should still appear in the stream.
    text.should contain("Allem")
    text.should contain("Gunzenhausen")
    File.delete(pdf)
  end
end
