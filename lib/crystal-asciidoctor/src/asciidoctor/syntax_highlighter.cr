module Asciidoctor
  # A pluggable adapter for integrating a syntax (aka code) highlighter into AsciiDoc processing.
  #
  # There are two types of syntax highlighter adapters:
  # 1. Server-side: performs syntax highlighting during the convert phase (highlight? returns true)
  # 2. Client-side: assumes syntax highlighting is performed on the client (docinfo? returns true)
  #
  # Ported from Ruby Asciidoctor lib/asciidoctor/syntax_highlighter.rb
  module SyntaxHighlighter
    # The default (global) registry of syntax highlighters.
    module DefaultRegistry
      @@registry = {} of String => SyntaxHighlighterBase.class

      # Resolve the name to a syntax highlighter instance, if found in the registry.
      def self.create(name : String, backend : String = "html5") : SyntaxHighlighterBase | Nil
        if (syntax_hl_class = self.for(name))
          syntax_hl_class.new(name, backend)
        else
          nil
        end
      end

      # Retrieve the syntax highlighter class registered for the specified name.
      def self.for(name : String) : SyntaxHighlighterBase.class | Nil
        @@registry[name]?
      end

      # Register a syntax highlighter for one or more names.
      def self.register(syntax_highlighter : SyntaxHighlighterBase.class, *names : String) : Nil
        names.each { |name| @@registry[name] = syntax_highlighter }
      end

      # Get all registered syntax highlighters.
      def self.registry : Hash(String, SyntaxHighlighterBase.class)
        @@registry
      end
    end

    # A custom factory that stores syntax highlighters in a local registry.
    class CustomFactory
      @registry : Hash(String, SyntaxHighlighterBase.class)

      def initialize(seed_registry = nil)
        if sr = seed_registry
          @registry = {} of String => SyntaxHighlighterBase.class
          sr.each { |k, v| @registry[k] = v }
        else
          @registry = {} of String => SyntaxHighlighterBase.class
        end
      end

      # Resolve the name to a syntax highlighter instance, if found in the registry.
      def create(name : String, backend : String = "html5") : SyntaxHighlighterBase | Nil
        if (syntax_hl_class = self.for(name))
          syntax_hl_class.new(name, backend)
        else
          nil
        end
      end

      # Retrieve the syntax highlighter class registered for the specified name.
      def for(name : String) : SyntaxHighlighterBase.class | Nil
        @registry[name]?
      end

      # Register a syntax highlighter for one or more names.
      def register(syntax_highlighter : SyntaxHighlighterBase.class, *names : String) : Nil
        names.each { |name| @registry[name] = syntax_highlighter }
      end
    end
  end

  # Abstract base class for syntax highlighter implementations.
  abstract class SyntaxHighlighterBase
    # The String name of this syntax highlighter.
    getter name : String

    # The CSS class prefix for the pre element.
    property pre_class : String

    def initialize(@name : String, backend : String = "html5")
      @pre_class = @name
    end

    # Generates docinfo markup for this syntax highlighter to insert at the specified
    # location in the output document.
    def docinfo(location : Symbol, doc : Document, opts : Hash(Symbol, String) = {} of Symbol => String) : String
      ""
    end

    # Indicates whether this syntax highlighter has docinfo (i.e., markup) to insert
    # into the output document at the specified location.
    def docinfo?(location : Symbol) : Bool
      false
    end

    # Format the highlighted source for inclusion in an HTML document.
    def format(node : AbstractNode, lang : String | Nil, opts : Hash(Symbol, String) = {} of Symbol => String) : String
      class_attr_val = "#{@pre_class} highlight"
      content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
      %(<pre class="#{class_attr_val}"><code#{lang ? %( data-lang="#{lang}") : ""}>#{content}</code></pre>)
    end

    # Highlights the specified source when this source block is being converted.
    def highlight(node : AbstractNode, source : String, lang : String, opts : Hash(Symbol, String) = {} of Symbol => String) : String
      source
    end

    # Indicates whether highlighting is handled by this syntax highlighter or by the client.
    def highlight? : Bool
      false
    end

    # Register this syntax highlighter class for the given names in the default registry.
    macro register_for(*names)
      {% for name in names %}
        Asciidoctor::SyntaxHighlighter::DefaultRegistry.register(self, {{name}}.to_s)
      {% end %}
    end

    # Writes the stylesheet to support the highlighted source(s) to disk.
    def write_stylesheet(doc : Document, to_dir : String) : Nil
    end

    # Indicates whether this syntax highlighter wants to write a stylesheet to disk.
    def write_stylesheet?(doc : Document) : Bool
      false
    end
  end
end
