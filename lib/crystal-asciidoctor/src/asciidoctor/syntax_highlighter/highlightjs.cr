module Asciidoctor
  # Client-side syntax highlighter adapter for highlight.js.
  #
  # This adapter inserts the necessary CSS and JavaScript into the output document
  # to enable client-side syntax highlighting using highlight.js.
  #
  # Ported from Ruby Asciidoctor lib/asciidoctor/syntax_highlighter/highlightjs.rb
  class HighlightJsAdapter < SyntaxHighlighterBase
    register_for "highlightjs", "highlight.js"

    CDN_BASE_URL         = "https://cdnjs.cloudflare.com/ajax/libs"
    HIGHLIGHT_JS_VERSION = "9.18.3"

    def initialize(name : String = "highlightjs", backend : String = "html5")
      super(name, backend)
      @name = "highlightjs"
      @pre_class = "highlightjs"
    end

    def docinfo(location : Symbol, doc : Document, opts : Hash(Symbol, String) = {} of Symbol => String) : String
      base_url = doc.attr("highlightjsdir") || "#{opts[:cdn_base_url]? || CDN_BASE_URL}/highlight.js/#{HIGHLIGHT_JS_VERSION}"
      slash = opts[:self_closing_tag_slash]? || ""

      if location == :head
        theme = doc.attr("highlightjs-theme") || "github"
        %(<link rel="stylesheet" href="#{base_url}/styles/#{theme}.min.css"#{slash}>)
      else # :footer
        languages = if doc.attr?("highlightjs-languages")
                      (doc.attr("highlightjs-languages") || "").split(",").map do |lang|
                        %(<script src="#{base_url}/languages/#{lang.strip}.min.js"></script>\n)
                      end.join
                    else
                      ""
                    end
        %(<script src="#{base_url}/highlight.min.js"></script>
#{languages}<script>
if (!hljs.initHighlighting.called) {
  hljs.initHighlighting.called = true
  ;[].slice.call(document.querySelectorAll('pre.highlight > code[data-lang]')).forEach(function (el) { hljs.highlightBlock(el) })
}
</script>)
      end
    end

    def docinfo?(location : Symbol) : Bool
      true
    end

    def format(node : AbstractNode, lang : String | Nil, opts : Hash(Symbol, String) = {} of Symbol => String) : String
      nohighlight = node.option?("nohighlight")
      class_attr_val = if nohighlight
                         @pre_class
                       else
                         "#{@pre_class} highlight"
                       end
      code_class = "language-#{lang || "none"} hljs"
      content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
      %(<pre class="#{class_attr_val}"><code class="#{code_class}"#{lang ? %( data-lang="#{lang}") : ""}>#{content}</code></pre>)
    end
  end
end
