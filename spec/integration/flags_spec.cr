require "./spec_helper"

describe "Inline country flags" do
  it "does not emit the raw regional-indicator codepoints as tofu text" do
    # A pair of regional indicators (🇫🇷 = U+1F1EB U+1F1F7) is drawn
    # as an inline SVG — the fallback text should never leak into the
    # text stream unless the SVG lookup failed.
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      🇫🇷 France est un pays.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("France")
    text.should contain("pays")
    # No bracketed ISO fallback expected for a valid code.
    text.should_not contain("[FR]")
    File.delete(pdf)
  end

  it "produces a valid PDF for a table with several flag emojis" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      [cols="1,2", options="header"]
      |===
      | Pays | Description

      | 🇫🇷 France
      | Paris est la capitale.

      | 🇩🇪 Allemagne
      | Berlin est la capitale.

      | 🇧🇷 Brésil
      | Brasília est la capitale.
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("France")
    text.should contain("Allemagne")
    text.should contain("Brésil") # regression: used to hang on this
    text.should contain("Paris")
    text.should contain("Berlin")
    text.should contain("Brasília")
    File.delete(pdf)
  end
end
