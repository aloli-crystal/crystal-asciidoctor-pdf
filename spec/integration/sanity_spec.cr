require "./spec_helper"

describe "Integration sanity check" do
  it "produces a non-empty PDF from the most basic AsciiDoc" do
    IntegrationHelper.produces_pdf?("= Hello\n\nWorld.").should be_true
  end
end
