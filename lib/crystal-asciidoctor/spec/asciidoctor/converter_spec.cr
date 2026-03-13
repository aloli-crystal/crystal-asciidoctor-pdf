require "../spec_helper"

# Custom converters for testing
class CustomHtmlConverterA < Asciidoctor::Converter::Base
  def convert(node : Asciidoctor::AbstractNode, transform : String? = nil) : String
    "document"
  end
end

class CustomTextConverterA < Asciidoctor::Converter::Base
  def convert(node : Asciidoctor::AbstractNode, transform : String? = nil) : String
    "document"
  end
end

class CustomConverterForRegistration < Asciidoctor::Converter::Base
  def convert(node : Asciidoctor::AbstractNode, transform : String? = nil) : String
    "custom content"
  end
end

class CustomConverterForRegistration2 < Asciidoctor::Converter::Base
  def convert(node : Asciidoctor::AbstractNode, transform : String? = nil) : String
    "custom content 2"
  end
end

# Helper methods
def convert_string(input : String, options : Hash(String, String) = {} of String => String) : String
  options["standalone"] = "true" unless options.has_key?("standalone")
  Asciidoctor.convert(input, options)
end

def convert_string_to_embedded(input : String, options : Hash(String, String) = {} of String => String) : String
  options["standalone"] = "false"
  Asciidoctor.convert(input, options)
end

def document_from_string(input : String, options : Hash(String, String) = {} of String => String) : Asciidoctor::Document
  Asciidoctor.load(input, options)
end

describe Asciidoctor::Converter do
  describe "BackendTraits" do
    it "should derive backend traits for html5 backend" do
      traits = Asciidoctor::Converter::Base.derive_backend_traits("html5")
      traits.basebackend.should eq("html")
      traits.filetype.should eq("html")
      traits.outfilesuffix.should eq(".html")
      traits.htmlsyntax.should eq("html")
    end

    it "should derive backend traits for docbook5 backend" do
      traits = Asciidoctor::Converter::Base.derive_backend_traits("docbook5")
      traits.basebackend.should eq("docbook")
      traits.filetype.should eq("xml")
      traits.outfilesuffix.should eq(".xml")
    end

    it "should derive backend traits for unknown backend" do
      traits = Asciidoctor::Converter::Base.derive_backend_traits("dita2")
      traits.basebackend.should eq("dita")
      traits.filetype.should eq("dita")
      traits.outfilesuffix.should eq(".dita")
    end

    it "should derive backend traits with explicit basebackend" do
      traits = Asciidoctor::Converter::Base.derive_backend_traits("slides", "html")
      traits.basebackend.should eq("html")
      traits.filetype.should eq("html")
      traits.outfilesuffix.should eq(".html")
      traits.htmlsyntax.should eq("html")
    end
  end

  describe "Base" do
    it "should initialize with backend and derive traits" do
      converter = Asciidoctor::Converter::Html5Converter.new("html5")
      converter.backend.should eq("html5")
      converter.backend_traits.basebackend.should eq("html")
    end

    it "should allow overriding backend traits with init_backend_traits" do
      converter = CustomHtmlConverterA.new("custom")
      converter.backend_traits.basebackend.should eq("custom")
    end
  end

  describe "DefaultRegistry" do
    it "should have built-in html5 converter registered" do
      Asciidoctor::Converter::DefaultRegistry.converter_for("html5").should eq(Asciidoctor::Converter::Html5Converter)
    end

    it "should have built-in docbook5 converter registered" do
      Asciidoctor::Converter::DefaultRegistry.converter_for("docbook5").should eq(Asciidoctor::Converter::DocBook5Converter)
    end

    it "should have built-in manpage converter registered" do
      Asciidoctor::Converter::DefaultRegistry.converter_for("manpage").should eq(Asciidoctor::Converter::ManPageConverter)
    end

    it "should return nil for unregistered backend" do
      Asciidoctor::Converter::DefaultRegistry.converter_for("nonexistent").should be_nil
    end

    it "should create an instance of a registered converter" do
      converter = Asciidoctor::Converter::DefaultRegistry.create("html5")
      converter.should_not be_nil
      converter.should be_a(Asciidoctor::Converter::Html5Converter)
    end

    it "should return nil when creating instance for unregistered backend" do
      Asciidoctor::Converter::DefaultRegistry.create("nonexistent").should be_nil
    end

    it "should register and retrieve a custom converter" do
      begin
        Asciidoctor::Converter::DefaultRegistry.register(CustomConverterForRegistration, "test-backend-1")
        Asciidoctor::Converter::DefaultRegistry.converter_for("test-backend-1").should eq(CustomConverterForRegistration)
      ensure
        Asciidoctor::Converter::DefaultRegistry.unregister_all
      end
    end

    it "should register a converter for multiple backends" do
      begin
        Asciidoctor::Converter::DefaultRegistry.register(CustomConverterForRegistration, "test-backend-2a", "test-backend-2b")
        Asciidoctor::Converter::DefaultRegistry.converter_for("test-backend-2a").should eq(CustomConverterForRegistration)
        Asciidoctor::Converter::DefaultRegistry.converter_for("test-backend-2b").should eq(CustomConverterForRegistration)
      ensure
        Asciidoctor::Converter::DefaultRegistry.unregister_all
      end
    end

    it "should unregister all custom converters but keep built-in ones" do
      begin
        Asciidoctor::Converter::DefaultRegistry.register(CustomConverterForRegistration, "test-backend-3")
        Asciidoctor::Converter::DefaultRegistry.converter_for("test-backend-3").should eq(CustomConverterForRegistration)
        Asciidoctor::Converter::DefaultRegistry.unregister_all
        Asciidoctor::Converter::DefaultRegistry.converter_for("test-backend-3").should be_nil
        Asciidoctor::Converter::DefaultRegistry.converter_for("html5").should eq(Asciidoctor::Converter::Html5Converter)
      ensure
        Asciidoctor::Converter::DefaultRegistry.unregister_all
      end
    end

    it "should list all registered converters" do
      converters = Asciidoctor::Converter::DefaultRegistry.converters
      converters.should be_a(Hash(String, Asciidoctor::Converter::Base.class))
      converters.has_key?("html5").should be_true
    end
  end

  describe "CustomFactory" do
    it "should create a custom factory with seed registry" do
      factory = Asciidoctor::Converter::CustomFactory.new({"custom-be" => CustomConverterForRegistration})
      factory.converter_for("custom-be").should eq(CustomConverterForRegistration)
    end

    it "should return nil for unregistered backend in custom factory" do
      factory = Asciidoctor::Converter::CustomFactory.new
      factory.converter_for("nonexistent").should be_nil
    end

    it "should create an instance from custom factory" do
      factory = Asciidoctor::Converter::CustomFactory.new({"custom-be" => CustomConverterForRegistration})
      converter = factory.create("custom-be")
      converter.should_not be_nil
      converter.should be_a(CustomConverterForRegistration)
    end

    it "should register a converter in custom factory" do
      factory = Asciidoctor::Converter::CustomFactory.new
      factory.register(CustomConverterForRegistration2, "custom-be-2")
      factory.converter_for("custom-be-2").should eq(CustomConverterForRegistration2)
    end

    it "should unregister all converters in custom factory" do
      factory = Asciidoctor::Converter::CustomFactory.new({"custom-be" => CustomConverterForRegistration})
      factory.unregister_all
      factory.converter_for("custom-be").should be_nil
    end

    it "should list all converters in custom factory" do
      factory = Asciidoctor::Converter::CustomFactory.new({"be1" => CustomConverterForRegistration, "be2" => CustomConverterForRegistration2})
      converters = factory.converters
      converters.size.should eq(2)
      converters.has_key?("be1").should be_true
      converters.has_key?("be2").should be_true
    end
  end

  describe "CompositeConverter" do
    it "should delegate to first converter that handles the transform" do
      html5 = Asciidoctor::Converter::Html5Converter.new("html5")
      composite = Asciidoctor::Converter::CompositeConverter.new("html5", [html5] of Asciidoctor::Converter::Base)
      composite.converters.size.should eq(1)
      composite.converters.first.should be(html5)
    end

    it "should cache converter for transform" do
      html5 = Asciidoctor::Converter::Html5Converter.new("html5")
      composite = Asciidoctor::Converter::CompositeConverter.new("html5", [html5] of Asciidoctor::Converter::Base)
      converter1 = composite.converter_for("document")
      converter2 = composite.converter_for("document")
      converter1.should be(converter2)
    end

    it "should raise if no converter handles the transform" do
      template = Asciidoctor::Converter::TemplateConverter.new("html5")
      composite = Asciidoctor::Converter::CompositeConverter.new("html5", [template] of Asciidoctor::Converter::Base)
      expect_raises(Exception, "Could not find a converter") do
        composite.converter_for("document")
      end
    end

    it "should use backend traits from source converter if provided" do
      html5 = Asciidoctor::Converter::Html5Converter.new("html5")
      composite = Asciidoctor::Converter::CompositeConverter.new("html5", [html5] of Asciidoctor::Converter::Base, html5)
      composite.backend_traits.basebackend.should eq("html")
      composite.backend_traits.filetype.should eq("html")
    end
  end

  describe "TemplateConverter" do
    it "should initialize with empty templates" do
      converter = Asciidoctor::Converter::TemplateConverter.new("html5")
      converter.templates.should be_empty
    end

    it "should register a template" do
      converter = Asciidoctor::Converter::TemplateConverter.new("html5")
      converter.register("paragraph", "/tmp/paragraph.html")
      converter.handles?("paragraph").should be_true
      converter.handles?("section").should be_false
    end

    it "should raise if no template handles the transform" do
      converter = Asciidoctor::Converter::TemplateConverter.new("html5")
      doc = Asciidoctor::Document.new
      expect_raises(Exception, "Could not find a custom template") do
        converter.convert(doc, "document")
      end
    end
  end

  describe "Document integration" do
    it "should use html5 converter by default" do
      doc = document_from_string("content")
      doc.converter.should be_a(Asciidoctor::Converter::Html5Converter)
    end

    it "should use docbook5 converter for docbook backend" do
      doc = document_from_string("content", {"backend" => "docbook5"})
      doc.converter.should be_a(Asciidoctor::Converter::DocBook5Converter)
    end

    it "should use manpage converter for manpage backend" do
      doc = document_from_string("content", {"backend" => "manpage"})
      doc.converter.should be_a(Asciidoctor::Converter::ManPageConverter)
    end

    it "should convert a simple document with html5 backend" do
      output = convert_string_to_embedded("Hello, World!")
      output.should contain("Hello, World!")
    end

    it "should convert a simple document with docbook backend" do
      output = convert_string_to_embedded("Hello, World!", {"backend" => "docbook"})
      output.should contain("Hello, World!")
    end
  end

  pending "should set Haml format to html5 for html5 backend" do
  end

  pending "should set Haml format to xhtml for docbook backend" do
  end

  pending "should configure Slim to resolve includes in specified template dirs" do
  end

  pending "should coerce template_dirs option to an Array" do
  end

  pending "should set Slim format to html for html5 backend" do
  end

  pending "should set Slim format to nil for docbook backend" do
  end

  pending "should set safe mode of Slim AsciiDoc engine to match document safe mode when Slim >= 3" do
  end

  pending "should support custom template engine options for known engine" do
  end

  pending "should support custom template engine options" do
  end

  pending "should load Haml templates for default backend" do
  end

  pending "should load ERB templates using ERBTemplate if eruby is not set" do
  end

  pending "should load ERB templates using ErubiTemplate if eruby is set to erubi" do
  end

  pending "should load Slim templates for default backend" do
  end

  pending "should load Slim templates for docbook5 backend" do
  end

  pending "should use Slim templates in place of built-in templates" do
  end

  pending "should be able to override the outline using a custom template" do
  end
end
