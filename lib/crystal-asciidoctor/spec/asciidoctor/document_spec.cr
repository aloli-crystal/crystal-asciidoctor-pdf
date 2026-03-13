require "../spec_helper"

describe Asciidoctor::Document do
  describe "#initialize" do
    it "creates a document with default values" do
      doc = Asciidoctor::Document.new
      doc.context.should eq(:document)
      doc.safe.should eq(Asciidoctor::SafeMode::SECURE)
      doc.backend.should eq("html5")
      doc.doctype.should eq("article")
      doc.base_dir.should eq(".")
    end

    it "creates a document with custom safe mode" do
      doc = Asciidoctor::Document.new(safe: Asciidoctor::SafeMode::UNSAFE)
      doc.safe.should eq(Asciidoctor::SafeMode::UNSAFE)
    end

    it "creates a document with custom backend" do
      doc = Asciidoctor::Document.new(backend: "docbook5")
      doc.backend.should eq("docbook5")
    end

    it "creates a document with custom doctype" do
      doc = Asciidoctor::Document.new(doctype: "book")
      doc.doctype.should eq("book")
    end

    it "creates a document with sourcemap enabled" do
      doc = Asciidoctor::Document.new(sourcemap: true)
      doc.sourcemap?.should be_true
    end

    it "starts with parsed? as false" do
      doc = Asciidoctor::Document.new
      doc.parsed?.should be_false
    end
  end

  describe "#<<" do
    it "assigns numeral to sections when appended" do
      doc = Asciidoctor::Document.new
      section = Asciidoctor::Section.new(doc, numbered: true)
      doc << section
      section.index.should eq(0)
    end

    it "appends a block" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      doc << block
      doc.blocks.size.should eq(1)
    end
  end

  describe "#apply_attribute_value_subs" do
    it "returns the value unchanged when no substitution is needed" do
      doc = Asciidoctor::Document.new
      doc.apply_attribute_value_subs("hello world").should eq("hello world")
    end

    it "applies attribute substitution" do
      doc = Asciidoctor::Document.new
      doc.attributes["name"] = "Crystal"
      result = doc.apply_attribute_value_subs("{name} rocks")
      result.should eq("Crystal rocks")
    end
  end

  describe "#attribute_locked?" do
    it "returns false for unlocked attributes" do
      doc = Asciidoctor::Document.new
      doc.attribute_locked?("author").should be_false
    end
  end

  describe "#author" do
    it "returns nil when no author is set" do
      doc = Asciidoctor::Document.new
      doc.author.should be_nil
    end

    it "returns the author attribute" do
      doc = Asciidoctor::Document.new
      doc.attributes["author"] = "John Doe"
      doc.author.should eq("John Doe")
    end
  end

  describe "#authors" do
    it "returns empty array when no authors" do
      doc = Asciidoctor::Document.new
      doc.authors.should be_empty
    end

    it "returns a single author" do
      doc = Asciidoctor::Document.new
      doc.attributes["author"] = "John Doe"
      doc.authors.should eq(["John Doe"])
    end

    it "returns multiple authors" do
      doc = Asciidoctor::Document.new
      doc.attributes["author"] = "John Doe"
      doc.attributes["author_2"] = "Jane Smith"
      doc.authors.should eq(["John Doe", "Jane Smith"])
    end
  end

  describe "#basebackend?" do
    it "returns true when backend starts with base" do
      doc = Asciidoctor::Document.new(backend: "html5")
      doc.basebackend?("html").should be_true
    end

    it "returns false when backend does not start with base" do
      doc = Asciidoctor::Document.new(backend: "html5")
      doc.basebackend?("docbook").should be_false
    end
  end

  describe "#block?" do
    it "returns true" do
      doc = Asciidoctor::Document.new
      doc.block?.should be_true
    end
  end

  describe "#catalog" do
    it "provides access to the document catalog" do
      doc = Asciidoctor::Document.new
      doc.catalog.should_not be_nil
      doc.catalog.footnotes.should be_empty
      doc.catalog.images.should be_empty
      doc.catalog.includes.should be_empty
      doc.catalog.links.should be_empty
      doc.catalog.refs.should be_empty
    end
  end

  describe "#clear_playback_attributes" do
    it "removes attribute_entries from the hash" do
      doc = Asciidoctor::Document.new
      attrs = {"attribute_entries" => "something", "other" => "value"}
      doc.clear_playback_attributes(attrs)
      attrs.has_key?("attribute_entries").should be_false
      attrs["other"].should eq("value")
    end
  end

  describe "#content" do
    it "deletes title attribute and delegates to super" do
      doc = Asciidoctor::Document.new
      doc.attributes["title"] = "something"
      doc.content
      doc.attributes.has_key?("title").should be_false
    end
  end

  describe "#convert" do
    it "parses before converting if not yet parsed" do
      doc = Asciidoctor::Document.new
      doc.parsed?.should be_false
      doc.convert
      doc.parsed?.should be_true
    end
  end

  describe "#counter" do
    it "initializes a counter to 1" do
      doc = Asciidoctor::Document.new
      doc.counter("example-number").should eq(1)
    end

    it "increments an existing integer counter" do
      doc = Asciidoctor::Document.new
      doc.counter("example-number")
      doc.counter("example-number").should eq(2)
    end

    it "initializes a counter with a seed value" do
      doc = Asciidoctor::Document.new
      doc.counter("example-number", 5).should eq(5)
    end

    it "initializes a counter with a string seed" do
      doc = Asciidoctor::Document.new
      doc.counter("appendix-number", "A").should eq("A")
    end

    it "increments a letter counter" do
      doc = Asciidoctor::Document.new
      doc.counter("appendix-number", "A")
      doc.counter("appendix-number").should eq("B")
    end

    it "stores the counter value in attributes" do
      doc = Asciidoctor::Document.new
      doc.counter("example-number")
      doc.attributes["example-number"].should eq("1")
    end
  end

  describe "#counters" do
    it "starts with empty counters" do
      doc = Asciidoctor::Document.new
      doc.counters.should be_empty
    end
  end

  describe "#create_converter" do
    it "creates an Html5Converter for html5 backend" do
      doc = Asciidoctor::Document.new
      converter = doc.create_converter("html5")
      converter.should be_a(Asciidoctor::Converter::Html5Converter)
    end

    it "creates a DocBook5Converter for docbook5 backend" do
      doc = Asciidoctor::Document.new
      converter = doc.create_converter("docbook5")
      converter.should be_a(Asciidoctor::Converter::DocBook5Converter)
    end

    it "creates a ManPageConverter for manpage backend" do
      doc = Asciidoctor::Document.new
      converter = doc.create_converter("manpage")
      converter.should be_a(Asciidoctor::Converter::ManPageConverter)
    end

    it "defaults to Html5Converter for unknown backend" do
      doc = Asciidoctor::Document.new
      converter = doc.create_converter("unknown")
      converter.should be_a(Asciidoctor::Converter::Html5Converter)
    end
  end

  describe "#delete_attribute" do
    it "deletes an unlocked attribute" do
      doc = Asciidoctor::Document.new
      doc.attributes["custom"] = "value"
      doc.delete_attribute("custom").should be_true
      doc.attributes.has_key?("custom").should be_false
    end
  end

  describe "#docinfo" do
    it "returns empty string when safe mode is SECURE" do
      doc = Asciidoctor::Document.new(safe: Asciidoctor::SafeMode::SECURE)
      doc.docinfo.should eq("")
    end
  end

  describe "#doctitle" do
    it "returns nil when no header is set" do
      doc = Asciidoctor::Document.new
      doc.doctitle.should be_nil
    end

    it "returns fallback title when use_fallback is true" do
      doc = Asciidoctor::Document.new
      doc.doctitle({:use_fallback => true}).should eq("Untitled")
    end

    it "returns the doctitle attribute when set" do
      doc = Asciidoctor::Document.new
      doc.attributes["doctitle"] = "My Document"
      doc.doctitle.should eq("My Document")
    end

    it "returns the title when set" do
      doc = Asciidoctor::Document.new
      doc.title = "My Title"
      doc.doctitle.should eq("My Title")
    end
  end

  describe "#doctitle_as_title" do
    it "returns nil when no title" do
      doc = Asciidoctor::Document.new
      doc.doctitle_as_title.should be_nil
    end

    it "returns a Title object when title is set" do
      doc = Asciidoctor::Document.new
      doc.attributes["doctitle"] = "Main: Subtitle"
      title = doc.doctitle_as_title
      title.should_not be_nil
      title.not_nil!.main.should eq("Main")
      title.not_nil!.subtitle.should eq("Subtitle")
    end
  end

  describe "#document" do
    it "returns itself" do
      doc = Asciidoctor::Document.new
      doc.document.should eq(doc)
    end
  end

  describe "#embedded?" do
    it "returns false by default" do
      doc = Asciidoctor::Document.new
      doc.embedded?.should be_false
    end

    it "returns true when embedded attribute is set" do
      doc = Asciidoctor::Document.new
      doc.attributes["embedded"] = ""
      doc.embedded?.should be_true
    end
  end

  describe "#extensions?" do
    it "returns false by default" do
      doc = Asciidoctor::Document.new
      doc.extensions?.should be_false
    end
  end

  describe "#fill_datetime_attributes" do
    it "fills local datetime attributes" do
      doc = Asciidoctor::Document.new
      attrs = {} of String => String
      doc.fill_datetime_attributes(attrs)
      attrs.has_key?("localdate").should be_true
      attrs.has_key?("localtime").should be_true
      attrs.has_key?("localdatetime").should be_true
      attrs.has_key?("localyear").should be_true
    end

    it "fills doc datetime attributes" do
      doc = Asciidoctor::Document.new
      attrs = {} of String => String
      doc.fill_datetime_attributes(attrs)
      attrs.has_key?("docdate").should be_true
      attrs.has_key?("doctime").should be_true
      attrs.has_key?("docdatetime").should be_true
      attrs.has_key?("docyear").should be_true
    end

    it "does not overwrite existing localdate" do
      doc = Asciidoctor::Document.new
      attrs = {"localdate" => "2025-01-01"}
      doc.fill_datetime_attributes(attrs)
      attrs["localdate"].should eq("2025-01-01")
    end

    it "does not overwrite existing docdate" do
      doc = Asciidoctor::Document.new
      attrs = {"docdate" => "2024-06-15"}
      doc.fill_datetime_attributes(attrs)
      attrs["docdate"].should eq("2024-06-15")
    end
  end

  describe "#finalize_header" do
    it "calls save_attributes and returns block_attrs" do
      doc = Asciidoctor::Document.new
      attrs = {"key" => "value"}
      result = doc.finalize_header(attrs)
      result.should eq(attrs)
    end
  end

  describe "#first_section" do
    it "returns nil when no sections" do
      doc = Asciidoctor::Document.new
      doc.first_section.should be_nil
    end

    it "returns the first section" do
      doc = Asciidoctor::Document.new
      doc << Asciidoctor::Block.new(doc, :paragraph)
      section = Asciidoctor::Section.new(doc)
      section.title = "First"
      doc << section
      doc.first_section.should eq(section)
    end

    it "returns the header if set" do
      doc = Asciidoctor::Document.new
      header = Asciidoctor::Section.new(doc)
      header.title = "Header"
      doc.header = header
      result = doc.first_section
      result.should_not be_nil
      result.not_nil!.title.should eq("Header")
    end
  end

  describe "#footnotes" do
    it "returns empty array initially" do
      doc = Asciidoctor::Document.new
      doc.footnotes.should be_empty
    end
  end

  describe "#footnotes?" do
    it "returns false when no footnotes" do
      doc = Asciidoctor::Document.new
      doc.footnotes?.should be_false
    end

    it "returns true when footnotes exist" do
      doc = Asciidoctor::Document.new
      doc.catalog.footnotes << Asciidoctor::Document::Footnote.new(index: 1, id: "fn1", text: "A note")
      doc.footnotes?.should be_true
    end
  end

  describe "#header?" do
    it "returns false when no header is set" do
      doc = Asciidoctor::Document.new
      doc.header?.should be_false
    end

    it "returns true when header is set" do
      doc = Asciidoctor::Document.new
      doc.header = Asciidoctor::Section.new(doc)
      doc.header?.should be_true
    end
  end

  describe "#increment_and_store_counter" do
    it "initializes a counter to 1" do
      doc = Asciidoctor::Document.new
      doc.increment_and_store_counter("example-number").should eq("1")
    end

    it "increments an existing integer counter" do
      doc = Asciidoctor::Document.new
      doc.increment_and_store_counter("example-number")
      doc.increment_and_store_counter("example-number").should eq("2")
    end
  end

  describe "#inline?" do
    it "returns false" do
      doc = Asciidoctor::Document.new
      doc.inline?.should be_false
    end
  end

  describe "#multipart?" do
    it "returns false for article doctype" do
      doc = Asciidoctor::Document.new
      doc.multipart?.should be_false
    end
  end

  describe "#nested?" do
    it "returns false for a root document" do
      doc = Asciidoctor::Document.new
      doc.nested?.should be_false
    end

    it "returns true for a nested document" do
      parent = Asciidoctor::Document.new
      child = Asciidoctor::Document.new(parent_document: parent)
      child.nested?.should be_true
    end
  end

  describe "#nofooter" do
    it "returns false by default" do
      doc = Asciidoctor::Document.new
      doc.nofooter.should be_false
    end

    it "returns true when nofooter attribute is set" do
      doc = Asciidoctor::Document.new
      doc.attributes["nofooter"] = ""
      doc.nofooter.should be_true
    end
  end

  describe "#noheader" do
    it "returns false by default" do
      doc = Asciidoctor::Document.new
      doc.noheader.should be_false
    end

    it "returns true when noheader attribute is set" do
      doc = Asciidoctor::Document.new
      doc.attributes["noheader"] = ""
      doc.noheader.should be_true
    end
  end

  describe "#notitle" do
    it "returns false by default" do
      doc = Asciidoctor::Document.new
      doc.notitle.should be_false
    end

    it "returns true when notitle attribute is set" do
      doc = Asciidoctor::Document.new
      doc.attributes["notitle"] = ""
      doc.notitle.should be_true
    end
  end

  describe "#parse" do
    it "parses source data" do
      doc = Asciidoctor::Document.new
      doc.parse("= My Title\n\nHello world")
      doc.parsed?.should be_true
    end

    it "does not re-parse if already parsed" do
      doc = Asciidoctor::Document.new
      doc.parse("= Title\n\nContent")
      doc.parsed?.should be_true
      # Calling parse again should be a no-op
      doc.parse("= Different Title\n\nOther content")
      doc.parsed?.should be_true
    end
  end

  describe "#parsed?" do
    it "returns false initially" do
      doc = Asciidoctor::Document.new
      doc.parsed?.should be_false
    end
  end

  describe "#register" do
    it "registers a link" do
      doc = Asciidoctor::Document.new
      doc.register(:links, "https://example.com")
      doc.catalog.links.should eq(["https://example.com"])
    end

    it "registers an image" do
      doc = Asciidoctor::Document.new
      doc.register(:images, "photo.png")
      doc.catalog.images.size.should eq(1)
      doc.catalog.images[0].target.should eq("photo.png")
    end

    it "registers an include" do
      doc = Asciidoctor::Document.new
      doc.register(:includes, "chapter1.adoc")
      doc.catalog.includes["chapter1.adoc"].should be_true
    end
  end

  describe "#resolve_id" do
    it "returns nil when no matching ref" do
      doc = Asciidoctor::Document.new
      doc.resolve_id("nonexistent").should be_nil
    end
  end

  describe "#restore_attributes" do
    it "restores attributes from saved header attributes" do
      doc = Asciidoctor::Document.new
      doc.attributes["key1"] = "value1"
      doc.attributes["key2"] = "value2"
      doc.save_attributes
      doc.attributes["key1"] = "modified"
      doc.attributes["key3"] = "new"
      doc.restore_attributes
      doc.attributes["key1"].should eq("value1")
      doc.attributes["key2"].should eq("value2")
      doc.attributes.has_key?("key3").should be_false
    end
  end

  describe "#revdate" do
    it "returns nil when not set" do
      doc = Asciidoctor::Document.new
      doc.revdate.should be_nil
    end

    it "returns the revdate attribute" do
      doc = Asciidoctor::Document.new
      doc.attributes["revdate"] = "2026-01-01"
      doc.revdate.should eq("2026-01-01")
    end
  end

  describe "#save_attributes" do
    it "saves a copy of current attributes" do
      doc = Asciidoctor::Document.new
      doc.attributes["myattr"] = "myval"
      doc.save_attributes
      # After save, restore should bring back the saved state
      doc.attributes["myattr"] = "changed"
      doc.restore_attributes
      doc.attributes["myattr"].should eq("myval")
    end

    it "normalizes toc attributes" do
      doc = Asciidoctor::Document.new
      doc.attributes["toc"] = ""
      doc.save_attributes
      doc.attributes["toc"].should eq("")
    end

    it "normalizes icons attribute" do
      doc = Asciidoctor::Document.new
      doc.attributes["icons"] = "font"
      doc.save_attributes
      doc.attributes["icons"].should eq("font")
    end

    it "sets compat_mode when compat-mode attribute is present" do
      doc = Asciidoctor::Document.new
      doc.attributes["compat-mode"] = ""
      doc.save_attributes
      doc.compat_mode?.should be_true
    end
  end

  describe "#save_to" do
    it "writes output to a file" do
      doc = Asciidoctor::Document.new
      tmpfile = "/tmp/test_save_to_#{Random.rand(10000)}.html"
      begin
        doc.save_to("<html>test</html>", tmpfile)
        File.exists?(tmpfile).should be_true
        File.read(tmpfile).should contain("test")
      ensure
        File.delete(tmpfile) if File.exists?(tmpfile)
      end
    end
  end

  describe "#sections?" do
    it "returns false when no sections" do
      doc = Asciidoctor::Document.new
      doc.sections?.should be_false
    end
  end

  describe "#set_attribute" do
    it "sets an attribute on the document" do
      doc = Asciidoctor::Document.new
      doc.set_attribute("custom", "value")
      doc.attributes["custom"].should eq("value")
    end

    it "returns the value set" do
      doc = Asciidoctor::Document.new
      doc.set_attribute("custom", "value").should eq("value")
    end

    it "sets an empty value" do
      doc = Asciidoctor::Document.new
      doc.set_attribute("flag")
      doc.attributes["flag"].should eq("")
    end
  end

  describe "#set_header_attribute" do
    it "sets an attribute" do
      doc = Asciidoctor::Document.new
      doc.set_header_attribute("key", "value").should be_true
      doc.attributes["key"].should eq("value")
    end

    it "does not overwrite when overwrite is false and attribute exists" do
      doc = Asciidoctor::Document.new
      doc.attributes["key"] = "original"
      doc.set_header_attribute("key", "new", overwrite: false).should be_false
      doc.attributes["key"].should eq("original")
    end

    it "overwrites by default" do
      doc = Asciidoctor::Document.new
      doc.attributes["key"] = "original"
      doc.set_header_attribute("key", "new").should be_true
      doc.attributes["key"].should eq("new")
    end
  end

  describe "#source" do
    it "returns nil when no reader" do
      doc = Asciidoctor::Document.new
      doc.source.should be_nil
    end
  end

  describe "#source_lines" do
    it "returns empty array when no reader" do
      doc = Asciidoctor::Document.new
      doc.source_lines.should be_empty
    end
  end

  describe "#update_backend_attributes" do
    it "updates backend and related attributes" do
      doc = Asciidoctor::Document.new(backend: "html5")
      doc.update_backend_attributes("docbook5")
      doc.backend.should eq("docbook5")
      doc.attributes["backend"].should eq("docbook5")
    end

    it "returns nil when backend is unchanged" do
      doc = Asciidoctor::Document.new(backend: "html5")
      doc.update_backend_attributes("html5").should be_nil
    end

    it "sets htmlsyntax to xml for xhtml backend" do
      doc = Asciidoctor::Document.new
      doc.update_backend_attributes("xhtml5", init: true)
      doc.attributes["htmlsyntax"].should eq("xml")
    end
  end

  describe "#update_doctype_attributes" do
    it "updates doctype and related attributes" do
      doc = Asciidoctor::Document.new(doctype: "article")
      doc.update_doctype_attributes("book")
      doc.doctype.should eq("book")
      doc.attributes["doctype"].should eq("book")
      doc.attributes.has_key?("doctype-book").should be_true
    end

    it "returns nil when doctype is unchanged" do
      doc = Asciidoctor::Document.new(doctype: "article")
      doc.update_doctype_attributes("article").should be_nil
    end
  end

  describe "#write" do
    it "writes output to a file" do
      doc = Asciidoctor::Document.new
      tmpfile = "/tmp/test_write_#{Random.rand(10000)}.html"
      begin
        doc.write("<html>content</html>", tmpfile)
        File.exists?(tmpfile).should be_true
        content = File.read(tmpfile)
        content.should contain("content")
      ensure
        File.delete(tmpfile) if File.exists?(tmpfile)
      end
    end

    it "does nothing when output is nil" do
      doc = Asciidoctor::Document.new
      tmpfile = "/tmp/test_write_nil_#{Random.rand(10000)}.html"
      doc.write(nil, tmpfile)
      File.exists?(tmpfile).should be_false
    end

    it "does nothing when output is empty" do
      doc = Asciidoctor::Document.new
      tmpfile = "/tmp/test_write_empty_#{Random.rand(10000)}.html"
      doc.write("", tmpfile)
      File.exists?(tmpfile).should be_false
    end
  end

  describe "#xreftext" do
    it "returns the doctitle" do
      doc = Asciidoctor::Document.new
      doc.xreftext.should be_nil
    end

    it "returns the doctitle when set" do
      doc = Asciidoctor::Document.new
      doc.attributes["doctitle"] = "My Doc"
      doc.xreftext.should eq("My Doc")
    end
  end

  describe "Asciidoctor::Document::AttributeEntry" do
    it "stores name and value" do
      entry = Asciidoctor::Document::AttributeEntry.new("author", "John Doe")
      entry.name.should eq("author")
      entry.value.should eq("John Doe")
      entry.negate.should be_false
    end

    it "negates when value is nil" do
      entry = Asciidoctor::Document::AttributeEntry.new("toc", nil)
      entry.negate.should be_true
    end

    it "saves to attributes hash" do
      attrs = {} of String => String
      entry = Asciidoctor::Document::AttributeEntry.new("key", "value")
      entry.save_to(attrs)
      attrs["key"].should eq("value")
    end

    it "removes from attributes hash when negated" do
      attrs = {"key" => "value"}
      entry = Asciidoctor::Document::AttributeEntry.new("key", nil)
      entry.save_to(attrs)
      attrs.has_key?("key").should be_false
    end
  end

  describe "Asciidoctor::Document::Footnote" do
    it "stores index, id, and text" do
      fn = Asciidoctor::Document::Footnote.new(index: 1, id: "fn1", text: "A footnote")
      fn.index.should eq(1)
      fn.id.should eq("fn1")
      fn.text.should eq("A footnote")
    end
  end

  describe "Asciidoctor::Document::ImageReference" do
    it "stores target and imagesdir" do
      ref = Asciidoctor::Document::ImageReference.new("image.png", "images")
      ref.target.should eq("image.png")
      ref.imagesdir.should eq("images")
    end

    it "converts to string as target" do
      ref = Asciidoctor::Document::ImageReference.new("image.png", "images")
      ref.to_s.should eq("image.png")
    end
  end

  describe "Asciidoctor::Document::Title" do
    it "parses a simple title" do
      title = Asciidoctor::Document::Title.new("My Document")
      title.main.should eq("My Document")
      title.subtitle.should be_nil
      title.combined.should eq("My Document")
    end

    it "parses a title with subtitle" do
      title = Asciidoctor::Document::Title.new("Main Title: Subtitle Here")
      title.main.should eq("Main Title")
      title.subtitle.should eq("Subtitle Here")
      title.combined.should eq("Main Title: Subtitle Here")
    end

    it "uses the last separator for subtitle split" do
      title = Asciidoctor::Document::Title.new("Part One: Chapter: Details")
      title.main.should eq("Part One: Chapter")
      title.subtitle.should eq("Details")
    end

    it "reports subtitle?" do
      title_with = Asciidoctor::Document::Title.new("Main: Sub")
      title_with.subtitle?.should be_true

      title_without = Asciidoctor::Document::Title.new("Simple Title")
      title_without.subtitle?.should be_false
    end
  end

  describe "Asciidoctor::Catalog" do
    it "initializes with empty collections" do
      catalog = Asciidoctor::Catalog.new
      catalog.footnotes.should be_empty
      catalog.images.should be_empty
      catalog.includes.should be_empty
      catalog.links.should be_empty
      catalog.refs.should be_empty
    end

    it "provides access to callouts" do
      catalog = Asciidoctor::Catalog.new
      catalog.callouts.should_not be_nil
    end
  end

  context "Document Title" do
    it "document title" do
      input = "= My Title\n\npreamble"
      doc = Asciidoctor.load(input)
      doc.doctitle.should eq("My Title")
      doc.header?.should be_truthy
    end

    it "safe mode level set to SECURE by default" do
      doc = Asciidoctor.load("")
      doc.safe.should eq(Asciidoctor::SafeMode::SECURE)
    end

    it "safe mode level set using string" do
      doc = Asciidoctor.load("", {"safe" => "1"})
      doc.safe.should eq(Asciidoctor::SafeMode::SAFE)
    end

    it "document with no doctitle" do
      doc = Asciidoctor.load("Snorf")
      doc.doctitle.should be_nil
      doc.header?.should be_falsey
    end

    it "document with doctitle defined as attribute entry" do
      input = ":doctitle: Document Title\n\npreamble\n\n== First Section\n\ntext"
      doc = Asciidoctor.load(input)
      doc.doctitle.should eq("Document Title")
      doc.header?.should be_truthy
    end

    it "document with doctitle defined as attribute entry followed by block with title" do
      input = ":doctitle: Document Title\n\n.Block title\nBlock content"
      doc = Asciidoctor.load(input)
      doc.doctitle.should eq("Document Title")
      doc.header?.should be_truthy
      doc.blocks.size.should be >= 1
    end

    it "document header can reference intrinsic doctitle attribute" do
      input = "= ACME Documentation\n:intro: Welcome to the {doctitle}!\n\n{intro}"
      doc = Asciidoctor.load(input)
      doc.attr("intro").should eq("Welcome to the ACME Documentation!")
    end

    it "should recognize document title when preceded by blank lines" do
      input = "= Title\n\npreamble\n\n== Section 1\n\ntext"
      output = Asciidoctor.convert(input, {"safe" => "1"})
      output.to_s.should contain("<h1>Title</h1>")
    end

    it "should apply max-width to each top-level container" do
      input = ":max-width: 50em\n\n= Title\n\ncontent"
      output = Asciidoctor.convert(input)
      output.to_s.should contain("max-width: 50em")
    end

    it "should set doctype to article by default" do
      doc = Asciidoctor.load("")
      doc.doctype.should eq("article")
    end

    it "should set doctype to book when specified" do
      doc = Asciidoctor.load("", {"doctype" => "book"})
      doc.doctype.should eq("book")
    end

    it "should set backend to html5 by default" do
      doc = Asciidoctor.load("")
      doc.backend.should eq("html5")
    end

    it "should set backend to docbook5 when specified" do
      doc = Asciidoctor.load("", {"backend" => "docbook5"})
      doc.backend.should eq("docbook5")
    end

    it "should have empty blocks when document is empty" do
      doc = Asciidoctor.load("")
      doc.blocks.should be_empty
    end

    it "should parse preamble as first block" do
      input = "= Title\n\npreamble text\n\n== Section"
      doc = Asciidoctor.load(input)
      doc.blocks.should_not be_empty
    end

    it "should set safe mode attributes on document" do
      doc = Asciidoctor.load("")
      doc.attr?("safe-mode-name").should be_truthy
      doc.attr("safe-mode-name").should eq("secure")
    end

    it "should set backend attributes" do
      doc = Asciidoctor.load("")
      doc.attr?("backend").should be_truthy
      doc.attr("backend").should eq("html5")
      doc.attr?("backend-html5").should be_truthy
    end

    it "should set doctype attributes" do
      doc = Asciidoctor.load("")
      doc.attr?("doctype").should be_truthy
      doc.attr("doctype").should eq("article")
      doc.attr?("doctype-article").should be_truthy
    end

    it "should have author info when author line present" do
      input = "= Title\nJohn Doe <john@example.com>\n\ncontent"
      doc = Asciidoctor.load(input)
      doc.attr("author").should eq("John Doe")
      doc.attr("email").should eq("john@example.com")
      doc.attr("firstname").should eq("John")
      doc.attr("lastname").should eq("Doe")
    end

    it "should have revision info when revision line present" do
      input = "= Title\nAuthor Name\nv1.0, 2020-01-01\n\ncontent"
      doc = Asciidoctor.load(input)
      doc.attr("revnumber").should eq("1.0")
      doc.attr("revdate").should eq("2020-01-01")
    end

    it "should set attribute via header" do
      input = "= Title\n:foo: bar\n\n{foo}"
      doc = Asciidoctor.load(input)
      doc.attr("foo").should eq("bar")
    end

    it "should unset attribute via header" do
      input = "= Title\n:foo: bar\n:!foo:\n\n{foo}"
      doc = Asciidoctor.load(input)
      doc.attr?("foo").should be_falsey
    end

    it "should set attribute via API" do
      doc = Asciidoctor.load("content", {"foo" => "bar"})
      doc.attr("foo").should eq("bar")
    end

    it "should have correct content model" do
      doc = Asciidoctor.load("content")
      doc.content_model.should eq(Asciidoctor::ContentModel::Compound)
    end

    it "should have correct context" do
      doc = Asciidoctor.load("content")
      doc.context.should eq(:document)
    end

    it "should have source_location nil by default" do
      doc = Asciidoctor.load("content")
      doc.source_location.should be_nil
    end

    it "should count blocks correctly" do
      input = "paragraph 1\n\nparagraph 2\n\nparagraph 3"
      doc = Asciidoctor.load(input)
      doc.blocks.size.should eq(3)
    end
  end
end
