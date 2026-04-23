require "./spec_helper"

describe "Lists" do
  it "renders an unordered list with bullet markers" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      * Premier
      * Deuxième
      * Troisième
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Premier")
    text.should contain("Deuxième")
    text.should contain("Troisième")
    File.delete(pdf)
  end

  it "renders an ordered list with numeric markers" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      . Alpha
      . Bravo
      . Charlie
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Alpha")
    text.should contain("Bravo")
    text.should contain("Charlie")
    text.should match(/1\./)
    text.should match(/2\./)
    text.should match(/3\./)
    File.delete(pdf)
  end

  it "renders a definition list" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      Meaux:: 10 km
      Reims:: 140 km
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Meaux")
    text.should contain("Reims")
    text.should contain("10 km")
    text.should contain("140 km")
    File.delete(pdf)
  end
end
