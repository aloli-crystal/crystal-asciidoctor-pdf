require "./spec_helper"

describe AsciicrystalPDF::WinAnsi do
  describe ".representable?" do
    it "accepts ASCII printable characters" do
      AsciicrystalPDF::WinAnsi.representable?('a').should be_true
      AsciicrystalPDF::WinAnsi.representable?('Z').should be_true
      AsciicrystalPDF::WinAnsi.representable?('5').should be_true
      AsciicrystalPDF::WinAnsi.representable?(' ').should be_true
    end

    it "accepts Latin-1 supplement (French/German/Spanish accents)" do
      "àéèêïôùçñöüß".each_char do |char|
        AsciicrystalPDF::WinAnsi.representable?(char).should be_true
      end
    end

    it "accepts Windows-1252 extras (em-dash, smart quotes, euro sign)" do
      "—€‘’“”•…".each_char do |char|
        AsciicrystalPDF::WinAnsi.representable?(char).should be_true
      end
    end

    it "rejects emojis (out of WinAnsi)" do
      AsciicrystalPDF::WinAnsi.representable?('✅').should be_false
      AsciicrystalPDF::WinAnsi.representable?('❌').should be_false
      AsciicrystalPDF::WinAnsi.representable?('🔴').should be_false
      AsciicrystalPDF::WinAnsi.representable?('🟢').should be_false
    end

    it "rejects basic dingbats out of WinAnsi" do
      AsciicrystalPDF::WinAnsi.representable?('✓').should be_false
      AsciicrystalPDF::WinAnsi.representable?('✗').should be_false
      AsciicrystalPDF::WinAnsi.representable?('★').should be_false
    end

    it "rejects CJK ideographs" do
      AsciicrystalPDF::WinAnsi.representable?('日').should be_false
      AsciicrystalPDF::WinAnsi.representable?('本').should be_false
    end
  end

  describe ".sanitize" do
    it "leaves a fully WinAnsi string untouched" do
      AsciicrystalPDF::WinAnsi.sanitize("Hello — héllo €").should eq("Hello — héllo €")
    end

    it "replaces every non-WinAnsi char with `?`" do
      AsciicrystalPDF::WinAnsi.sanitize("ok ✅ no ❌").should eq("ok ? no ?")
    end

    it "calls the block once per substituted character (in order of appearance)" do
      collected = [] of Char
      AsciicrystalPDF::WinAnsi.sanitize("a✅b❌c") { |char| collected << char }
      collected.should eq(['✅', '❌'])
    end

    it "calls the block multiple times for repeat occurrences (deduplication is the caller's job)" do
      collected = [] of Char
      AsciicrystalPDF::WinAnsi.sanitize("✅✅✅") { |char| collected << char }
      collected.size.should eq(3)
    end

    it "returns the original string when the input is fully ASCII" do
      AsciicrystalPDF::WinAnsi.sanitize("plain ASCII string 12345").should eq("plain ASCII string 12345")
    end
  end
end
