require "../spec_helper"
require "../test_helpers"

describe "Attributes" do
  # TODO: setup and teardown for logger

  context "Assignment" do
    it "creates an attribute" do
      doc = TestHelpers.document_from_string(":frog: Tanglefoot")
      doc.attributes["frog"].should eq("Tanglefoot")
    end

    it "requires a space after colon following attribute name" do
      doc = TestHelpers.document_from_string("foo:bar")
      doc.attributes["foo"]?.should be_nil
    end

    it "does not recognize attribute entry if name contains colon" do
      input = ":foo:bar: baz"
      doc = TestHelpers.document_from_string(input)
      doc.attr?("foo:bar").should be_falsey
      doc.blocks.size.should eq(1)
      doc.blocks[0].context.should eq(:paragraph)
    end

    it "does not recognize attribute entry if name ends with colon" do
      input = ":foo:: bar"
      doc = TestHelpers.document_from_string(input)
      doc.attr?("foo:").should be_falsey
      doc.blocks.size.should eq(1)
      # In Crystal, this is parsed as a dlist
      # doc.blocks[0].context.should eq(:dlist)
    end

    it "allows any word character defined by Unicode in an attribute name" do
      [
        {"café", "a coffee shop"},
        # {"سمن", "سازمان مردمنهاد"} # Fails with "invalid byte sequence in UTF-8"
      ].each do |(name, value)|
        str = <<-EOS
        :#{name}: #{value}

        {#{name}}
        EOS
        result = TestHelpers.convert_string_to_embedded(str)
        result.should contain("<p>#{value}</p>")
      end
    end

    it "creates an attribute by fusing a legacy multi-line value" do
      str = <<-EOS
      :description: This is the first      +
                    Ruby implementation of +
                    AsciiDoc.
      EOS
      doc = TestHelpers.document_from_string(str)
      doc.attributes["description"].should eq("This is the first Ruby implementation of AsciiDoc.")
    end

    it "creates an attribute by fusing a multi-line value" do
      str = <<-EOS
      :description: This is the first \\
                    Ruby implementation of \\
                    AsciiDoc.
      EOS
      doc = TestHelpers.document_from_string(str)
      doc.attributes["description"].should eq("This is the first Ruby implementation of AsciiDoc.")
    end

    it "honors line break characters in multi-line values" do
      str = <<-EOS
      :signature: Linus Torvalds + \\
      Linux Hacker + \\
      linus.torvalds@example.com
      EOS
      doc = TestHelpers.document_from_string(str)
      doc.attributes["signature"].should eq("Linus Torvalds +\nLinux Hacker +\nlinus.torvalds@example.com")
    end

    it "should allow pass macro to surround a multi-line value that contains line breaks" do
      str = <<-EOS
      :signature: pass:a[{author} + \\
      {title} + \\
      {email}]
      EOS
      doc = TestHelpers.document_from_string(str, {"author" => "Linus Torvalds", "title" => "Linux Hacker", "email" => "linus.torvalds@example.com"})
      doc.attr("signature").should eq("Linus Torvalds +\nLinux Hacker +\nlinus.torvalds@example.com")
    end

    it "should delete an attribute that ends with !" do
      doc = TestHelpers.document_from_string(":frog: Tanglefoot\n:frog!:")
      doc.attributes["frog"]?.should be_nil
    end

    it "should delete an attribute that ends with ! set via API" do
      doc = TestHelpers.document_from_string(":frog: Tanglefoot", {"frog!" => ""})
      doc.attributes["frog"]?.should be_nil
    end

    it "should delete an attribute that begins with !" do
      doc = TestHelpers.document_from_string(":frog: Tanglefoot\n:!frog:")
      doc.attributes["frog"]?.should be_nil
    end

    it "should delete an attribute that begins with ! set via API" do
      doc = TestHelpers.document_from_string(":frog: Tanglefoot", {"!frog" => ""})
      doc.attributes["frog"]?.should be_nil
    end

    it "should delete an attribute set via API to nil value" do
      doc = TestHelpers.document_from_string(":frog: Tanglefoot", {"frog" => nil})
      doc.attributes["frog"]?.should be_nil
    end

    it "should not choke when deleting a non-existing attribute" do
      doc = TestHelpers.document_from_string(":frog!:")
      doc.attributes["frog"]?.should be_nil
    end

    it "replaces special characters in attribute value" do
      doc = TestHelpers.document_from_string(":xml-busters: <>&", {"standalone" => "false"})
      doc.attributes["xml-busters"].should eq("&lt;&gt;&amp;")
    end

    it "performs attribute substitution on attribute value" do
      doc = TestHelpers.document_from_string(":version: 1.0\n:release: Asciidoctor {version}")
      doc.attributes["release"].should eq("Asciidoctor 1.0")
    end

    it "assigns attribute to empty string if substitution fails to resolve attribute" do
      # input = ":release: Asciidoctor {version}"
      # document_from_string input, attributes: { 'attribute-missing' => 'drop-line' }
      # assert_message @logger, :INFO, 'dropping line containing reference to missing attribute: version'
    end

    it "assigns multi-line attribute to empty string if substitution fails to resolve attribute" do
      # input = <<-EOS
      # :release: Asciidoctor +
      #           {version}
      # EOS
      # doc = document_from_string input, attributes: { 'attribute-missing' => 'drop-line' }
      # doc.attributes['release'].should eq('')
      # assert_message @logger, :INFO, 'dropping line containing reference to missing attribute: version'
    end

    it "resolves attributes inside attribute value within header" do
      input = <<-EOS
      = Document Title
      :big: big
      :bigfoot: {big}foot

      {bigfoot}
      EOS

      result = TestHelpers.convert_string_to_embedded(input)
      result.should contain("bigfoot")
    end

    it "resolves attributes and pass macro inside attribute value outside header" do
      input = <<-EOS
      = Document Title

      content

      :big: pass:a,q[_big_]
      :bigfoot: {big}foot
      {bigfoot}
      EOS

      result = TestHelpers.convert_string_to_embedded(input)
      result.should contain("<em>big</em>foot")
    end

    it "should limit maximum size of attribute value if safe mode is SECURE" do
      expected = "a" * 4096
      input = <<-EOS
      :name: #{"a" * 5000}

      {name}
      EOS

      result = TestHelpers.convert_inline_string(input)
      result.should eq(expected)
      result.bytesize.should eq(4096)
    end

    it "should handle multibyte characters when limiting attribute value size" do
      expected = "日本"
      input = <<-EOS
      :name: 日本語

      {name}
      EOS

      result = TestHelpers.convert_inline_string(input, {"max-attribute-value-size" => "6"})
      result.should eq(expected)
      result.bytesize.should eq(6)
    end

    it "should not mangle multibyte characters when limiting attribute value size" do
      expected = "日本"
      input = <<-EOS
      :name: 日本語

      {name}
      EOS

      result = TestHelpers.convert_inline_string(input, {"max-attribute-value-size" => "8"})
      result.should eq(expected)
      result.bytesize.should eq(6)
    end

    it "should allow maximize size of attribute value to be disabled" do
      expected = "a" * 5000
      input = <<-EOS
      :name: #{"a" * 5000}

      {name}
      EOS

      result = TestHelpers.convert_inline_string(input, {"safe" => "safe"})
      result.should eq(expected)
      result.bytesize.should eq(5000)
    end

    it "resolves user-home attribute if safe mode is less than SERVER" do
      input = <<-EOS
      :imagesdir: {user-home}/etc/images

      {imagesdir}
      EOS
      output = TestHelpers.convert_inline_string(input, {"safe" => "safe"})
      output.should eq("#{Asciidoctor::USER_HOME}/etc/images")
    end

    it "user-home attribute resolves to . if safe mode is SERVER or greater" do
      input = <<-EOS
      :imagesdir: {user-home}/etc/images

      {imagesdir}
      EOS
      output = TestHelpers.convert_inline_string(input, {"safe" => "server"})
      output.should eq("./etc/images")
    end

    it "user-home attribute can be overridden by API if safe mode is less than SERVER" do
      input = <<-EOS
      Go {user-home}!
      EOS
      output = TestHelpers.convert_inline_string(input, {"user-home" => "/home"})
      output.should eq("Go /home!")
    end

    it "user-home attribute can be overridden by API if safe mode is SERVER or greater" do
      input = <<-EOS
      Go {user-home}!
      EOS
      output = TestHelpers.convert_inline_string(input, {"safe" => "server", "user-home" => "/home"})
      output.should eq("Go /home!")
    end

    it "apply custom substitutions to text in passthrough macro and assign to attribute" do
      doc = TestHelpers.document_from_string(":xml-busters: pass:[<>&]")
      doc.attributes["xml-busters"].should eq("<>&")
      doc = TestHelpers.document_from_string(":xml-busters: pass:none[<>&]")
      doc.attributes["xml-busters"].should eq("<>&")
      doc = TestHelpers.document_from_string(":xml-busters: pass:specialcharacters[<>&]")
      doc.attributes["xml-busters"].should eq("&lt;&gt;&amp;")
      doc = TestHelpers.document_from_string(":xml-busters: pass:n,-c[<(C)>]")
      doc.attributes["xml-busters"].should eq("<&#169;>")
    end

    it "should not recognize pass macro with invalid substitution list in attribute value" do
      [",", "42", "a,"].each do |subs|
        doc = TestHelpers.document_from_string(":pass-fail: pass:#{subs}[whale]")
        doc.attributes["pass-fail"].should eq("pass:#{subs}[whale]")
      end
    end

    it "attribute is treated as defined until it is unset" do
      input = <<-EOS
      :holygrail:
      ifdef::holygrail[]
      The holy grail has been found!
      endif::holygrail[]

      :holygrail!:
      ifndef::holygrail[]
      Buggers! What happened to the grail?
      endif::holygrail[]
      EOS
      output = TestHelpers.convert_string(input)
      TestHelpers.xpath_count("//p", output).should eq(2)
      TestHelpers.xpath_count("(//p)[1][text() = \"The holy grail has been found!\"]", output).should eq(1)
      TestHelpers.xpath_count("(//p)[2][text() = \"Buggers! What happened to the grail?\"]", output).should eq(1)
    end
  end


  context "API" do
    it "attribute set via API overrides attribute set in document" do
      doc = TestHelpers.document_from_string(":cash: money", {"cash" => "heroes"})
      doc.attributes["cash"].should eq("heroes")
    end

    it "attribute set via API cannot be unset by document" do
      doc = TestHelpers.document_from_string(":cash!:", {"cash" => "heroes"})
      doc.attributes["cash"].should eq("heroes")
    end

    it "attribute soft set via API using modifier on name can be overridden by document" do
      doc = TestHelpers.document_from_string(":cash: money", {"cash@" => "heroes"})
      doc.attributes["cash"].should eq("money")
    end

    it "attribute soft set via API using modifier on value can be overridden by document" do
      doc = TestHelpers.document_from_string(":cash: money", {"cash" => "heroes@"})
      doc.attributes["cash"].should eq("money")
    end

    it "attribute soft set via API using modifier on name can be unset by document" do
      doc = TestHelpers.document_from_string(":cash!:", {"cash@" => "heroes"})
      doc.attributes["cash"]?.should be_nil
      doc = TestHelpers.document_from_string(":cash!:", {"cash@" => "true"})
      doc.attributes["cash"]?.should be_nil
    end

    it "attribute soft set via API using modifier on value can be unset by document" do
      doc = TestHelpers.document_from_string(":cash!:", {"cash" => "heroes@"})
      doc.attributes["cash"]?.should be_nil
    end

    it "attribute unset via API cannot be set by document" do
      [
        {"cash!" => ""},
        {"!cash" => ""},
      ].each do |attributes|
        doc = TestHelpers.document_from_string(":cash: money", attributes)
        doc.attributes["cash"]?.should be_nil
      end
    end

    it "attribute soft unset via API can be set by document" do
      [
        {"cash!@" => ""},
        {"!cash@" => ""},
        {"cash!" => "@"},
        {"!cash" => "@"},
        {"cash" => "false"},
      ].each do |attributes|
        doc = TestHelpers.document_from_string(":cash: money", attributes)
        doc.attributes["cash"].should eq("money")
      end
    end

    it "can soft unset built-in attribute from API and still override in document" do
      # [
      #   { "sectids!@" => "" },
      #   { "!sectids@" => "" },
      #   { "sectids!" => "@" },
      #   { "!sectids" => "@" },
      #   { "sectids" => false },
      # ].each do |attributes|
      #   doc = document_from_string("== Heading", attributes: attributes)
      #   doc.attr?("sectids").should be_falsey
      #   assert_css "#_heading", (doc.convert standalone: false), 0
      #   doc = document_from_string(":sectids:\n\n== Heading", attributes: attributes)
      #   doc.attr?("sectids").should be_truthy
      #   assert_css "#_heading", (doc.convert standalone: false), 1
      # end
    end
  end

  end

  context "Default Attributes" do
    it "backend and doctype attributes are set by default in default configuration" do
      input = <<-EOS
      = Document Title
      Author Name

      content
      EOS

      doc = TestHelpers.document_from_string(input)
      expect = {
        "backend" => "html5",
        "backend-html5" => "",
        "backend-html5-doctype-article" => "",
        "outfilesuffix" => ".html",
        "basebackend" => "html",
        "basebackend-html" => "",
        "basebackend-html-doctype-article" => "",
        "doctype" => "article",
        "doctype-article" => "",
        "filetype" => "html",
        "filetype-html" => "",
      }
      expect.each do |key, val|
        doc.attributes.has_key?(key).should be_truthy
        doc.attributes[key].should eq(val)
      end
    end

    it "backend and doctype attributes are set by default in custom configuration" do
      input = <<-EOS
      = Document Title
      Author Name

      content
      EOS

      doc = TestHelpers.document_from_string(input, {"doctype" => "book", "backend" => "docbook"})
      expect = {
        "backend" => "docbook5",
        "backend-docbook5" => "",
        "backend-docbook5-doctype-book" => "",
        "outfilesuffix" => ".xml",
        "basebackend" => "docbook",
        "basebackend-docbook" => "",
        "basebackend-docbook-doctype-book" => "",
        "doctype" => "book",
        "doctype-book" => "",
        "filetype" => "xml",
        "filetype-xml" => "",
      }
      expect.each do |key, val|
        doc.attributes.has_key?(key).should be_truthy
        doc.attributes[key].should eq(val)
      end
    end

    it "backend attributes are updated if backend attribute is defined in document and safe mode is less than SERVER" do
      input = <<-EOS
      = Document Title
      Author Name
      :backend: docbook
      :doctype: book

      content
      EOS

      doc = TestHelpers.document_from_string(input, {"safe" => "1"})
      expect = {
        "backend" => "docbook5",
        "backend-docbook5" => "",
        "backend-docbook5-doctype-book" => "",
        "outfilesuffix" => ".xml",
        "basebackend" => "docbook",
        "basebackend-docbook" => "",
        "basebackend-docbook-doctype-book" => "",
        "doctype" => "book",
        "doctype-book" => "",
        "filetype" => "xml",
        "filetype-xml" => "",
      }
      expect.each do |key, val|
        doc.attributes.has_key?(key).should be_truthy
        doc.attributes[key].should eq(val)
      end

      doc.attributes.has_key?("backend-html5").should be_falsey
      doc.attributes.has_key?("backend-html5-doctype-article").should be_falsey
      doc.attributes.has_key?("basebackend-html").should be_falsey
      doc.attributes.has_key?("basebackend-html-doctype-article").should be_falsey
      doc.attributes.has_key?("doctype-article").should be_falsey
      doc.attributes.has_key?("filetype-html").should be_falsey
    end

    it "backend attributes defined in document options overrides backend attribute in document" do
      doc = TestHelpers.document_from_string(":backend: docbook5", {"safe" => "1", "backend" => "html5"})
      doc.attributes["backend"].should eq("html5")
      doc.attributes.has_key?("backend-html5").should be_truthy
      doc.attributes["basebackend"].should eq("html")
      doc.attributes.has_key?("basebackend-html").should be_truthy
    end
  end

  context "Block Attributes" do
    it "can only access a positional attribute from the attributes hash" do
      node = Asciidoctor::Block.new(TestHelpers.empty_document, :paragraph, nil, nil, {"1" => "position 1"})
      node.attr("1").should be_nil
      node.attr?("1").should be_falsey
      node.attributes["1"].should eq("position 1")
    end

    it "attr should not retrieve attribute from document if not set on block" do
      doc = TestHelpers.document_from_string("paragraph", {"name" => "value"})
      para = doc.blocks[0]
      para.attr("name").should be_nil
    end

    it "attr looks for attribute on document if fallback name is true" do
      doc = TestHelpers.document_from_string("paragraph", {"name" => "value"})
      para = doc.blocks[0]
      para.attr("name", nil, true).should eq("value")
    end

    it "attr uses fallback name when looking for attribute on document" do
      doc = TestHelpers.document_from_string("paragraph", {"alt-name" => "value"})
      para = doc.blocks[0]
      para.attr("name", nil, "alt-name").should eq("value")
    end

    it "attr? should not check for attribute on document if not set on block" do
      doc = TestHelpers.document_from_string("paragraph", {"name" => "value"})
      para = doc.blocks[0]
      para.attr?("name").should be_falsey
    end

    it "attr? checks for attribute on document if fallback name is true" do
      doc = TestHelpers.document_from_string("paragraph", {"name" => "value"})
      para = doc.blocks[0]
      para.attr?("name", nil, true).should be_truthy
    end

    it "attr? checks for fallback name when looking for attribute on document" do
      doc = TestHelpers.document_from_string("paragraph", {"alt-name" => "value"})
      para = doc.blocks[0]
      para.attr?("name", nil, "alt-name").should be_truthy
    end

    it "set_attr should set value to empty string if no value is specified" do
      node = Asciidoctor::Block.new(TestHelpers.empty_document, :paragraph)
      node.set_attr("foo")
      node.attr("foo").should eq("")
    end

    it "remove_attr should remove attribute and return previous value" do
      doc = TestHelpers.empty_document
      node = Asciidoctor::Block.new(doc, :paragraph, nil, nil, {"foo" => "bar"})
      node.remove_attr("foo").should eq("bar")
      node.attr("foo").should be_nil
    end

    it "set_attr should not overwrite existing key if overwrite is false" do
      node = Asciidoctor::Block.new(TestHelpers.empty_document, :paragraph, nil, nil, {"foo" => "bar"})
      node.attr("foo").should eq("bar")
      node.set_attr("foo", "baz", false)
      node.attr("foo").should eq("bar")
    end

    it "set_attr should overwrite existing key by default" do
      node = Asciidoctor::Block.new(TestHelpers.empty_document, :paragraph, nil, nil, {"foo" => "bar"})
      node.attr("foo").should eq("bar")
      node.set_attr("foo", "baz")
      node.attr("foo").should eq("baz")
    end

    pending "set_attr should set header attribute in loaded document" do
      # input = <<-EOS
      # :uri: http://example.org

      # {uri}
      # EOS

      # doc = Asciidoctor.load(input, {"uri" => "https://github.com"})
      # doc.set_attr("uri", "https://google.com")
      # output = doc.convert.to_s
      # TestHelpers.xpath_count("//a[@href=\"https://google.com\"]", output).should eq(1)
    end

    it "set_attribute should set attribute if key is not locked" do
      doc = TestHelpers.empty_document
      doc.attr?("foo").should be_falsey
      res = doc.set_attribute("foo", "baz")
      res.should be_truthy
      doc.attr("foo").should eq("baz")
    end

    it "set_attribute should not set key if key is locked" do
      doc = TestHelpers.empty_document({"foo" => "bar"})
      doc.attr("foo").should eq("bar")
      res = doc.set_attribute("foo", "baz")
      res.should be_falsey
      doc.attr("foo").should eq("bar")
    end

    it "set_attribute should update backend attributes" do
      doc = TestHelpers.empty_document({"backend" => "html5@"})
      doc.attr("backend-html5").should eq("")
      res = doc.set_attribute("backend", "docbook5")
      res.should be_truthy
      doc.attr?("backend-html5").should be_falsey
      doc.attr("backend-docbook5").should eq("")
    end
  end




  context "TOC Attributes" do
    pending "verify toc attribute matrix" do
      expected_data = <<-EOS
      #attributes                               |toc|toc-position|toc-placement|toc-class
      toc                                       |   |nil         |auto         |nil
      toc=header                                |   |nil         |auto         |nil
      toc=beeboo                                |   |nil         |auto         |nil
      toc=left                                  |   |left        |auto         |toc2
      toc2                                      |   |left        |auto         |toc2
      toc=right                                 |   |right       |auto         |toc2
      toc=preamble                              |   |content     |preamble     |nil
      toc=macro                                 |   |content     |macro        |nil
      toc toc-placement=macro toc-position=left |   |content     |macro        |nil
      toc toc-placement!                        |   |content     |macro        |nil
      EOS

      expected = expected_data.split("\n").map do |l|
        next if l.starts_with?("#")
        l.split("|").map(&.strip)
      end.compact

      expected.each do |(attributes, toc, toc_position, toc_placement, toc_class)|
        doc = TestHelpers.document_from_string("", {"attributes" => attributes})
        doc.attr?("toc").should eq(toc.empty? ? false : true)
        doc.attr("toc-position").should eq(toc_position == "nil" ? nil : toc_position)
        doc.attr("toc-placement").should eq(toc_placement == "nil" ? nil : toc_placement)
        doc.attr("toc-class").should eq(toc_class == "nil" ? nil : toc_class)
      end
    end
  end





  context "Interpolation" do
    it "convert properly with simple names" do
      html = TestHelpers.convert_string(":frog: Tanglefoot\n:my_super-hero: Spiderman\n\nYo, {frog}!\nBeat {my_super-hero}!")
      TestHelpers.xpath_count("//p[text()=\"Yo, Tanglefoot!\nBeat Spiderman!\"]", html).should eq(1)
    end

    it "attribute lookup is not case sensitive" do
      input = <<-EOS
      :He-Man: The most powerful man in the universe

      He-Man: {He-Man}

      She-Ra: {She-Ra}
      EOS
      result = TestHelpers.convert_string_to_embedded(input, {"She-Ra" => "The Princess of Power"})
      TestHelpers.xpath_count("//p[text()=\"He-Man: The most powerful man in the universe\"]", result).should eq(1)
      TestHelpers.xpath_count("//p[text()=\"She-Ra: The Princess of Power\"]", result).should eq(1)
    end

    it "convert properly with single character name" do
      html = TestHelpers.convert_string(":r: Ruby\n\nR is for {r}!")
      TestHelpers.xpath_count("//p[text()=\"R is for Ruby!\"]", html).should eq(1)
    end

    it "collapses spaces in attribute names" do
      input = <<-EOS
      = Main Header
      :My frog: Tanglefoot

      Yo, {myfrog}!
      EOS
      output = TestHelpers.convert_string(input)
      TestHelpers.xpath_count("(//p)[1][text()=\"Yo, Tanglefoot!\"]", output).should eq(1)
    end

    it "ignores lines with bad attributes if attribute-missing is drop-line" do
      # input = <<-EOS
      # :attribute-missing: drop-line

      # This is
      # blah blah {foobarbaz}
      # all there is.
      # EOS
      # output = convert_string_to_embedded input
      # para = xmlnodes_at_css "p", output, 1
      # refute_includes "blah blah", para.content
      # assert_message @logger, :INFO, "dropping line containing reference to missing attribute: foobarbaz"
    end

    it "attribute value gets interpreted when converting" do
      doc = TestHelpers.document_from_string(":google: http://google.com[Google]\n\n{google}")
      doc.attributes["google"].should eq("http://google.com[Google]")
      output = doc.convert.to_s
      TestHelpers.xpath_count("//a[@href=\"http://google.com\"][text() = \"Google\"]", output).should eq(1)
    end

    it "should drop line with reference to missing attribute if attribute-missing attribute is drop-line" do
      # input = <<-EOS
      # :attribute-missing: drop-line

      # Line 1: This line should appear in the output.
      # Line 2: Oh no, a {bogus-attribute}! This line should not appear in the output.
      # EOS

      # output = convert_string_to_embedded input
      # output.should match(/Line 1/)
      # output.should_not match(/Line 2/)
      # assert_message @logger, :INFO, "dropping line containing reference to missing attribute: bogus-attribute"
    end

    it "should not drop line with reference to missing attribute by default" do
      input = <<-EOS
      Line 1: This line should appear in the output.
      Line 2: A {bogus-attribute}! This time, this line should appear in the output.
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      output.should match(/Line 1/)
      output.should match(/Line 2/)
      output.should match(/\{bogus-attribute\}/)
    end

    it "should drop line with attribute unassignment by default" do
      input = <<-EOS
      :a:

      Line 1: This line should appear in the output.
      Line 2: {set:a!}This line should not appear in the output.
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      output.should match(/Line 1/)
      output.should_not match(/Line 2/)
    end

    it "should not drop line with attribute unassignment if attribute-undefined is drop" do
      input = <<-EOS
      :attribute-undefined: drop
      :a:

      Line 1: This line should appear in the output.
      Line 2: {set:a!}This line should appear in the output.
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      output.should match(/Line 1/)
      output.should match(/Line 2/)
      output.should_not match(/\{set:a!\}/)
    end

    it "should drop line that only contains attribute assignment" do
      input = <<-EOS
      Line 1
      {set:a}
      Line 2
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//p[text()=\"Line 1\nLine 2\"]", output).should eq(1)
    end

    it "should drop line that only contains unresolved attribute when attribute-missing is drop" do
      input = <<-EOS
      Line 1
      {unresolved}
      Line 2
      EOS

      output = TestHelpers.convert_string_to_embedded(input, {"attribute-missing" => "drop"})
      TestHelpers.xpath_count("//p[text()=\"Line 1\nLine 2\"]", output).should eq(1)
    end

    it "substitutes inside unordered list items" do
      html = TestHelpers.convert_string(":foo: bar\n* snort at the {foo}\n* yawn")
      TestHelpers.xpath_count("//li/p[text()=\"snort at the bar\"]", html).should eq(1)
    end

    it "substitutes inside section title" do
      output = TestHelpers.convert_string(":prefix: Cool\n\n== {prefix} Title\n\ncontent")
      TestHelpers.xpath_count("//h2[text()=\"Cool Title\"]", output).should eq(1)
      # Section ID generation from substituted title not yet implemented
      # TestHelpers.xpath_count("//h2[@id=\"_cool_title\"]", output).should eq(1)
    end

    it "interpolates attribute defined in header inside attribute entry in header" do
      input = <<-EOS
      = Title
      Author Name
      :attribute-a: value
      :attribute-b: {attribute-a}

      preamble
      EOS
      doc = TestHelpers.document_from_string(input, {"parse_header_only" => "true"})
      doc.attributes["attribute-b"].should eq("value")
    end

    it "interpolates author attribute inside attribute entry in header" do
      input = <<-EOS
      = Title
      Author Name
      :name: {author}

      preamble
      EOS
      doc = TestHelpers.document_from_string(input, {"parse_header_only" => "true"})
      doc.attributes["name"].should eq("Author Name")
    end

    it "interpolates revinfo attribute inside attribute entry in header" do
      input = <<-EOS
      = Title
      Author Name
      2013-01-01
      :date: {revdate}

      preamble
      EOS
      doc = TestHelpers.document_from_string(input, {"parse_header_only" => "true"})
      doc.attributes["date"].should eq("2013-01-01")
    end

    it "attribute entries can resolve previously defined attributes" do
      input = <<-EOS
      = Title
      Author Name
      v1.0, 2010-01-01: First release!
      :a: value
      :a2: {a}
      :revdate2: {revdate}

      {a} == {a2}

      {revdate} == {revdate2}
      EOS

      doc = TestHelpers.document_from_string(input)
      doc.attr("revdate").should eq("2010-01-01")
      doc.attr("revdate2").should eq("2010-01-01")
      doc.attr("a").should eq("value")
      doc.attr("a2").should eq("value")

      output = doc.convert.to_s
      output.should contain("value == value")
      output.should contain("2010-01-01 == 2010-01-01")
    end

    it "should warn if unterminated block comment is detected in document header" do
      # input = <<-EOS
      # = Document Title
      # :foo: bar
      # ////
      # :hey: there

      # content
      # EOS
      # doc = document_from_string input
      # doc.attr("hey").should be_nil
      # assert_message @logger, :WARN, "<stdin>: line 3: unterminated comment block", Hash
    end

    it "substitutes inside block title" do
      input = <<-EOS
      :gem_name: asciidoctor

      .Require the +{gem_name}+ gem
      To use {gem_name}, the first thing to do is to import it in your Ruby source file.
      EOS
      output = TestHelpers.convert_string_to_embedded(input, {"compat-mode" => ""})
      TestHelpers.xpath_count("//*[@class=\"title\"]/code[text()=\"asciidoctor\"]", output).should eq(1)

      input = <<-EOS
      :gem_name: asciidoctor

      .Require the `{gem_name}` gem
      To use {gem_name}, the first thing to do is to import it in your Ruby source file.
      EOS
      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//*[@class=\"title\"]/code[text()=\"asciidoctor\"]", output).should eq(1)
    end

    it "sets attribute until it is deleted" do
      input = <<-EOS
      :foo: bar

      Crossing the {foo}.

      :foo!:

      Belly up to the {foo}.
      EOS
      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//p[text()=\"Crossing the bar.\"]", output).should eq(1)
      TestHelpers.xpath_count("//p[text()=\"Belly up to the bar.\"]", output).should eq(0)
    end

    pending "should allow compat-mode to be set and unset in middle of document" do
      input = <<-EOS
      :foo: bar

      [[paragraph-a]]
      `{foo}`

      :compat-mode!:

      [[paragraph-b]]
      `{foo}`

      :compat-mode:

      [[paragraph-c]]
      `{foo}`
      EOS

      result = TestHelpers.convert_string_to_embedded(input, {"compat-mode" => "@"})
      TestHelpers.xpath_count("/*[@id=\"paragraph-a\"]//code[text()=\"{foo}\"]", result).should eq(1)
      TestHelpers.xpath_count("/*[@id=\"paragraph-b\"]//code[text()=\"bar\"]", result).should eq(1)
      TestHelpers.xpath_count("/*[@id=\"paragraph-c\"]//code[text()=\"{foo}\"]", result).should eq(1)
    end

    it "does not disturb attribute-looking things escaped with backslash" do
      html = TestHelpers.convert_string(":foo: bar\nThis is a \\{foo} day.")
      TestHelpers.xpath_count("//p[text()=\"This is a {foo} day.\"]", html).should eq(1)
    end
  end
  context "Substitution and Escaping" do

    it "does not disturb attribute-looking things escaped with literals" do
      html = TestHelpers.convert_string(":foo: bar\nThis is a +++{foo}+++ day.")
      TestHelpers.xpath_count("//p[text()=\"This is a {foo} day.\"]", html).should eq(1)
    end

    it "does not substitute attributes inside listing blocks" do
      input = <<-EOS
      :forecast: snow

      ----
      puts 'The forecast for today is {forecast}'
      ----
      EOS
      output = TestHelpers.convert_string(input)
      output.should match(/\{forecast\}/)
    end

    it "does not substitute attributes inside literal blocks" do
      input = <<-EOS
      :foo: bar

      ....
      You insert the text {foo} to expand the value
      of the attribute named foo in your document.
      ....
      EOS
      output = TestHelpers.convert_string(input)
      output.should match(/\{foo\}/)
    end

    it "does not show docdir and shows relative docfile if safe mode is SERVER or greater" do
      input = <<-EOS
      * docdir: {docdir}
      * docfile: {docfile}
      EOS

      docdir = Dir.current
      docfile = File.join(docdir, "sample.adoc")
      output = TestHelpers.convert_string_to_embedded(input, {"safe" => "server", "docdir" => docdir, "docfile" => docfile})
      TestHelpers.xpath_count("//li[1]/p[text()=\"docdir: \"]", output).should eq(1)
      TestHelpers.xpath_count("//li[2]/p[text()=\"docfile: sample.adoc\"]", output).should eq(1)
    end

    it "shows absolute docdir and docfile paths if safe mode is less than SERVER" do
      input = <<-EOS
      * docdir: {docdir}
      * docfile: {docfile}
      EOS

      docdir = Dir.current
      docfile = File.join(docdir, "sample.adoc")
      output = TestHelpers.convert_string_to_embedded(input, {"safe" => "safe", "docdir" => docdir, "docfile" => docfile})
      TestHelpers.xpath_count("//li[1]/p[text()=\"docdir: #{docdir}\"]", output).should eq(1)
      TestHelpers.xpath_count("//li[2]/p[text()=\"docfile: #{docfile}\"]", output).should eq(1)
    end

    it "assigns attribute defined in attribute reference with set prefix and value" do
      input = "{set:foo:bar}{foo}"
      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//p", output).should eq(1)
      TestHelpers.xpath_count("//p[text()=\"bar\"]", output).should eq(1)
    end

    it "assigns attribute defined in attribute reference with set prefix and no value" do
      input = "{set:foo}\n{foo}yes"
      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//p", output).should eq(1)
      TestHelpers.xpath_count("//p[normalize-space(text())=\"yes\"]", output).should eq(1)
    end

    it "assigns attribute defined in attribute reference with set prefix and empty value" do
      input = "{set:foo:}\n{foo}yes"
      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//p", output).should eq(1)
      TestHelpers.xpath_count("//p[normalize-space(text())=\"yes\"]", output).should eq(1)
    end

    it "unassigns attribute defined in attribute reference with set prefix" do
      # input = <<-EOS
      # :attribute-missing: drop-line
      # :foo:

      # {set:foo!}
      # {foo}yes
      # EOS
      # output = convert_string_to_embedded input
      # TestHelpers.xpath_count("//p", output).should eq(1)
      # TestHelpers.xpath_count("//p/child::text()", output).should eq(0)
      # assert_message @logger, :INFO, "dropping line containing reference to missing attribute: foo"
    end







  context "Intrinsic attributes" do
    it "substitute intrinsics" do
      Asciidoctor::INTRINSIC_ATTRIBUTES.each do |key, value|
        html = TestHelpers.convert_string("Look, a {#{key}} is here")
        html.should contain("Look, a #{value} is here")
      end
    end

    it "do not escape intrinsic substitutions" do
      html = TestHelpers.convert_string("happy{nbsp}together")
      html.should match(/happy&#160;together/)
    end

    it "escape special characters" do
      html = TestHelpers.convert_string("<node>&</node>")
      html.should match(/&lt;node&gt;&amp;&lt;\/node&gt;/)
    end

    it "creates counter" do
      input = "{counter:mycounter}"

      doc = TestHelpers.document_from_string(input)
      output = doc.convert.to_s
      doc.attributes["mycounter"].should eq("1")
      TestHelpers.xpath_count("//p[text()=\"1\"]", output).should eq(1)
    end

    it "creates counter silently" do
      input = "{counter2:mycounter}"

      doc = TestHelpers.document_from_string(input)
      output = doc.convert.to_s
      doc.attributes["mycounter"].should eq("1")
      TestHelpers.xpath_count("//p[text()=\"1\"]", output).should eq(0)
    end

    it "creates counter with numeric seed value" do
      input = "{counter2:mycounter:10}"

      doc = TestHelpers.document_from_string(input)
      doc.convert
      doc.attributes["mycounter"].should eq("10")
    end

    it "creates counter with character seed value" do
      input = "{counter2:mycounter:A}"

      doc = TestHelpers.document_from_string(input)
      doc.convert
      doc.attributes["mycounter"].should eq("A")
    end

    it "can seed counter to start at 1" do
      input = <<-EOS
      :mycounter: 0

      {counter:mycounter}
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//p[text()=\"1\"]", output).should eq(1)
    end

    it "can seed counter to start at A" do
      input = <<-EOS
      :mycounter: @

      {counter:mycounter}
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//p[text()=\"A\"]", output).should eq(1)
    end

    it "increments counter with positive numeric value" do
      input = <<-EOS
      [subs=attributes]
      ++++
      {counter:mycounter:1}
      {counter:mycounter}
      {counter:mycounter}
      {mycounter}
      ++++
      EOS

      doc = TestHelpers.document_from_string(input, {"standalone" => "false"})
      output = doc.convert.to_s
      doc.attributes["mycounter"].should eq("3")
      output.split("\n").map(&.strip).should eq(["1", "2", "3", "3"])
    end

    it "increments counter with negative numeric value" do
      input = <<-EOS
      [subs=attributes]
      ++++
      {counter:mycounter:-2}
      {counter:mycounter}
      {counter:mycounter}
      {mycounter}
      ++++
      EOS

      doc = TestHelpers.document_from_string(input, {"standalone" => "false"})
      output = doc.convert.to_s
      doc.attributes["mycounter"].should eq("0")
      output.split("\n").map(&.strip).should eq(["-2", "-1", "0", "0"])
    end

    it "increments counter with ASCII character value" do
      input = <<-EOS
      [subs=attributes]
      ++++
      {counter:mycounter:A}
      {counter:mycounter}
      {counter:mycounter}
      {mycounter}
      ++++
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      output.split("\n").map(&.strip).should eq(["A", "B", "C", "C"])
    end

    it "increments counter with non-ASCII character value" do
      input = <<-EOS
      [subs=attributes]
      ++++
      {counter:mycounter:é}
      {counter:mycounter}
      {counter:mycounter}
      {mycounter}
      ++++
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      output.split("\n").map(&.strip).should eq(["é", "ê", "ë", "ë"])
    end

    it "increments counter with emoji character value" do
      input = <<-EOS
      [subs=attributes]
      ++++
      {counter:smiley:😋}
      {counter:smiley}
      {counter:smiley}
      {smiley}
      ++++
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      output.split("\n").map(&.strip).should eq(["😋", "😌", "😍", "😍"])
    end

    it "increments counter with multi-character value" do
      input = <<-EOS
      [subs=attributes]
      ++++
      {counter:math:1x}
      {counter:math}
      {counter:math}
      {math}
      ++++
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      output.split("\n").map(&.strip).should eq(["1x", "1y", "1z", "1z"])
    end

    it "counter uses 0 as seed value if seed attribute is nil" do
      input = <<-EOS
      :mycounter:

      {counter:mycounter}

      {mycounter}
      EOS

      doc = TestHelpers.document_from_string(input)
      output = doc.convert({"standalone" => "false"}).to_s
      doc.attributes["mycounter"].should eq("1")
      TestHelpers.xpath_count("//p[text()=\"1\"]", output).should eq(2)
    end

    it "counter value can be reset by attribute entry" do
      input = <<-EOS
      :mycounter:

      before: {counter:mycounter} {counter:mycounter} {counter:mycounter}

      :mycounter!:

      after: {counter:mycounter}
      EOS

      doc = TestHelpers.document_from_string(input)
      output = doc.convert({"standalone" => "false"}).to_s
      doc.attributes["mycounter"].should eq("1")
      TestHelpers.xpath_count("//p[text()=\"before: 1 2 3\"]", output).should eq(1)
      TestHelpers.xpath_count("//p[text()=\"after: 1\"]", output).should eq(1)
    end

    pending "counter value can be advanced by attribute entry" do
      input = <<-EOS
      before: {counter:mycounter}

      :mycounter: 10
      EOS
      doc = TestHelpers.document_from_string(input)
      output = doc.convert({"standalone" => "false"}).to_s
      doc.attributes["mycounter"].should eq("10")
      TestHelpers.xpath_count("//p[text()=\"before: 1\"]", output).should eq(1)
    end
  end

    pending "nested document should use counter from parent document" do
      input = <<-EOS
      .Title for Foo
      image::foo.jpg[]

      [cols="2*a"]
      |===
      |
      .Title for Bar
      image::bar.jpg[]

      |
      .Title for Baz
      image::baz.jpg[]
      |===

      .Title for Qux
      image::qux.jpg[]
      EOS

      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//div[@class=\"title\"]", output).should eq(4)
      TestHelpers.xpath_count("//div[@class=\"title\"][text() = \"Figure 1. Title for Foo\"]", output).should eq(1)
      TestHelpers.xpath_count("//div[@class=\"title\"][text() = \"Figure 2. Title for Bar\"]", output).should eq(1)
      TestHelpers.xpath_count("//div[@class=\"title\"][text() = \"Figure 3. Title for Baz\"]", output).should eq(1)
      TestHelpers.xpath_count("//div[@class=\"title\"][text() = \"Figure 4. Title for Qux\"]", output).should eq(1)
    end

    it "should not allow counter to modify locked attribute" do
      input = <<-EOS
      {counter:foo:ignored} is not {foo}
      EOS

      output = TestHelpers.convert_string_to_embedded(input, {"foo" => "bar"})
      TestHelpers.xpath_count("//p[text()=\"bas is not bar\"]", output).should eq(1)
    end

    it "should not allow counter2 to modify locked attribute" do
      input = <<-EOS
      {counter2:foo:ignored}{foo}
      EOS

      output = TestHelpers.convert_string_to_embedded(input, {"foo" => "bar"})
      TestHelpers.xpath_count("//p[text()=\"bar\"]", output).should eq(1)
    end

    it "should not allow counter to modify built-in locked attribute" do
      input = <<-EOS
      {counter:max-include-depth:128} is one more than {max-include-depth}
      EOS

      doc = TestHelpers.document_from_string(input, {"standalone" => "false"})
      output = doc.convert.to_s
      TestHelpers.xpath_count("//p[text()=\"65 is one more than 64\"]", output).should eq(1)
      doc.attributes["max-include-depth"].should eq("64")
    end

    it "should not allow counter2 to modify built-in locked attribute" do
      input = <<-EOS
      {counter2:max-include-depth:128}{max-include-depth}
      EOS

      doc = TestHelpers.document_from_string(input, {"standalone" => "false"})
      output = doc.convert.to_s
      TestHelpers.xpath_count("//p[text()=\"64\"]", output).should eq(1)
      doc.attributes["max-include-depth"].should eq("64")
    end


  context "Block attributes" do
    it "parses named attribute with valid name" do
      input = <<-EOS
      [normal,foo="bar",_foo="_bar",foo1="bar1",foo-foo="bar-bar",foo.foo="bar.bar"]
      content
      EOS

      block = TestHelpers.block_from_string(input)
      block.attr("foo").should eq("bar")
      block.attr("_foo").should eq("_bar")
      block.attr("foo1").should eq("bar1")
      block.attr("foo-foo").should eq("bar-bar")
    end

    it "does not parse named attribute if name is invalid" do
      input = <<-EOS
      [normal,foo.foo="bar.bar",-foo-foo="-bar-bar"]
      content
      EOS

      block = TestHelpers.block_from_string(input)
      block.attributes["2"].should eq("foo.foo=\"bar.bar\"")
      block.attributes["3"].should eq("-foo-foo=\"-bar-bar\"")
    end

    it "positional attributes assigned to block" do
      input = <<-EOS
      [quote, author, source]
      ____
      A famous quote.
      ____
      EOS
      doc = TestHelpers.document_from_string(input)
      qb = doc.blocks.first
      qb.style.should eq("quote")
      qb.attr("attribution").should eq("author")
      qb.attributes["attribution"].should eq("author")
      qb.attributes["citetitle"].should eq("source")
    end

    it "normal substitutions are performed on single-quoted positional attribute" do
      input = <<-EOS
      [quote, author, 'http://wikipedia.org[source]']
      ____
      A famous quote.
      ____
      EOS
      doc = TestHelpers.document_from_string(input)
      qb = doc.blocks.first
      qb.style.should eq("quote")
      qb.attr("attribution").should eq("author")
      qb.attributes["attribution"].should eq("author")
      qb.attributes["citetitle"].should eq("<a href=\"http://wikipedia.org\">source</a>")
    end

    it "normal substitutions are performed on single-quoted named attribute" do
      input = <<-EOS
      [quote, author, citetitle='http://wikipedia.org[source]']
      ____
      A famous quote.
      ____
      EOS
      doc = TestHelpers.document_from_string(input)
      qb = doc.blocks.first
      qb.style.should eq("quote")
      qb.attr("attribution").should eq("author")
      qb.attributes["attribution"].should eq("author")
      qb.attributes["citetitle"].should eq("<a href=\"http://wikipedia.org\">source</a>")
    end

    it "normal substitutions are performed once on single-quoted named title attribute" do
      input = <<-EOS
      [title='*title*']
      content
      EOS
      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//*[@class=\"title\"]/strong[text()=\"title\"]", output).should eq(1)
    end

    it "attribute list may not begin with space" do
      input = <<-EOS
      [ quote]
      ____
      A famous quote.
      ____
      EOS

      doc = TestHelpers.document_from_string(input)
      b1 = doc.blocks.first
      b1.as(Asciidoctor::Block).lines.should eq(["[ quote]"])
    end

    it "attribute list may begin with comma" do
      input = <<-EOS
      [, author, source]
      ____
      A famous quote.
      ____
      EOS

      doc = TestHelpers.document_from_string(input)
      qb = doc.blocks.first
      qb.style.should eq("quote")
      qb.attributes["attribution"].should eq("author")
      qb.attributes["citetitle"].should eq("source")
    end

    it "first attribute in list may be double quoted" do
      input = <<-EOS
      ["quote", "author", "source", role="famous"]
      ____
      A famous quote.
      ____
      EOS

      doc = TestHelpers.document_from_string(input)
      qb = doc.blocks.first
      qb.style.should eq("quote")
      qb.attributes["attribution"].should eq("author")
      qb.attributes["citetitle"].should eq("source")
      qb.attributes["role"].should eq("famous")
    end

    it "first attribute in list may be single quoted" do
      input = <<-EOS
      ['quote', 'author', 'source', role='famous']
      ____
      A famous quote.
      ____
      EOS

      doc = TestHelpers.document_from_string(input)
      qb = doc.blocks.first
      qb.style.should eq("quote")
      qb.attributes["attribution"].should eq("author")
      qb.attributes["citetitle"].should eq("source")
      qb.attributes["role"].should eq("famous")
    end

    it "attribute with value None without quotes is ignored" do
      input = <<-EOS
      [id=None]
      paragraph
      EOS

      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.attributes.has_key?("id").should be_falsey
    end

    it "role? returns true if role is assigned" do
      input = <<-EOS
      [role="lead"]
      A paragraph
      EOS

      doc = TestHelpers.document_from_string(input)
      p = doc.blocks.first
      p.role?.should be_truthy
    end

    it "role? does not return true if role attribute is set on document" do
      input = <<-EOS
      :role: lead

      A paragraph
      EOS

      doc = TestHelpers.document_from_string(input)
      p = doc.blocks.first
      p.role?.should be_falsey
    end

    it "role? can check for exact role name match" do
      input = <<-EOS
      [role="lead"]
      A paragraph
      EOS

      doc = TestHelpers.document_from_string(input)
      p = doc.blocks.first
      p.role?("lead").should be_truthy
      p2 = doc.blocks.last
      p2.role?("final").should be_falsey
    end

    it "has_role? can check for presence of role name" do
      input = <<-EOS
      [role="lead abstract"]
      A paragraph
      EOS

      doc = TestHelpers.document_from_string(input)
      p = doc.blocks.first
      p.role?("lead").should be_falsey
      p.has_role?("lead").should be_truthy
    end

    it "has_role? does not look for role defined as document attribute" do
      input = <<-EOS
      :role: lead abstract

      A paragraph
      EOS

      doc = TestHelpers.document_from_string(input)
      p = doc.blocks.first
      p.has_role?("lead").should be_falsey
    end

    it "roles returns array of role names" do
      input = <<-EOS
      [role="story lead"]
      A paragraph
      EOS

      doc = TestHelpers.document_from_string(input)
      p = doc.blocks.first
      p.roles.should eq(["story", "lead"])
    end
  end


    it "roles returns empty array if role attribute is not set" do
      input = "a paragraph"

      doc = TestHelpers.document_from_string(input)
      p = doc.blocks.first
      p.roles.empty?.should be_truthy
    end

    it "roles does not return value of roles document attribute" do
      input = <<-EOS
      :role: story lead

      A paragraph
      EOS

      doc = TestHelpers.document_from_string(input)
      p = doc.blocks.first
      p.roles.empty?.should be_truthy
    end

    it "roles= sets the role attribute on the node" do
      doc = TestHelpers.document_from_string("a paragraph")
      p = doc.blocks.first
      p.role = "foobar"
      p.attr("role").should eq("foobar")
    end

    it "roles= coerces array value to a space-separated string" do
      doc = TestHelpers.document_from_string("a paragraph")
      p = doc.blocks.first
      p.role = ["foo", "bar"]
      p.attr("role").should eq("foo bar")
    end

    it "Attribute substitutions are performed on attribute list before parsing attributes" do
      input = <<-EOS
      :lead: role=\"lead\"

      [{lead}]
      A paragraph
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.attributes["role"].should eq("lead")
    end

    it "id, role and options attributes can be specified on block style using shorthand syntax" do
      input = <<-EOS
      [literal#first.lead%step]
      A literal paragraph.
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.context.should eq(:literal)
      para.attributes["id"].should eq("first")
      para.attributes["role"].should eq("lead")
      para.attributes.has_key?("step-option").should be_truthy
      para.attributes.has_key?("options").should be_falsey
    end

    it "id, role and options attributes can be specified using shorthand syntax on block style using multiple block attribute lines" do
      input = <<-EOS
      [literal]
      [#first]
      [.lead]
      [%step]
      A literal paragraph.
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.context.should eq(:literal)
      para.attributes["id"].should eq("first")
      para.attributes["role"].should eq("lead")
      para.attributes.has_key?("step-option").should be_truthy
      para.attributes.has_key?("options").should be_falsey
    end

    it "multiple roles and options can be specified in block style using shorthand syntax" do
      input = <<-EOS
      [.role1%option1.role2%option2]
      Text
      EOS

      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.attributes["role"].should eq("role1 role2")
      para.attributes.has_key?("option1-option").should be_truthy
      para.attributes.has_key?("option2-option").should be_truthy
      para.attributes.has_key?("options").should be_falsey
    end

    it "options specified using shorthand syntax on block style across multiple lines should be additive" do
      input = <<-EOS
      [%option1]
      [%option2]
      Text
      EOS

      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.attributes.has_key?("option1-option").should be_truthy
      para.attributes.has_key?("option2-option").should be_truthy
      para.attributes.has_key?("options").should be_falsey
    end

    it "roles specified using shorthand syntax on block style across multiple lines should be additive" do
      input = <<-EOS
      [.role1]
      [.role2.role3]
      Text
      EOS

      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.attributes["role"].should eq("role1 role2 role3")
    end

    it "setting a role using the role attribute replaces any existing roles" do
      input = <<-EOS
      [.role1]
      [role=role2]
      [.role3]
      Text
      EOS

      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.attributes["role"].should eq("role2 role3")
    end

    it "setting a role using the shorthand syntax on block style should not clear the ID" do
      input = <<-EOS
      [#id]
      [.role]
      Text
      EOS

      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.id.should eq("id")
      para.role.should eq("role")
    end

    it "a role can be added using add_role when the node has no roles" do
      input = "A normal paragraph"
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      res = para.add_role("role1")
      res.should be_truthy
      para.attributes["role"].should eq("role1")
      para.has_role?("role1").should be_truthy
    end

    it "a role can be added using add_role when the node already has a role" do
      input = <<-EOS
      [.role1]
      A normal paragraph
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      res = para.add_role("role2")
      res.should be_truthy
      para.attributes["role"].should eq("role1 role2")
      para.has_role?("role1").should be_truthy
      para.has_role?("role2").should be_truthy
    end

    it "a role is not added using add_role if the node already has that role" do
      input = <<-EOS
      [.role1]
      A normal paragraph
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      res = para.add_role("role1")
      res.should be_falsey
      para.attributes["role"].should eq("role1")
      para.has_role?("role1").should be_truthy
    end

    it "an existing role can be removed using remove_role" do
      input = <<-EOS
      [.role1.role2]
      A normal paragraph
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      res = para.remove_role("role1")
      res.should be_truthy
      para.attributes["role"].should eq("role2")
      para.has_role?("role2").should be_truthy
      para.has_role?("role1").should be_falsey
    end

    it "roles are removed when last role is removed using remove_role" do
      input = <<-EOS
      [.role1]
      A normal paragraph
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      res = para.remove_role("role1")
      res.should be_truthy
      para.role?.should be_falsey
      para.attributes["role"]?.should be_nil
      para.has_role?("role1").should be_falsey
    end

    it "roles are not changed when a non-existent role is removed using remove_role" do
      input = <<-EOS
      [.role1]
      A normal paragraph
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      res = para.remove_role("role2")
      res.should be_falsey
      para.attributes["role"].should eq("role1")
      para.has_role?("role1").should be_truthy
      para.has_role?("role2").should be_falsey
    end

    it "roles are not changed when using remove_role if the node has no roles" do
      input = "A normal paragraph"
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      res = para.remove_role("role1")
      res.should be_falsey
      para.attributes["role"]?.should be_nil
      para.has_role?("role1").should be_falsey
    end

    it "option can be specified in first position of block style using shorthand syntax" do
      input = <<-EOS
      [%interactive]
      - [x] checked
      EOS

      doc = TestHelpers.document_from_string(input)
      list = doc.blocks.first
      list.attributes.has_key?("interactive-option").should be_truthy
      list.attributes.has_key?("options").should be_falsey
    end

    it "id and role attributes can be specified on section style using shorthand syntax" do
      input = <<-EOS
      [dedication#dedication.small]
      == Section
      Content.
      EOS
      output = TestHelpers.convert_string_to_embedded(input)
      TestHelpers.xpath_count("//div[@class=\"sect1 small\"]", output).should eq(1)
      TestHelpers.xpath_count("//div[@class=\"sect1 small\"]/h2[@id=\"dedication\"]", output).should eq(1)
    end

    pending "id attribute specified using shorthand syntax should not create a special section" do
      input = <<-EOS
      [#idname]
      == Section

      content
      EOS

      doc = TestHelpers.document_from_string(input, {"backend" => "docbook"})
      section = doc.blocks[0]
      section.should_not be_nil
      section.context.should eq(:section)
      section.as(Asciidoctor::Section).special.should be_falsey
      output = doc.convert.to_s
      TestHelpers.xpath_count("article:root > section", output).should eq(1)
      TestHelpers.xpath_count("article:root > section[xml|id=\"idname\"]", output).should eq(1)
    end

    it "Block attributes are additive" do
      input = <<-EOS
      [id=\"foo\"]
      [role=\"lead\"]
      A paragraph.
      EOS
      doc = TestHelpers.document_from_string(input)
      para = doc.blocks.first
      para.id.should eq("foo")
      para.attributes["role"].should eq("lead")
    end

    it "Last wins for id attribute" do
      input = <<-EOS
      [[bar]]
      [[foo]]
      == Section

      paragraph

      [[baz]]
      [id=\"coolio\"]
      === Section
      EOS
      doc = TestHelpers.document_from_string(input)
      sec = doc.first_section.not_nil!
      sec.id.should eq("foo")
      subsec = sec.blocks.last
      subsec.id.should eq("coolio")
    end

    it "trailing block attributes transfer to the following section" do
      input = <<-EOS
      [[one]]

      == Section One

      paragraph

      [[sub]]
      // try to mess this up!

      === Sub-section

      paragraph

      [role=\"classy\"]

      ////
      block comment
      ////

      == Section Two

      content
      EOS
      doc = TestHelpers.document_from_string(input)
      section_one = doc.blocks.first
      section_one.id.should eq("one")
      subsection = section_one.blocks.last
      subsection.id.should eq("sub")
      section_two = doc.blocks.last.as(Asciidoctor::Section)
      section_two.attr("role").should eq("classy")
    end




end
