require "../../spec_helper"

describe Asciidoctor::Cli::Options do
  describe "initialization" do
    it "should have default values" do
      opts = Asciidoctor::Cli::Options.new
      opts.backend.should eq("html5")
      opts.doctype.should eq("article")
      opts.standalone.should be_true
      opts.embedded.should be_false
      opts.verbose.should eq(1)
      opts.sourcemap.should be_false
      opts.safe_mode.should eq(Asciidoctor::SafeMode::UNSAFE)
      opts.input_files.should be_empty
      opts.attributes.should be_empty
    end
  end

  describe "parse" do
    it "should parse backend option" do
      opts = Asciidoctor::Cli::Options.parse(["-b", "docbook5"])
      opts.backend.should eq("docbook5")
    end

    it "should parse backend option with equals sign" do
      opts = Asciidoctor::Cli::Options.parse(["--backend=docbook5"])
      opts.backend.should eq("docbook5")
    end

    it "should allow any backend to be specified" do
      opts = Asciidoctor::Cli::Options.parse(["-b", "my_custom_backend"])
      opts.backend.should eq("my_custom_backend")
    end

    it "should parse article doctype" do
      opts = Asciidoctor::Cli::Options.parse(["-d", "article"])
      opts.doctype.should eq("article")
    end

    it "should parse book doctype" do
      opts = Asciidoctor::Cli::Options.parse(["-d", "book"])
      opts.doctype.should eq("book")
    end

    it "should parse inline doctype" do
      opts = Asciidoctor::Cli::Options.parse(["-d", "inline"])
      opts.doctype.should eq("inline")
    end

    it "should parse embedded option with -e flag" do
      opts = Asciidoctor::Cli::Options.parse(["-e"])
      opts.embedded.should be_true
      opts.standalone.should be_false
    end

    it "should parse no-header-footer option with -s flag" do
      opts = Asciidoctor::Cli::Options.parse(["-s"])
      opts.standalone.should be_false
    end

    it "should parse output file option" do
      opts = Asciidoctor::Cli::Options.parse(["-o", "output.html"])
      opts.output_file.should eq("output.html")
    end

    it "should parse section numbers option" do
      opts = Asciidoctor::Cli::Options.parse(["-n"])
      opts.section_numbers.should be_true
      opts.attributes["sectnums"].should eq("")
    end

    it "should parse single attribute" do
      opts = Asciidoctor::Cli::Options.parse(["-a", "icons"])
      opts.attributes["icons"].should eq("")
    end

    it "should parse attribute with value" do
      opts = Asciidoctor::Cli::Options.parse(["-a", "imagesdir=images"])
      opts.attributes["imagesdir"].should eq("images")
    end

    it "should parse multiple attributes" do
      opts = Asciidoctor::Cli::Options.parse(["-a", "imagesdir=images", "-a", "icons"])
      opts.attributes["imagesdir"].should eq("images")
      opts.attributes["icons"].should eq("")
    end

    it "should only split attribute key/value pairs on first equal sign" do
      opts = Asciidoctor::Cli::Options.parse(["-a", "name=value=value"])
      opts.attributes["name"].should eq("value=value")
    end

    it "should parse attribute with complex value" do
      opts = Asciidoctor::Cli::Options.parse(["-a", "docinfosubs=attributes,replacements"])
      opts.attributes["docinfosubs"].should eq("attributes,replacements")
    end

    it "should parse base directory option" do
      opts = Asciidoctor::Cli::Options.parse(["-B", "/tmp/docs"])
      opts.base_dir.should eq("/tmp/docs")
    end

    it "should parse destination directory option" do
      opts = Asciidoctor::Cli::Options.parse(["-D", "/tmp/output"])
      opts.destination_dir.should eq("/tmp/output")
    end

    it "should parse safe mode option" do
      opts = Asciidoctor::Cli::Options.parse(["-S", "safe"])
      opts.safe_mode.should eq(Asciidoctor::SafeMode::SAFE)
    end

    it "should parse server safe mode" do
      opts = Asciidoctor::Cli::Options.parse(["-S", "server"])
      opts.safe_mode.should eq(Asciidoctor::SafeMode::SERVER)
    end

    it "should parse secure safe mode" do
      opts = Asciidoctor::Cli::Options.parse(["-S", "secure"])
      opts.safe_mode.should eq(Asciidoctor::SafeMode::SECURE)
    end

    it "should parse sourcemap option" do
      opts = Asciidoctor::Cli::Options.parse(["--sourcemap"])
      opts.sourcemap.should be_true
    end

    it "sourcemap option is disabled by default" do
      opts = Asciidoctor::Cli::Options.parse([] of String)
      opts.sourcemap.should be_false
    end

    it "should parse quiet option" do
      opts = Asciidoctor::Cli::Options.parse(["-q"])
      opts.verbose.should eq(0)
    end

    it "should parse verbose option" do
      opts = Asciidoctor::Cli::Options.parse(["-v"])
      opts.verbose.should eq(2)
    end

    it "should set verbose to 0 when -q flag is specified after -v flag" do
      opts = Asciidoctor::Cli::Options.parse(["-v", "-q"])
      opts.verbose.should eq(0)
    end

    it "should set verbose to 2 when -v flag is specified after -q flag" do
      opts = Asciidoctor::Cli::Options.parse(["-q", "-v"])
      opts.verbose.should eq(2)
    end

    it "should not fail if value of attribute option is empty" do
      opts = Asciidoctor::Cli::Options.parse(["-a", ""])
      opts.attributes.empty?.should be_true
    end
  end

  describe "to_options_hash" do
    it "should convert options to hash" do
      opts = Asciidoctor::Cli::Options.new
      opts.backend = "docbook5"
      opts.doctype = "book"
      hash = opts.to_options_hash
      hash["backend"].should eq("docbook5")
      hash["doctype"].should eq("book")
    end

    it "should include attributes in hash" do
      opts = Asciidoctor::Cli::Options.new
      opts.attributes["icons"] = ""
      opts.attributes["imagesdir"] = "images"
      hash = opts.to_options_hash
      hash["attributes"].should contain("icons")
      hash["attributes"].should contain("imagesdir=images")
    end

    it "should include standalone in hash" do
      opts = Asciidoctor::Cli::Options.new
      opts.standalone = false
      hash = opts.to_options_hash
      hash["standalone"].should eq("false")
    end

    it "should include sourcemap in hash" do
      opts = Asciidoctor::Cli::Options.new
      opts.sourcemap = true
      hash = opts.to_options_hash
      hash["sourcemap"].should eq("true")
    end
  end
end
