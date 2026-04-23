require "./spec_helper"

# Regression suite for non-breaking-space (NBSP) handling across the
# renderer. A `{nbsp}` or `&nbsp;` in the source must:
#   - render visually as a space (no tofu / no literal `&#160;`)
#   - preserve the non-break property in `wrap_text`
#   - flow through every renderer path: paragraph body, table cell,
#     admonition body, list item, document title, PDF metadata.
describe "NBSP handling" do
  it "renders {nbsp} in a paragraph as a space" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      Paris{nbsp}— Meaux fait 50{nbsp}km.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Paris")
    text.should contain("km")
    text.should_not contain("&#160;")
    text.should_not contain("&nbsp;")
    File.delete(pdf)
  end

  it "renders &nbsp; in a paragraph as a space" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      OVH&nbsp;Cloud est un fournisseur.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("OVH")
    text.should contain("Cloud")
    text.should_not contain("&nbsp;")
    File.delete(pdf)
  end

  it "renders {nbsp} inside a table cell" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      [cols="1,1"]
      |===
      | Ville | Distance

      | Meaux | 10{nbsp}km
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Meaux")
    text.should contain("km")
    text.should_not contain("&#160;")
    File.delete(pdf)
  end

  it "renders {nbsp} in an admonition body" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      IMPORTANT: Le tarif est de 100{nbsp}€/mois.
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("IMPORTANT")
    text.should contain("100")
    text.should_not contain("&#160;")
    File.delete(pdf)
  end

  it "renders {nbsp} in an unordered list item" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      * 10{nbsp}km pour Meaux
      * 140{nbsp}km pour Reims
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Meaux")
    text.should contain("Reims")
    text.should_not contain("&#160;")
    File.delete(pdf)
  end

  it "renders {nbsp} in the document title (PDF /Info metadata)" do
    pdf = IntegrationHelper.convert("= 10{nbsp}km de parcours\n\nContent.")
    title = IntegrationHelper.title(pdf)
    title.should_not be_nil
    title.not_nil!.should contain("10")
    title.not_nil!.should contain("km")
    title.not_nil!.should_not contain("&#160;")
    title.not_nil!.should_not contain("&nbsp;")
    File.delete(pdf)
  end
end
