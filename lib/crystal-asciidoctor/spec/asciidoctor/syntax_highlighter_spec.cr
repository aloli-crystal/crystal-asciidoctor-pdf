require "../spec_helper"

# Custom syntax highlighter for testing registration
class TestSyntaxHighlighterA < Asciidoctor::SyntaxHighlighterBase
  def format(node : Asciidoctor::AbstractNode, lang : String | Nil, opts : Hash(Symbol, String) = {} of Symbol => String) : String
    %(<pre class="highlight"><code class="language-#{lang}" data-lang="#{lang}">#{node.is_a?(Asciidoctor::AbstractBlock) ? (node.content || "") : ""}</code></pre>)
  end

  def highlight? : Bool
    false
  end
end

class TestSyntaxHighlighterB < Asciidoctor::SyntaxHighlighterBase
  def format(node : Asciidoctor::AbstractNode, lang : String | Nil, opts : Hash(Symbol, String) = {} of Symbol => String) : String
    %(<pre class="highlight"><code>#{node.is_a?(Asciidoctor::AbstractBlock) ? (node.content || "") : ""}</code></pre>)
  end

  def highlight? : Bool
    false
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

describe Asciidoctor::SyntaxHighlighter do
  describe "DefaultRegistry" do
    it "should register and retrieve a syntax highlighter by name" do
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.register(TestSyntaxHighlighterA, "test-hl-a")
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.for("test-hl-a").should eq(TestSyntaxHighlighterA)
    end

    it "should return nil for unregistered syntax highlighter" do
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.for("nonexistent-hl").should be_nil
    end

    it "should create an instance of a registered syntax highlighter" do
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.register(TestSyntaxHighlighterA, "test-hl-create")
      instance = Asciidoctor::SyntaxHighlighter::DefaultRegistry.create("test-hl-create")
      instance.should_not be_nil
      instance.should be_a(TestSyntaxHighlighterA)
      instance.not_nil!.name.should eq("test-hl-create")
    end

    it "should return nil when creating an instance for unregistered name" do
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.create("nonexistent-hl-create").should be_nil
    end

    it "should register a syntax highlighter for multiple names" do
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.register(TestSyntaxHighlighterB, "test-hl-b1", "test-hl-b2")
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.for("test-hl-b1").should eq(TestSyntaxHighlighterB)
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.for("test-hl-b2").should eq(TestSyntaxHighlighterB)
    end
  end

  describe "CustomFactory" do
    it "should create a custom factory with seed registry" do
      factory = Asciidoctor::SyntaxHighlighter::CustomFactory.new({"custom-hl" => TestSyntaxHighlighterA})
      factory.for("custom-hl").should eq(TestSyntaxHighlighterA)
    end

    it "should return nil for unregistered name in custom factory" do
      factory = Asciidoctor::SyntaxHighlighter::CustomFactory.new
      factory.for("nonexistent").should be_nil
    end

    it "should create an instance from custom factory" do
      factory = Asciidoctor::SyntaxHighlighter::CustomFactory.new({"custom-hl" => TestSyntaxHighlighterA})
      instance = factory.create("custom-hl")
      instance.should_not be_nil
      instance.should be_a(TestSyntaxHighlighterA)
    end

    it "should register a syntax highlighter in custom factory" do
      factory = Asciidoctor::SyntaxHighlighter::CustomFactory.new
      factory.register(TestSyntaxHighlighterB, "custom-hl-b")
      factory.for("custom-hl-b").should eq(TestSyntaxHighlighterB)
    end
  end

  describe "SyntaxHighlighterBase" do
    it "should store name" do
      hl = TestSyntaxHighlighterA.new("test-hl")
      hl.name.should eq("test-hl")
    end

    it "should have pre_class defaulting to name" do
      hl = TestSyntaxHighlighterA.new("test-hl")
      hl.pre_class.should eq("test-hl")
    end

    it "should not highlight by default" do
      hl = TestSyntaxHighlighterA.new("test-hl")
      hl.highlight?.should be_false
    end

    it "should not have docinfo by default" do
      hl = TestSyntaxHighlighterA.new("test-hl")
      hl.docinfo?(:head).should be_false
      hl.docinfo?(:footer).should be_false
    end

    it "should return empty string for docinfo by default" do
      hl = TestSyntaxHighlighterA.new("test-hl")
      doc = Asciidoctor::Document.new
      hl.docinfo(:head, doc).should eq("")
      hl.docinfo(:footer, doc).should eq("")
    end
  end

  describe "HighlightJsAdapter" do
    it "should be registered for highlightjs and highlight.js" do
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.for("highlightjs").should eq(Asciidoctor::HighlightJsAdapter)
      Asciidoctor::SyntaxHighlighter::DefaultRegistry.for("highlight.js").should eq(Asciidoctor::HighlightJsAdapter)
    end

    it "should have pre_class set to highlightjs" do
      hl = Asciidoctor::HighlightJsAdapter.new
      hl.pre_class.should eq("highlightjs")
    end

    it "should have docinfo for head and footer" do
      hl = Asciidoctor::HighlightJsAdapter.new
      hl.docinfo?(:head).should be_true
      hl.docinfo?(:footer).should be_true
    end

    it "should generate CSS link in head docinfo" do
      hl = Asciidoctor::HighlightJsAdapter.new
      doc = Asciidoctor::Document.new
      head = hl.docinfo(:head, doc)
      head.should contain("link")
      head.should contain("highlight.js")
      head.should contain("github.min.css")
    end

    it "should generate JS script in footer docinfo" do
      hl = Asciidoctor::HighlightJsAdapter.new
      doc = Asciidoctor::Document.new
      footer = hl.docinfo(:footer, doc)
      footer.should contain("highlight.min.js")
      footer.should contain("hljs.highlightBlock")
    end

    it "should use custom theme from document attribute" do
      hl = Asciidoctor::HighlightJsAdapter.new
      doc = Asciidoctor::Document.new
      doc.attributes["highlightjs-theme"] = "monokai"
      head = hl.docinfo(:head, doc)
      head.should contain("monokai.min.css")
    end

    it "should load additional languages from highlightjs-languages attribute" do
      hl = Asciidoctor::HighlightJsAdapter.new
      doc = Asciidoctor::Document.new
      doc.attributes["highlightjs-languages"] = "yaml, scilab"
      footer = hl.docinfo(:footer, doc)
      footer.should contain("languages/yaml.min.js")
      footer.should contain("languages/scilab.min.js")
    end

    it "should not highlight (client-side)" do
      hl = Asciidoctor::HighlightJsAdapter.new
      hl.highlight?.should be_false
    end
  end

  describe "Document integration" do
    it "should set syntax_highlighter on document when source-highlighter is highlight.js and basebackend is html" do
      input = ":source-highlighter: highlight.js\n\n[source,ruby]\n----\nputs \"Hello\"\n----"
      doc = document_from_string(input, {"safe" => "safe"})
      doc.basebackend?("html").should be_true
      doc.syntax_highlighter.should_not be_nil
      doc.syntax_highlighter.should be_a(Asciidoctor::HighlightJsAdapter)
    end

    it "should not set syntax_highlighter on document when source-highlighter is not set" do
      input = "[source,ruby]\n----\nputs \"Hello\"\n----"
      doc = document_from_string(input, {"safe" => "safe"})
      doc.syntax_highlighter.should be_nil
    end

    it "should not set syntax_highlighter on document when source-highlighter is not recognized" do
      input = ":source-highlighter: unknown\n\n[source,ruby]\n----\nputs \"Hello\"\n----"
      doc = document_from_string(input, {"safe" => "safe"})
      doc.syntax_highlighter.should be_nil
    end

    it "should not set syntax_highlighter on document when basebackend is not html" do
      input = ":source-highlighter: highlight.js\n\n[source,ruby]\n----\nputs \"Hello\"\n----"
      doc = document_from_string(input, {"safe" => "safe", "backend" => "docbook"})
      doc.basebackend?("html").should be_false
      doc.syntax_highlighter.should be_nil
    end
  end

  describe "Conversion output" do
    it "should output source block with highlight class" do
      input = "[source]\n----\nputs \"Hello, World!\"\n----"
      output = convert_string_to_embedded(input, {"safe" => "safe"})
      output.should contain("<pre class=\"highlight")
      output.should contain("<code>")
    end

    it "should set language on output of source block when source-highlighter is not set" do
      input = "[source,ruby]\n----\nputs \"Hello, World!\"\n----"
      output = convert_string_to_embedded(input, {"safe" => "safe"})
      output.should contain("highlight")
      output.should contain("data-lang=\"ruby\"")
    end

    it "should set language on output of source block when source-highlighter is not recognized" do
      input = ":source-highlighter: unknown\n\n[source,ruby]\n----\nputs \"Hello, World!\"\n----"
      output = convert_string_to_embedded(input, {"safe" => "safe"})
      output.should contain("highlight")
      output.should contain("data-lang=\"ruby\"")
    end

    it "should add data-lang on code tag when source-highlighter is highlight.js" do
      input = ":source-highlighter: highlight.js\n\n[source,ruby]\n----\nputs \"Hello, World!\"\n----"
      output = convert_string_to_embedded(input, {"safe" => "safe"})
      output.should contain("highlightjs")
      output.should contain("data-lang=\"ruby\"")
    end

    it "should include remote highlight.js assets when source-highlighter is highlight.js" do
      input = ":source-highlighter: highlight.js\n\n[source,html]\n----\n<p>Highlight me!</p>\n----"
      output = convert_string(input, {"safe" => "safe", "standalone" => "true"})
      output.should contain("highlight.min.js")
      output.should contain("hljs")
    end

    it "should add language-none class when source-highlighter is highlight.js and language is not set" do
      input = ":source-highlighter: highlight.js\n\n[source]\n----\n[numbers]\none\ntwo\nthree\n----"
      output = convert_string_to_embedded(input, {"safe" => "safe"})
      output.should contain("language-none")
    end

    it "should set starting line number in DocBook output if linenums option is enabled and start attribute is set" do
      input = "[source%linenums,java,start=3]\n----\npublic class HelloWorld {\n  public static void main(String[] args) {\n    out.println(\"Hello, World!\");\n  }\n}\n----"
      output = convert_string_to_embedded(input, {"backend" => "docbook", "safe" => "safe"})
      output.should contain("startinglinenumber=\"3\"")
    end

    it "should rename document attribute named language to source-language when compat-mode is enabled" do
      input = ":language: ruby\n\n{source-language}"
      output1 = convert_string_to_embedded(input, {"attributes" => "compat-mode="})
      output1.strip.should contain("ruby")
      output2 = convert_string_to_embedded(input)
      output2.should contain("{source-language}")
    end
  end

  describe "Prettify" do
    it "should add prettyprint class when source-highlighter is prettify" do
      input = "[source,ruby]\n----\nputs \"foo\"\n----"
      output = convert_string_to_embedded(input, {"attributes" => "source-highlighter=prettify"})
      output.should contain("prettyprint")
      output.should contain("data-lang=\"ruby\"")
    end
  end

  describe "CodeRay" do
    pending "should highlight source if source-highlighter attribute is set" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should not fail if source language is invalid" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should number lines if third positional attribute is set" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should number lines if linenums option is set on source block" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should number lines of source block if source-linenums-option document attribute is set" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should highlight lines specified in highlight attribute if linenums is set and source-highlighter is coderay" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should replace callout marks but not highlight them if source-highlighter attribute is coderay" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should support autonumbered callout marks if source-highlighter attribute is coderay" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should restore callout marks to correct lines if source highlighter is coderay and table line numbering is enabled" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should restore isolated callout mark on last line of source when source highlighter is coderay" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should preserve space before callout on final line" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should preserve passthrough placeholders when highlighting source using coderay" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should link to CodeRay stylesheet if source-highlighter is coderay and linkcss is set" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should highlight source inline if source-highlighter attribute is coderay and coderay-css is style" do
      # Porting note: Depends on CodeRay gem
    end

    pending "should read stylesheet" do
      # Porting note: Depends on CodeRay gem
    end
  end

  describe "HTML Pipeline" do
    pending "should set lang attribute on pre when source-highlighter is html-pipeline" do
      # Porting note: Depends on HTML-Pipeline gem
    end
  end

  describe "Rouge" do
    pending "should syntax highlight source if source-highlighter attribute is set" do
      # Porting note: Depends on Rouge gem
    end

    pending "should highlight source using a mixed lexer (HTML + JavaScript)" do
      # Porting note: Depends on Rouge gem
    end

    pending "should enable start_inline for PHP by default" do
      # Porting note: Depends on Rouge gem
    end

    pending "should not enable start_inline for PHP if disabled using cgi-style option on language" do
      # Porting note: Depends on Rouge gem
    end

    pending "should not enable start_inline for PHP if mixed option is set" do
      # Porting note: Depends on Rouge gem
    end

    pending "should preserve cgi-style options on language when setting start_inline option for PHP" do
      # Porting note: Depends on Rouge gem
    end

    pending "should not crash if source-highlighter attribute is set and source block does not define a language" do
      # Porting note: Depends on Rouge gem
    end

    pending "should default to plain text lexer if lexer cannot be resolved for language" do
      # Porting note: Depends on Rouge gem
    end

    pending "should honor cgi-style options on language" do
      # Porting note: Depends on Rouge gem
    end

    pending "should number lines using table layout if linenums option is enabled and linenums mode is not set" do
      # Porting note: Depends on Rouge gem
    end

    pending "should number lines using inline element if linenums option is enabled and linenums mode is inline" do
      # Porting note: Depends on Rouge gem
    end

    pending "should set starting line number in HTML output if linenums option is enabled and start attribute is set" do
      # Porting note: Depends on Rouge gem
    end

    pending "should restore callout marks to correct lines" do
      # Porting note: Depends on Rouge gem
    end
  end
end
