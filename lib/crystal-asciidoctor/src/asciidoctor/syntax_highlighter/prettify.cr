module Asciidoctor
  # Client-side syntax highlighter adapter for Google Code Prettify.
  #
  # This adapter inserts the necessary CSS and JavaScript into the output document
  # to enable client-side syntax highlighting using Google Code Prettify.
  #
  # Ported from Ruby Asciidoctor lib/asciidoctor/syntax_highlighter/prettify.rb
  class PrettifyAdapter < SyntaxHighlighterBase
    register_for "prettify"

    CDN_BASE_URL      = "https://cdnjs.cloudflare.com/ajax/libs/prettify"
    PRETTIFY_VERSION  = "r298"

    def initialize(name : String = "prettify", backend : String = "html5")
      super(name, backend)
      @name = "prettify"
      @pre_class = "prettyprint"
    end

    def docinfo(location : Symbol, doc : Document, opts : Hash(Symbol, String) = {} of Symbol => String) : String
      base_url = doc.attr("prettifydir") || "#{opts[:cdn_base_url]? || CDN_BASE_URL}/#{PRETTIFY_VERSION}"
      slash = opts[:self_closing_tag_slash]? || ""

      if location == :head
        theme = doc.attr("prettify-theme") || "prettify"
        %(<link rel="stylesheet" href="#{base_url}/#{theme}.min.css"#{slash}>)
      else # :footer
        %(<script src="#{base_url}/prettify.min.js"></script>
<script>prettyPrint()</script>)
      end
    end

    def docinfo?(location : Symbol) : Bool
      true
    end

    def format(node : AbstractNode, lang : String | Nil, opts : Hash(Symbol, String) = {} of Symbol => String) : String
      nohighlight = node.option?("nohighlight")
      pre_class = if nohighlight
                    "prettyprint"
                  else
                    lang ? "prettyprint language-#{lang}" : "prettyprint"
                  end
      content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
      %(<pre class="#{pre_class}"><code class="prettyprint"#{lang ? %( data-lang="#{lang}") : ""}>#{content}</code></pre>)
    end
  end
end
