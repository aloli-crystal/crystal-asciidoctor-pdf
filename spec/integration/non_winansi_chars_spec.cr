require "./spec_helper"

# Regression for the silent-tofu bug: characters outside the WinAnsi
# encoding (typical: emojis ✅ ❌ 🔴, dingbats ✓ ✗, CJK ideographs)
# used to render as empty rectangles in the PDF with no warning to
# the author. They now render as `?` (visible) and STDERR receives
# a single warning per character per conversion.
describe "Integration · non-WinAnsi characters" do
  it "produces a valid PDF when the source contains emojis" do
    source = <<-ADOC
    = Test emoji
    Sample with ✅ and ❌ inline.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      File.exists?(path).should be_true
      File.size(path).should be > 500
      # The PDF text now contains `?` substitutes (one per emoji),
      # not the raw codepoints.
      text = IntegrationHelper.text(path)
      text.should contain("?")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "leaves WinAnsi text untouched (no `?` substitution)" do
    source = <<-ADOC
    = Test
    Plain ASCII plus accents éàù — €.
    ADOC
    path = IntegrationHelper.convert(source)
    begin
      text = IntegrationHelper.text(path)
      text.should contain("Plain ASCII")
      text.should contain("éàù")
      # No spurious `?` introduced when the source is fully WinAnsi.
      text.should_not contain("?")
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
