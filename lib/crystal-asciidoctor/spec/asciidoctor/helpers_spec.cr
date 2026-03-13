require "../spec_helper"
require "file_utils"

describe Asciidoctor::Helpers do
  describe ".basename" do
    it "returns the basename of a filename" do
      Asciidoctor::Helpers.basename("images/tiger.png").should eq("tiger.png")
    end

    it "returns the basename without extension when drop_ext is true" do
      Asciidoctor::Helpers.basename("images/tiger.png", true).should eq("tiger")
    end

    it "returns the basename without specific extension" do
      Asciidoctor::Helpers.basename("images/tiger.png", ".png").should eq("tiger")
    end
  end

  describe ".encode_spaces_in_uri" do
    it "replaces spaces with %20" do
      Asciidoctor::Helpers.encode_spaces_in_uri("my file.adoc").should eq("my%20file.adoc")
    end

    it "returns original string if no spaces" do
      Asciidoctor::Helpers.encode_spaces_in_uri("myfile.adoc").should eq("myfile.adoc")
    end
  end

  describe ".encode_uri_component" do
    it "encodes special characters" do
      Asciidoctor::Helpers.encode_uri_component("hello world").should eq("hello%20world")
    end

    it "encodes slashes" do
      result = Asciidoctor::Helpers.encode_uri_component("foo/bar")
      result.should contain("%2F")
    end
  end

  describe ".extname" do
    it "returns the extension of a path" do
      Asciidoctor::Helpers.extname("file.adoc").should eq(".adoc")
    end

    it "returns fallback if no extension" do
      Asciidoctor::Helpers.extname("file", ".txt").should eq(".txt")
    end

    it "returns empty string as default fallback" do
      Asciidoctor::Helpers.extname("file").should eq("")
    end

    it "does not return extension if dot is in directory part" do
      Asciidoctor::Helpers.extname("path.d/file").should eq("")
    end
  end

  describe ".extname?" do
    it "returns true if path has an extension" do
      Asciidoctor::Helpers.extname?("file.adoc").should be_true
    end

    it "returns false if path has no extension" do
      Asciidoctor::Helpers.extname?("file").should be_false
    end

    it "returns false if dot is only in directory part" do
      Asciidoctor::Helpers.extname?("path.d/file").should be_false
    end
  end

  describe ".int_to_roman" do
    it "converts 1 to I" do
      Asciidoctor::Helpers.int_to_roman(1).should eq("I")
    end

    it "converts 4 to IV" do
      Asciidoctor::Helpers.int_to_roman(4).should eq("IV")
    end

    it "converts 9 to IX" do
      Asciidoctor::Helpers.int_to_roman(9).should eq("IX")
    end

    it "converts 14 to XIV" do
      Asciidoctor::Helpers.int_to_roman(14).should eq("XIV")
    end

    it "converts 42 to XLII" do
      Asciidoctor::Helpers.int_to_roman(42).should eq("XLII")
    end

    it "converts 99 to XCIX" do
      Asciidoctor::Helpers.int_to_roman(99).should eq("XCIX")
    end

    it "converts 2024 to MMXXIV" do
      Asciidoctor::Helpers.int_to_roman(2024).should eq("MMXXIV")
    end
  end

  describe ".mkdir_p" do
    it "creates a nested directory structure" do
      test_dir = "/tmp/asciidoctor_test_#{Random.rand(100000)}/a/b/c"
      begin
        Asciidoctor::Helpers.mkdir_p(test_dir)
        File.directory?(test_dir).should be_true
      ensure
        parts = test_dir.split("/")
        FileUtils.rm_rf("/tmp/#{parts[2]}") if parts.size > 2
      end
    end

    it "does nothing if directory already exists" do
      Asciidoctor::Helpers.mkdir_p("/tmp")
      File.directory?("/tmp").should be_true
    end
  end

  describe ".nextval" do
    it "increments an integer" do
      Asciidoctor::Helpers.nextval(1).should eq(2)
    end

    it "increments a numeric string" do
      Asciidoctor::Helpers.nextval("1").should eq(2)
    end

    it "returns successor of a character string" do
      Asciidoctor::Helpers.nextval("a").should eq("b")
    end
  end

  describe ".prepare_source_array" do
    it "returns empty array for empty input" do
      Asciidoctor::Helpers.prepare_source_array([] of String).should eq([] of String)
    end

    it "strips trailing whitespace when trim_end is true" do
      Asciidoctor::Helpers.prepare_source_array(["hello  ", "world  "]).should eq(["hello", "world"])
    end

    it "strips only trailing newline when trim_end is false" do
      Asciidoctor::Helpers.prepare_source_array(["hello  \n", "world  \n"], false).should eq(["hello  ", "world  "])
    end

    it "strips BOM from first line" do
      Asciidoctor::Helpers.prepare_source_array(["\u{FEFF}hello", "world"]).should eq(["hello", "world"])
    end
  end

  describe ".prepare_source_string" do
    it "returns empty array for empty input" do
      Asciidoctor::Helpers.prepare_source_string("").should eq([] of String)
    end

    it "splits string into lines and strips trailing whitespace" do
      Asciidoctor::Helpers.prepare_source_string("hello  \nworld  \n").should eq(["hello", "world"])
    end

    it "strips BOM" do
      Asciidoctor::Helpers.prepare_source_string("\u{FEFF}hello\nworld").should eq(["hello", "world"])
    end
  end

  describe ".roman_to_int" do
    it "converts I to 1" do
      Asciidoctor::Helpers.roman_to_int("I").should eq(1)
    end

    it "converts IV to 4" do
      Asciidoctor::Helpers.roman_to_int("IV").should eq(4)
    end

    it "converts IX to 9" do
      Asciidoctor::Helpers.roman_to_int("IX").should eq(9)
    end

    it "converts XIV to 14" do
      Asciidoctor::Helpers.roman_to_int("XIV").should eq(14)
    end

    it "converts XLII to 42" do
      Asciidoctor::Helpers.roman_to_int("XLII").should eq(42)
    end

    it "converts XCIX to 99" do
      Asciidoctor::Helpers.roman_to_int("XCIX").should eq(99)
    end

    it "converts MMXXIV to 2024" do
      Asciidoctor::Helpers.roman_to_int("MMXXIV").should eq(2024)
    end
  end

  describe ".rootname" do
    it "removes the extension from a filename" do
      Asciidoctor::Helpers.rootname("part1/chapter1.adoc").should eq("part1/chapter1")
    end

    it "returns the filename if no extension" do
      Asciidoctor::Helpers.rootname("chapter1").should eq("chapter1")
    end

    it "does not remove extension if dot is in directory part only" do
      Asciidoctor::Helpers.rootname("path.d/file").should eq("path.d/file")
    end
  end

  describe ".uriish?" do
    it "returns true for http URI" do
      Asciidoctor::Helpers.uriish?("http://example.com").should be_true
    end

    it "returns true for https URI" do
      Asciidoctor::Helpers.uriish?("https://example.com").should be_true
    end

    it "returns false for plain path" do
      Asciidoctor::Helpers.uriish?("images/tiger.png").should be_false
    end
  end
end
