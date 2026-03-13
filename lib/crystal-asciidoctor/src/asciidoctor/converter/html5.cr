module Asciidoctor
  module Converter
    class Html5Converter < Base
      register_for "html5"

      FONT_AWESOME_VERSION = "4.7.0"
      MATHJAX_VERSION      = "2.7.9"

      DEFAULT_STYLESHEET_KEYS = Set{"", "DEFAULT", "asciidoctor.css"}

      QUOTE_TAGS = {
        :monospaced  => {"<code>", "</code>", true},
        :emphasis    => {"<em>", "</em>", true},
        :strong      => {"<strong>", "</strong>", true},
        :double      => {"&#8220;", "&#8221;", false},
        :single      => {"&#8216;", "&#8217;", false},
        :mark        => {"<mark>", "</mark>", true},
        :superscript => {"<sup>", "</sup>", true},
        :subscript   => {"<sub>", "</sub>", true},
        :asciimath   => {"\\$", "\\$", false},
        :latexmath   => {"\\(", "\\)", false},
      }

      DEFAULT_QUOTE_TAG = {"", "", false}

      DropAnchorRx      = /<(?:a\b[^>]*|\/a)>/
      LeadingAnchorsRx  = /^(?:<a id="[^"]+"><\/a>)+/
      StemBreakRx       = / *\\\n(?:\\?\n)*|\n\n+/
      SvgPreambleRx     = /\A.*?(?=<svg[\s>])/m
      SvgStartTagRx     = /\A<svg(?:\s[^>]*)?>/
      DimensionAttrRx   = /\s(?:width|height|style)=(["']).*?\1/

      @xml_mode : Bool
      @void_element_slash : String

      def initialize(backend : String = "html5", htmlsyntax : String = "html")
        super(backend)
        if htmlsyntax == "xml"
          @xml_mode = true
          @void_element_slash = "/"
        else
          @xml_mode = false
          @void_element_slash = ""
        end
        @backend_traits = BackendTraits.new(
          basebackend: "html",
          filetype: "html",
          htmlsyntax: htmlsyntax,
          outfilesuffix: ".html"
        )
      end

      def convert(node : AbstractNode, transform : String? = nil) : String
        transform ||= node.node_name
        # Si le document n'est pas standalone, utiliser convert_embedded
        if transform == "document" && node.is_a?(Document) && !node.attr?("standalone")
          transform = "embedded"
        end
        output = dispatch(node, transform)
        # Invoke postprocessors if this is a document conversion
        if (transform == "document" || transform == "embedded") && node.is_a?(Document)
          if (ext = node.extensions) && ext.postprocessors?
            ext.postprocessors.each do |processor_ext|
              if (processor = processor_ext.instance) && processor.is_a?(Extensions::Postprocessor)
                output = processor.process(node, output)
              end
            end
          end
        end
        output
      end

      def dispatch(node : AbstractNode, transform : String) : String
        case transform
        when "admonition"       then convert_admonition(node)
        when "audio"            then convert_audio(node)
        when "colist"           then convert_colist(node)
        when "dlist"            then convert_dlist(node)
        when "document"         then convert_document(node)
        when "embedded"         then convert_embedded(node)
        when "example"          then convert_example(node)
        when "floating_title"   then convert_floating_title(node)
        when "image"            then convert_image(node)
        when "inline_anchor"    then convert_inline_anchor(node)
        when "inline_break"     then convert_inline_break(node)
        when "inline_button"    then convert_inline_button(node)
        when "inline_callout"   then convert_inline_callout(node)
        when "inline_footnote"  then convert_inline_footnote(node)
        when "inline_image"     then convert_inline_image(node)
        when "inline_indexterm" then convert_inline_indexterm(node)
        when "inline_kbd"       then convert_inline_kbd(node)
        when "inline_menu"      then convert_inline_menu(node)
        when "inline_quoted"    then convert_inline_quoted(node)
        when "listing"          then convert_listing(node)
        when "literal"          then convert_literal(node)
        when "olist"            then convert_olist(node)
        when "open"             then convert_open(node)
        when "outline"          then convert_outline(node) || ""
        when "page_break"       then convert_page_break(node)
        when "paragraph"        then convert_paragraph(node)
        when "pass"             then content_only(node)
        when "preamble"         then convert_preamble(node)
        when "quote"            then convert_quote(node)
        when "section"          then convert_section(node)
        when "sidebar"          then convert_sidebar(node)
        when "stem"             then convert_stem(node)
        when "table"            then convert_table(node)
        when "thematic_break"   then convert_thematic_break(node)
        when "toc"              then convert_toc(node)
        when "ulist"            then convert_ulist(node)
        when "verse"            then convert_verse(node)
        when "video"            then convert_video(node)
        else                         ""
        end
      end

      def convert_admonition(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        name = node.attr("name") || ""
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.title}</div>\n) : ""
        if node.document.attr?("icons")
          if node.document.attr?("icons", "font") && !node.attr?("icon")
            label = %(<i class="fa icon-#{name}" title="#{node.attr("textlabel") || ""}"></i>)
          else
            label = %(<img src="#{node.icon_uri(name)}" alt="#{node.attr("textlabel") || ""}"#{slash}>)
          end
        else
          label = %(<div class="title">#{node.attr("textlabel") || ""}</div>)
        end
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        role = node.role
        %(<div#{id_attr} class="admonitionblock #{name}#{role ? " #{role}" : ""}">
<table>
<tr>
<td class="icon">
#{label}
</td>
<td class="content">
#{title_el}#{content}
</td>
</tr>
</table>
</div>)
      end

      def convert_audio(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        classes = ["audioblock"]
        classes << node.role.not_nil! if node.role
        class_attr = %( class="#{classes.join(" ")}")
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.title}</div>\n) : ""
        raw_target = node.attr("target") || ""
        target = raw_target.starts_with?("http://") || raw_target.starts_with?("https://") ? raw_target : node.media_uri(raw_target)
        start_t = node.attr("start")
        end_t = node.attr("end")
        time_anchor = (start_t || end_t) ? "#t=#{start_t || ""}#{end_t ? ",#{end_t}" : ""}" : ""
        %(<div#{id_attr}#{class_attr}>
#{title_el}<div class="content">
<audio src="#{target}#{time_anchor}"#{node.option?("autoplay") ? append_boolean_attribute("autoplay") : ""}#{node.option?("nocontrols") ? "" : append_boolean_attribute("controls")}#{node.option?("loop") ? append_boolean_attribute("loop") : ""}>
Your browser does not support the audio tag.
</audio>
</div>
</div>)
      end

      def convert_colist(node : AbstractNode) : String
        result = [] of String
        id_attr = node.id ? %( id="#{node.id}") : ""
        classes = ["colist"]
        classes << (node.attr("style") || "arabic")
        classes << node.role.not_nil! if node.role
        class_attr = %( class="#{classes.join(" ")}")
        result << %(<div#{id_attr}#{class_attr}>)
        result << %(<div class="title">#{node.title}</div>) if node.is_a?(AbstractBlock) && node.title?

        if node.is_a?(List)
          if node.document.attr?("icons")
            result << "<table>"
            num = 0
            node.items.each do |item|
              num += 1
              if node.document.attr?("icons", "font")
                num_label = %(<i class="conum" data-value="#{num}"></i><b>#{num}</b>)
              else
                num_label = %(<img src="#{node.icon_uri("callouts/#{num}")}" alt="#{num}"#{slash}>)
              end
              item_text = item.is_a?(ListItem) ? (item.text || "") : ""
              item_content = item.is_a?(AbstractBlock) && item.blocks? ? "\n#{item.content}" : ""
              result << %(<tr>\n<td>#{num_label}</td>\n<td>#{item_text}#{item_content}</td>\n</tr>)
            end
            result << "</table>"
          else
            result << "<ol>"
            node.items.each do |item|
              item_text = item.is_a?(ListItem) ? (item.text || "") : ""
              item_content = item.is_a?(AbstractBlock) && item.blocks? ? "\n#{item.content}" : ""
              result << %(<li>\n<p>#{item_text}</p>#{item_content}\n</li>)
            end
            result << "</ol>"
          end
        end

        result << "</div>"
        result.join("\n")
      end

      def convert_dlist(node : AbstractNode) : String
        result = [] of String
        id_attr = node.id ? %( id="#{node.id}") : ""
        style = node.is_a?(AbstractBlock) ? node.style : nil
        role = node.role

        case style
        when "qanda"
          classes = ["qlist", "qanda"]
        when "horizontal"
          classes = ["hdlist"]
        else
          classes = ["dlist"]
          classes << style.not_nil! if style
        end
        classes << role.not_nil! if role
        class_attr = %( class="#{classes.join(" ")}")

        result << %(<div#{id_attr}#{class_attr}>)
        result << %(<div class="title">#{node.title}</div>) if node.is_a?(AbstractBlock) && node.title?

        if style == "qanda"
          result << "<ol>"
          if node.is_a?(List)
            items = node.items
            i = 0
            while i < items.size
              item = items[i]
              if item.is_a?(ListItem) && (item.marker == "::" || item.marker.nil?)
                result << "<li>"
                result << %(<p><em>#{item.text || ""}</em></p>)
                if i + 1 < items.size && items[i + 1].is_a?(ListItem) && items[i + 1].as(ListItem).marker == "desc"
                  desc_item = items[i + 1].as(ListItem)
                  result << "<p>#{desc_item.text.try(&.strip) || ""}</p>" unless (desc_item.text || "").strip.empty?
                  i += 2
                else
                  i += 1
                end
                result << "</li>"
                next
              end
              i += 1
            end
          end
          result << "</ol>"
        elsif style == "horizontal"
          # Horizontal dlist uses a table layout
          label_width = node.is_a?(AbstractBlock) ? node.attr("labelwidth") : nil
          item_width = node.is_a?(AbstractBlock) ? node.attr("itemwidth") : nil
          strong_option = node.is_a?(AbstractBlock) ? node.option?("strong") : false
          result << "<table>"
          if label_width || item_width
            result << "<colgroup>"
            lw = label_width ? "#{label_width}%" : "15%"
            iw = item_width ? "#{item_width}%" : "85%"
            result << %(<col style="width: #{lw};">) 
            result << %(<col style="width: #{iw};">)
            result << "</colgroup>"
          end
          result << "<tbody>"
          if node.is_a?(List)
            items = node.items
            i = 0
            while i < items.size
              item = items[i]
              if item.is_a?(ListItem) && (item.marker == "::" || item.marker.nil?)
                result << "<tr>"
                term_text = item.text || ""
                term_text = "<strong>#{term_text}</strong>" if strong_option
                result << %(<td class="hdlist1">#{term_text}</td>)
                result << %(<td class="hdlist2">)
                if i + 1 < items.size && items[i + 1].is_a?(ListItem) && items[i + 1].as(ListItem).marker == "desc"
                  desc_item = items[i + 1].as(ListItem)
                  result << "<p>#{desc_item.text || ""}</p>" unless (desc_item.text || "").empty?
                  result << (desc_item.content || "") if desc_item.blocks?
                  i += 2
                else
                  i += 1
                end
                result << "</td>"
                result << "</tr>"
                next
              end
              i += 1
            end
          end
          result << "</tbody>"
          result << "</table>"
        else
          result << "<dl>"
          if node.is_a?(List)
            items = node.items
            i = 0
            while i < items.size
              item = items[i]
              if item.is_a?(ListItem)
                marker = item.marker
                # A term has any dlist delimiter (::, :::, ::::, ;;) or nil; a description has marker == "desc"
                if marker != "desc"
                  # Term (dt)
                  result << %(<dt>#{item.text || ""}</dt>)
                  # Check if next item is a description (dd)
                  if i + 1 < items.size && items[i + 1].is_a?(ListItem) && items[i + 1].as(ListItem).marker == "desc"
                    desc_item = items[i + 1].as(ListItem)
                    result << "<dd>"
                    if desc_item.blocks?
                      result << "<p>#{desc_item.text || ""}</p>" unless (desc_item.text || "").empty?
                      result << (desc_item.content || "")
                    else
                      result << "<p>#{desc_item.text || ""}</p>" unless (desc_item.text || "").empty?
                    end
                    result << "</dd>"
                    i += 2
                    next
                  end
                end
              end
              i += 1
            end
          end
          result << "</dl>"
        end
        result << "</div>"
        result.join("\n")
      end

      def convert_document(node : AbstractNode) : String
        # Handle inline doctype: return only the content of the first block
        doctype_val = node.is_a?(Document) ? node.doctype : (node.attr("doctype") || "article")
        if doctype_val == "inline"
          if node.is_a?(Document) && !node.blocks.empty?
            first_block = node.blocks.first
            if first_block.is_a?(Block) && first_block.context == :paragraph
              return first_block.content.to_s
            end
          end
          return ""
        end
        slash = @void_element_slash.empty? ? "" : " #{@void_element_slash}"
        br = "<br#{slash}>"
        result = [] of String
        result << "<!DOCTYPE html>"
        lang = node.attr("lang", "en")
        nolang = node.attr?("nolang")
        lang_attr = nolang ? "" : %( lang="#{lang}")
        xml_ns = @xml_mode ? %( xmlns="http://www.w3.org/1999/xhtml") : ""
        result << %(<html#{xml_ns}#{lang_attr}>)
        encoding = node.attr("encoding", "UTF-8")
        result << %(<head>\n<meta charset="#{encoding}"#{slash}>\n<meta http-equiv="X-UA-Compatible" content="IE=edge"#{slash}>\n<meta name="viewport" content="width=device-width, initial-scale=1.0"#{slash}>)
        result << %(<meta name="generator" content="Asciidoctor (Crystal)"#{slash}>) unless node.attr?("reproducible")
        result << %(<meta name="description" content="#{node.attr("description")}"#{slash}>) if node.attr?("description")
        result << %(<meta name="keywords" content="#{node.attr("keywords")}"#{slash}>) if node.attr?("keywords")
        result << %(<meta name="author" content="#{node.attr("authors") || ""}"#{slash}>) if node.attr?("authors")

        doc_title = if node.is_a?(Document)
                      node.doctitle({:use_fallback => true}) || "Untitled"
                    else
                      node.attr("doctitle") || "Untitled"
                    end
        result << %(<title>#{doc_title}</title>)

        # Stylesheet
        linkcss = node.attr?("linkcss")
        stylesheet = node.attr("stylesheet")
        if stylesheet.nil? || DEFAULT_STYLESHEET_KEYS.includes?(stylesheet || "")
          if linkcss
            stylesdir = node.attr("stylesdir") || "."
            result << %(<link rel="stylesheet" href="#{stylesdir}/#{DEFAULT_STYLESHEET_NAME}"#{slash}>)
          else
            result << Stylesheets.instance.embed_primary_stylesheet
          end
        elsif stylesheet && !stylesheet.empty?
          if linkcss
            stylesdir = node.attr("stylesdir") || "."
            result << %(<link rel="stylesheet" href="#{stylesdir}/#{stylesheet}"#{slash}>)
          end
        end

        # Syntax highlighter head docinfo
        if node.is_a?(Document)
          if (syntax_hl = node.syntax_highlighter) && syntax_hl.docinfo?(:head)
            result << syntax_hl.docinfo(:head, node)
          end
        end

        result << "</head>"

        # Body
        id_attr = node.id ? %( id="#{node.id}") : ""
        doctype = node.is_a?(Document) ? node.doctype : (node.attr("doctype") || "article")
        body_classes = [doctype]
        body_classes << node.role.not_nil! if node.role
        result << %(<body#{id_attr} class="#{body_classes.join(" ")}">)

        # Header
        noheader = node.is_a?(Document) ? node.noheader : node.attr?("noheader")
        unless noheader
          result << %(<div id="header">)
          if node.is_a?(Document)
            if node.header?
              result << %(<h1>#{node.header.not_nil!.title}</h1>) unless node.notitle
            end
            # Generate TOC in header if toc-placement is auto (default)
            if node.sections? && node.attr?("toc") && node.attr?("toc-placement", "auto")
              toc_class = node.attr("toc-class", "toc")
              toc_title = node.attr("toc-title") || "Table of Contents"
              result << %(<div id="toc" class="#{toc_class}">\n<div id="toctitle">#{toc_title}</div>\n#{convert_outline(node) || ""}\n</div>)
            end
          end
          result << "</div>"
        end

        # Content
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        max_width_style = if node.is_a?(Document) && (mw = node.attr("max-width"))
          %( style="max-width: #{mw};")
        else
          ""
        end
        result << %(<div id="content"#{max_width_style}>\n#{content}\n</div>)

        # Footer
        nofooter = node.is_a?(Document) ? node.nofooter : node.attr?("nofooter")
        unless nofooter
          result << %(<div id="footer">\n<div id="footer-text">)
          result << %(#{node.attr("version-label") || ""} #{node.attr("revnumber") || ""}#{br}) if node.attr?("revnumber")
          result << %(#{node.attr("last-update-label") || ""} #{node.attr("docdatetime") || ""}) if node.attr?("last-update-label") && !node.attr?("reproducible")
          result << %(</div>\n</div>)
        end

        # Syntax highlighter footer docinfo
        if node.is_a?(Document)
          if (syntax_hl = node.syntax_highlighter) && syntax_hl.docinfo?(:footer)
            result << syntax_hl.docinfo(:footer, node)
          end
        end

        result << "</body>"
        result << "</html>"
        result.join("\n")
      end

      def convert_embedded(node : AbstractNode) : String
        result = [] of String
        if node.is_a?(Document)
          if node.doctype == "manpage"
            unless node.notitle
              id_attr = node.id ? %( id="#{node.id}") : ""
              result << %(<h1#{id_attr}>#{node.doctitle} Manual Page</h1>)
            end
          elsif node.header? && !node.notitle
            id_attr = node.id ? %( id="#{node.id}") : ""
            result << %(<h1#{id_attr}>#{node.header.not_nil!.title}</h1>)
          end
        end
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        result << content.to_s
        result.join("\n")
      end

      def convert_example(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        if node.option?("collapsible")
          class_attr = node.role ? %( class="#{node.role}") : ""
          summary = node.is_a?(AbstractBlock) && node.title? ? %(<summary class="title">#{node.title}</summary>) : %(<summary class="title">Details</summary>)
          open_attr = node.option?("open") ? " open" : ""
          %(<details#{id_attr}#{class_attr}#{open_attr}>\n#{summary}\n<div class="content">\n#{content}\n</div>\n</details>)
        else
          title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.captioned_title}</div>\n) : ""
          role = node.role
          %(<div#{id_attr} class="exampleblock#{role ? " #{role}" : ""}">\n#{title_el}<div class="content">\n#{content}\n</div>\n</div>)
        end
      end

      def convert_floating_title(node : AbstractNode) : String
        level = node.is_a?(Section) ? node.level : (node.is_a?(AbstractBlock) ? node.level : 1)
        tag_name = "h#{level + 1}"
        id_attr = node.id ? %( id="#{node.id}") : ""
        classes = [] of String
        classes << (node.is_a?(AbstractBlock) ? (node.style || "float") : "float")
        classes << node.role.not_nil! if node.role
        title = node.is_a?(AbstractBlock) ? (node.title || "") : ""
        %(<#{tag_name}#{id_attr} class="#{classes.join(" ")}">#{title}</#{tag_name}>)
      end

      def convert_image(node : AbstractNode) : String
        target = node.attr("target") || ""
        width_attr = node.attr?("width") ? %( width="#{node.attr("width")}") : ""
        height_attr = node.attr?("height") ? %( height="#{node.attr("height")}") : ""
        alt = node.is_a?(AbstractBlock) ? node.alt : (node.attr("alt") || "")
        img = %(<img src="#{node.image_uri(target)}" alt="#{encode_attribute_value(alt)}"#{width_attr}#{height_attr}#{slash}>)

        if node.attr?("link")
          href = node.attr("link") || ""
          img = %(<a class="image" href="#{href}">#{img}</a>)
        end

        id_attr = node.id ? %( id="#{node.id}") : ""
        classes = ["imageblock"]
        classes << node.attr("float").not_nil! if node.attr?("float")
        classes << "text-#{node.attr("align")}" if node.attr?("align")
        classes << node.role.not_nil! if node.role
        class_attr = %( class="#{classes.join(" ")}")
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(\n<div class="title">#{node.captioned_title}</div>) : ""
        %(<div#{id_attr}#{class_attr}>\n<div class="content">\n#{img}\n</div>#{title_el}\n</div>)
      end

      def convert_inline_anchor(node : AbstractNode) : String
        return "" unless node.is_a?(Inline)
        case node.type
        when :xref
          attrs = node.role ? %( class="#{node.role}") : ""
          text = node.text || node.attributes["refid"]? || ""
          %(<a href="#{node.target}"#{attrs}>#{text}</a>)
        when :ref
          %(<a id="#{node.id}"></a>)
        when :link
          attrs = [] of String
          attrs << %( id="#{node.id}") if node.id
          attrs << %( class="#{node.role}") if node.role
          attrs << %( title="#{node.attr("title")}") if node.attr?("title")
          target_attrs = append_link_constraint_attrs(node, attrs)
          %(<a href="#{node.target}"#{target_attrs.join}>#{node.text}</a>)
        when :bibref
          %(<a id="#{node.id}"></a>[#{node.reftext || node.id}])
        else
          ""
        end
      end

      def convert_inline_break(node : AbstractNode) : String
        text = node.is_a?(Inline) ? (node.text || "") : ""
        %(#{text}<br#{slash}>)
      end

      def convert_inline_button(node : AbstractNode) : String
        text = node.is_a?(Inline) ? (node.text || "") : ""
        %(<b class="button">#{text}</b>)
      end

      def convert_inline_callout(node : AbstractNode) : String
        text = node.is_a?(Inline) ? (node.text || "") : ""
        if node.document.attr?("icons", "font")
          %(<i class="conum" data-value="#{text}"></i><b>(#{text})</b>)
        elsif node.document.attr?("icons")
          src = node.icon_uri("callouts/#{text}")
          %(<img src="#{src}" alt="#{text}"#{slash}>)
        else
          guard = node.attr("guard") || ""
          %(#{guard}<b class="conum">(#{text})</b>)
        end
      end

      def convert_inline_footnote(node : AbstractNode) : String
        return "" unless node.is_a?(Inline)
        if (index = node.attr("index"))
          if node.type == :xref
            %(<sup class="footnoteref">[<a class="footnote" href="#_footnotedef_#{index}" title="View footnote.">#{index}</a>]</sup>)
          else
            id_attr = node.id ? %( id="_footnote_#{node.id}") : ""
            %(<sup class="footnote"#{id_attr}>[<a id="_footnoteref_#{index}" class="footnote" href="#_footnotedef_#{index}" title="View footnote.">#{index}</a>]</sup>)
          end
        else
          ""
        end
      end

      def convert_inline_image(node : AbstractNode) : String
        return "" unless node.is_a?(Inline)
        target = node.target || ""
        type = node.type || :image
        alt = node.attr("alt") || ""

        if type == :icon
          if node.document.attr?("icons") == "font"
            i_class = "fa fa-#{target}"
            i_class += " fa-#{node.attr("size")}" if node.attr?("size")
            if node.attr?("flip")
              i_class += " fa-flip-#{node.attr("flip")}"
            elsif node.attr?("rotate")
              i_class += " fa-rotate-#{node.attr("rotate")}"
            end
            title_attr = node.attr?("title") ? %( title="#{node.attr("title")}") : ""
            img = %(<i class="#{i_class}"#{title_attr}></i>)
          else
            attrs = node.attr?("width") ? %( width="#{node.attr("width")}") : ""
            attrs += %( height="#{node.attr("height")}") if node.attr?("height")
            attrs += %( title="#{node.attr("title")}") if node.attr?("title")
            img = %(<img src="#{node.icon_uri(target)}" alt="#{encode_attribute_value(alt)}"#{attrs}#{slash}>)
          end
        else
          attrs = node.attr?("width") ? %( width="#{node.attr("width")}") : ""
          attrs += %( height="#{node.attr("height")}") if node.attr?("height")
          attrs += %( title="#{node.attr("title")}") if node.attr?("title")
          img = %(<img src="#{node.image_uri(target)}" alt="#{encode_attribute_value(alt)}"#{attrs}#{slash}>)
        end

        if node.attr?("link")
          href = node.attr("link") || ""
          img = %(<a class="image" href="#{href}">#{img}</a>)
        end

        id_attr = node.id ? %( id="#{node.id}") : ""
        class_val = type.to_s
        class_val += " #{node.role}" if node.role
        %(<span#{id_attr} class="#{class_val}">#{img}</span>)
      end

      def convert_inline_indexterm(node : AbstractNode) : String
        return "" unless node.is_a?(Inline)
        node.type == :visible ? (node.text || "") : ""
      end

      def convert_inline_kbd(node : AbstractNode) : String
        keys_str = node.attr("keys") || ""
        keys = keys_str.split("+").map(&.strip)
        if keys.size == 1
          %(<kbd>#{keys[0]}</kbd>)
        else
          %(<span class="keyseq"><kbd>#{keys.join("</kbd>+<kbd>")}</kbd></span>)
        end
      end

      def convert_inline_menu(node : AbstractNode) : String
        caret = node.document.attr?("icons", "font") ? "&#160;<i class=\"fa fa-angle-right caret\"></i> " : "&#160;<b class=\"caret\">&#8250;</b> "
        menu = node.attr("menu") || ""
        menuitem = node.attr("menuitem") || ""
        submenus = node.attr("submenus") || ""

        if submenus.empty?
          if !menuitem.empty?
            %(<span class="menuseq"><b class="menu">#{menu}</b>#{caret}<b class="menuitem">#{menuitem}</b></span>)
          else
            %(<b class="menuref">#{menu}</b>)
          end
        else
          submenu_joiner = %(</b>#{caret}<b class="submenu">)
          %(<span class="menuseq"><b class="menu">#{menu}</b>#{caret}<b class="submenu">#{submenus.split(",").map(&.strip).join(submenu_joiner)}</b>#{caret}<b class="menuitem">#{menuitem}</b></span>)
        end
      end

      def convert_inline_quoted(node : AbstractNode) : String
        return "" unless node.is_a?(Inline)
        type = node.type || :strong
        open, close, is_tag = QUOTE_TAGS[type]? || DEFAULT_QUOTE_TAG
        text = node.text || ""

        if node.id
          class_attr = node.role ? %( class="#{node.role}") : ""
          if is_tag
            %(#{open[0...-1]} id="#{node.id}"#{class_attr}>#{text}#{close})
          else
            %(<span id="#{node.id}"#{class_attr}>#{open}#{text}#{close}</span>)
          end
        elsif node.role
          if is_tag
            %(#{open[0...-1]} class="#{node.role}">#{text}#{close})
          else
            %(<span class="#{node.role}">#{open}#{text}#{close}</span>)
          end
        else
          %(#{open}#{text}#{close})
        end
      end

      def convert_listing(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.captioned_title}</div>\n) : ""
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        role = node.role
        style = node.is_a?(AbstractBlock) ? node.style : nil
        nowrap = node.option?("nowrap") || !node.document.attr?("prewrap")

        if style == "source"
          lang = node.attr("language")
          syntax_hl = node.document.syntax_highlighter
          if syntax_hl
            # Use the syntax highlighter's format method to generate the pre/code block
            pre_block = syntax_hl.format(node, lang)
            return %(<div#{id_attr} class="listingblock#{role ? " #{role}" : ""}">
#{title_el}<div class="content">\n#{pre_block}\n</div>\n</div>)
          else
            pre_open = %(<pre class="highlight#{nowrap ? " nowrap" : ""}"><code#{lang ? %( class="language-#{lang}" data-lang="#{lang}") : ""}>)
            pre_close = "</code></pre>"
          end
        else
          pre_open = %(<pre#{nowrap ? " class=\"nowrap\"" : ""}>)
          pre_close = "</pre>"
        end

        %(<div#{id_attr} class="listingblock#{role ? " #{role}" : ""}">
#{title_el}<div class="content">\n#{pre_open}#{content}#{pre_close}\n</div>\n</div>)
      end

      def convert_literal(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.title}</div>\n) : ""
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        role = node.role
        nowrap = !node.document.attr?("prewrap") || node.option?("nowrap")
        %(<div#{id_attr} class="literalblock#{role ? " #{role}" : ""}">\n#{title_el}<div class="content">\n<pre#{nowrap ? " class=\"nowrap\"" : ""}>#{content}</pre>\n</div>\n</div>)
      end

      def convert_olist(node : AbstractNode) : String
        result = [] of String
        id_attr = node.id ? %( id="#{node.id}") : ""
        style = node.is_a?(AbstractBlock) ? (node.style || "arabic") : "arabic"
        classes = ["olist", style]
        classes << node.role.not_nil! if node.role
        class_attr = %( class="#{classes.join(" ")}")

        result << %(<div#{id_attr}#{class_attr}>)
        result << %(<div class="title">#{node.title}</div>) if node.is_a?(AbstractBlock) && node.title?

        keyword = node.is_a?(AbstractBlock) ? node.list_marker_keyword : nil
        type_attr = keyword ? %( type="#{keyword}") : ""
        start_attr = node.attr?("start") ? %( start="#{node.attr("start")}") : ""
        reversed_attr = node.option?("reversed") ? append_boolean_attribute("reversed") : ""
        result << %(<ol class="#{style}"#{type_attr}#{start_attr}#{reversed_attr}>)

        if node.is_a?(List)
          node.items.each do |item|
            li_attrs = if item.id
                         %( id="#{item.id}"#{item.role ? %( class="#{item.role}") : ""})
                       elsif item.role
                         %( class="#{item.role}")
                       else
                         ""
                       end
            item_text = item.is_a?(ListItem) ? (item.text || "") : ""
            item_content = item.is_a?(AbstractBlock) && item.blocks? ? "\n#{item.content}" : ""
            result << %(<li#{li_attrs}>\n<p>#{item_text}</p>#{item_content}\n</li>)
          end
        end

        result << "</ol>"
        result << "</div>"
        result.join("\n")
      end

      def convert_open(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.title}</div>\n) : ""
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        style = node.is_a?(AbstractBlock) ? node.style : nil
        role = node.role

        if style == "abstract"
          %(<div#{id_attr} class="quoteblock abstract#{role ? " #{role}" : ""}">\n#{title_el}<blockquote>\n#{content}\n</blockquote>\n</div>)
        else
          style_class = style && style != "open" ? " #{style}" : ""
          %(<div#{id_attr} class="openblock#{style_class}#{role ? " #{role}" : ""}">\n#{title_el}<div class="content">\n#{content}\n</div>\n</div>)
        end
      end

      def convert_outline(node : AbstractNode, toclevels : Int32? = nil, sectnumlevels : Int32? = nil) : String?
        return nil unless node.is_a?(AbstractBlock) && node.is_a?(AbstractBlock)
        sections = node.sections
        return nil if sections.empty?

        sectnumlevels ||= (node.document.attributes["sectnumlevels"]?.try(&.to_i?) || 3)
        toclevels ||= (node.document.attributes["toclevels"]?.try(&.to_i?) || 2)
        sectlevel = sections.first.is_a?(Section) ? sections.first.as(Section).level : 1

        result = [] of String
        result << %(<ul class="sectlevel#{sectlevel}">)
        sections.each do |section|
          next unless section.is_a?(Section)
          slevel = section.level
          next if slevel > toclevels
          stitle = if section.caption
                     section.captioned_title
                   elsif section.numbered && slevel <= sectnumlevels
                     "#{section.sectnum} #{section.title}"
                   else
                     section.title || ""
                   end
          if slevel < toclevels && (child_toc = convert_outline(section, toclevels: toclevels, sectnumlevels: sectnumlevels))
            result << %(<li><a href="##{section.id}">#{stitle}</a>)
            result << child_toc
            result << "</li>"
          else
            result << %(<li><a href="##{section.id}">#{stitle}</a></li>)
          end
        end
        result << "</ul>"
        result.join("\n")
      end

      def convert_page_break(node : AbstractNode) : String
        %(<div class="page-break"></div>)
      end

      def convert_paragraph(node : AbstractNode) : String
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        para_style = node.is_a?(AbstractBlock) ? node.style : nil
        if para_style == "abstract"
          id_attr = node.id ? %( id="#{node.id}") : ""
          role_attr = node.role ? " #{node.role}" : ""
          title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.title}</div>\n) : ""
          return %(<div#{id_attr} class="quoteblock abstract#{role_attr}">\n#{title_el}<blockquote>\n#{content}\n</blockquote>\n</div>)
        end
        if node.role
          extra_class = para_style && para_style != "normal" ? " #{para_style}" : ""
          attributes = %(#{node.id ? %( id="#{node.id}") : ""} class="paragraph#{extra_class} #{node.role}")
        elsif node.id
          attributes = %( id="#{node.id}" class="paragraph")
        else
          attributes = %( class="paragraph")
        end
        if node.is_a?(AbstractBlock) && node.title?
          %(<div#{attributes}>\n<div class="title">#{node.title}</div>\n<p>#{content}</p>\n</div>)
        else
          %(<div#{attributes}>\n<p>#{content}</p>\n</div>)
        end
      end

      def convert_preamble(node : AbstractNode) : String
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        toc = ""
        if node.is_a?(AbstractBlock)
          doc = node.document
          if doc.attr?("toc-placement", "preamble") && doc.sections? && doc.attr?("toc")
            toc = %(<div id="toc" class="#{doc.attr("toc-class", "toc")}">\n<div id="toctitle">#{doc.attr("toc-title") || "Table of Contents"}</div>\n#{convert_outline(doc) || ""}\n</div>\n)
          end
        end
        %(<div id="preamble">\n#{toc}<div class="sectionbody">\n#{content}\n</div>\n</div>)
      end

      def convert_quote(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        classes = ["quoteblock"]
        classes << node.role.not_nil! if node.role
        class_attr = %( class="#{classes.join(" ")}")
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(\n<div class="title">#{node.title}</div>) : ""
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        attribution = node.attr?("attribution") ? node.attr("attribution") : nil
        citetitle = node.attr?("citetitle") ? node.attr("citetitle") : nil
        attribution_el = if attribution || citetitle
                           cite_el = citetitle ? %(<cite>#{citetitle}</cite>) : ""
                           attr_text = attribution ? %(&#8212; #{attribution}#{citetitle ? "<br#{slash}>\n" : ""}) : ""
                           %(\n<div class="attribution">\n#{attr_text}#{cite_el}\n</div>)
                         else
                           ""
                         end
        %(<div#{id_attr}#{class_attr}>#{title_el}\n<blockquote>\n#{content}\n</blockquote>#{attribution_el}\n</div>)
      end

      def convert_section(node : AbstractNode) : String
        return "" unless node.is_a?(Section)
        doc_attrs = node.document.attributes
        level = node.level
        title = if node.caption
                  node.captioned_title
                elsif node.numbered && level <= (doc_attrs["sectnumlevels"]?.try(&.to_i?) || 3)
                  "#{node.sectnum} #{node.title}"
                else
                  node.title || ""
                end

        id_attr = ""
        if node.id
          id = node.id
          id_attr = %( id="#{id}")
          if doc_attrs["sectlinks"]?
            title = %(<a class="link" href="##{id}">#{title}</a>)
          end
          if doc_attrs["sectanchors"]?
            if doc_attrs["sectanchors"]? == "after"
              title = %(#{title}<a class="anchor" href="##{id}"></a>)
            else
              title = %(<a class="anchor" href="##{id}"></a>#{title})
            end
          end
        end

        role = node.role
        content = node.content || ""
        if level == 0
          %(<h1#{id_attr} class="sect0#{role ? " #{role}" : ""}">#{title}</h1>\n#{content})
        else
          %(<div class="sect#{level}#{role ? " #{role}" : ""}">\n<h#{level + 1}#{id_attr}>#{title}</h#{level + 1}>\n#{level == 1 ? %(<div class="sectionbody">\n#{content}\n</div>) : content}\n</div>)
        end
      end

      def convert_sidebar(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.title}</div>\n) : ""
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        role = node.role
        %(<div#{id_attr} class="sidebarblock#{role ? " #{role}" : ""}">\n<div class="content">\n#{title_el}#{content}\n</div>\n</div>)
      end

      def convert_stem(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(<div class="title">#{node.title}</div>\n) : ""
        content = node.is_a?(AbstractBlock) ? (node.content || "").to_s : ""
        style = node.is_a?(AbstractBlock) ? (node.style || "asciimath") : "asciimath"
        delimiters = BLOCK_MATH_DELIMITERS[style]?
        open_delim = delimiters.try(&.[0]) || "\\$"
        close_delim = delimiters.try(&.[1]) || "\\$"
        equation = content.to_s
        unless equation.empty? || (equation.starts_with?(open_delim) && equation.ends_with?(close_delim))
          equation = "#{open_delim}#{equation}#{close_delim}"
        end
        role = node.role
        %(<div#{id_attr} class="stemblock#{role ? " #{role}" : ""}">\n#{title_el}<div class="content">\n#{equation}\n</div>\n</div>)
      end

      def convert_table(node : AbstractNode) : String
        return "" unless node.is_a?(Table)
        result = [] of String
        id_attr = node.id ? %( id="#{node.id}") : ""
        frame = node.attr("frame", "all")
        frame = "ends" if frame == "topbot"
        grid = node.attr("grid", "all")
        classes = ["tableblock", "frame-#{frame}", "grid-#{grid}"]
        if (stripes = node.attr("stripes"))
          classes << "stripes-#{stripes}"
        end
        if node.option?("autowidth") && !node.attr?("width")
          classes << "fit-content"
        elsif (tablepcwidth = node.attr("tablepcwidth"))
          if tablepcwidth == "100"
            classes << "stretch"
          end
        end
        classes << node.attr("float").not_nil! if node.attr?("float")
        classes << node.role.not_nil! if node.role
        class_attr = %( class="#{classes.join(" ")}")
        # Add width style if width is not 100%
        tablepcwidth = node.attr("tablepcwidth")
        width_attr = if tablepcwidth && tablepcwidth != "100"
                       %( style="width: #{tablepcwidth}%;")
                     else
                       ""
                     end

        result << %(<table#{id_attr}#{class_attr}#{width_attr}>)
        result << %(<caption class="title">#{node.captioned_title}</caption>) if node.title?

        # Columns
        result << "<colgroup>"
        node.columns.each do |col|
          if col.option?("autowidth")
            result << %(<col#{slash}>)
          else
            colpcwidth = col.attr("colpcwidth") || ""
            result << %(<col width="#{colpcwidth}%"#{slash}>)
          end
        end
        result << "</colgroup>"

        # Rows
        rows = node.rows
        { {"head", rows.head}, {"body", rows.body}, {"foot", rows.foot} }.each do |tsec, section_rows|
          next if section_rows.empty?
          result << "<t#{tsec}>"
          section_rows.each do |row|
            result << "<tr>"
            row.each do |cell|
              if tsec == "head"
                cell_content = cell.text || ""
              else
                case cell.cell_style
                when :asciidoc
                  cell_content = %(<div class="content">#{cell.content}</div>)
                when :literal
                  cell_content = %(<div class="literal"><pre>#{cell.text || ""}</pre></div>)
                else
                  raw_content = cell.content
                  cell_content_parts = raw_content.is_a?(Array) ? raw_content : [raw_content]
                  base_content = cell_content_parts.empty? ? "" : %(<p class="tableblock">#{cell_content_parts.join("</p>\n<p class=\"tableblock\">")}</p>)
                  # Apply cell style wrapping
                  cell_content = case cell.cell_style
                  when :emphasis, :e
                    %(<p class="tableblock"><em>#{cell_content_parts.join}</em></p>)
                  when :monospaced, :m
                    %(<p class="tableblock"><code>#{cell_content_parts.join}</code></p>)
                  when :strong, :s
                    %(<p class="tableblock"><strong>#{cell_content_parts.join}</strong></p>)
                  when :verse
                    %(<div class="verse">#{cell.text || ""}</div>)
                  else
                    base_content
                  end
                end
              end
              cell_tag = (tsec == "head" || cell.cell_style == :header) ? "th" : "td"
              halign = cell.attr("halign") || "left"
              valign = cell.attr("valign") || "top"
              cell_class = %( class="tableblock halign-#{halign} valign-#{valign}")
              colspan_attr = cell.colspan && cell.colspan.not_nil! > 0 ? %( colspan="#{cell.colspan}") : ""
              rowspan_attr = cell.rowspan && cell.rowspan.not_nil! > 0 ? %( rowspan="#{cell.rowspan}") : ""
              result << %(<#{cell_tag}#{cell_class}#{colspan_attr}#{rowspan_attr}>#{cell_content}</#{cell_tag}>)
            end
            result << "</tr>"
          end
          result << "</t#{tsec}>"
        end

        result << "</table>"
        result.join("\n")
      end

      def convert_thematic_break(node : AbstractNode) : String
        class_attr = node.role ? %( class="#{node.role}") : ""
        %(<hr#{class_attr}#{slash}>)
      end

      def convert_toc(node : AbstractNode) : String
        doc = node.document
        unless doc.attr?("toc-placement", "macro") && doc.sections? && doc.attr?("toc")
          return "<!-- toc disabled -->"
        end
        id_attr = node.id ? %( id="#{node.id}") : %( id="toc")
        title = node.is_a?(AbstractBlock) && node.title? ? node.title.not_nil! : (doc.attr("toc-title") || "Table of Contents")
        role = node.role || doc.attr("toc-class", "toc") || "toc"
        %(<div#{id_attr} class="#{role}">\n<div class="title">#{title}</div>\n#{convert_outline(doc) || ""}\n</div>)
      end

      def convert_ulist(node : AbstractNode) : String
        result = [] of String
        id_attr = node.id ? %( id="#{node.id}") : ""
        style = node.is_a?(AbstractBlock) ? node.style : nil
        div_classes = ["ulist"]
        div_classes << style.not_nil! if style
        div_classes << node.role.not_nil! if node.role

        checklist = node.option?("checklist")
        marker_checked = ""
        marker_unchecked = ""
        if checklist
          div_classes.insert(1, "checklist")
          ul_class_attr = %( class="checklist")
          if node.option?("interactive")
            marker_checked = %(<input type="checkbox" data-item-complete="1" checked#{@xml_mode ? "=\"checked\"" : ""}> )
            marker_unchecked = %(<input type="checkbox" data-item-complete="0"> )
          elsif node.document.attr?("icons", "font")
            marker_checked = %(<i class="fa fa-check-square-o"></i> )
            marker_unchecked = %(<i class="fa fa-square-o"></i> )
          else
            marker_checked = "&#10003; "
            marker_unchecked = "&#10063; "
          end
        else
          ul_class_attr = style ? %( class="#{style}") : ""
        end

        result << %(<div#{id_attr} class="#{div_classes.join(" ")}">)
        result << %(<div class="title">#{node.title}</div>) if node.is_a?(AbstractBlock) && node.title?
        result << %(<ul#{ul_class_attr}>)

        if node.is_a?(List)
          node.items.each do |item|
            li_attrs = if item.id
                         %( id="#{item.id}"#{item.role ? %( class="#{item.role}") : ""})
                       elsif item.role
                         %( class="#{item.role}")
                       else
                         ""
                       end
            item_text = item.is_a?(ListItem) ? (item.text || "") : ""
            if checklist && item.attr?("checkbox")
              marker = item.attr?("checked") ? marker_checked : marker_unchecked
              result << %(<li#{li_attrs}>\n<p>#{marker}#{item_text}</p>)
            else
              result << %(<li#{li_attrs}>\n<p>#{item_text}</p>)
            end
            result << (item.content.to_s) if item.is_a?(AbstractBlock) && item.blocks?
            result << "</li>"
          end
        end

        result << "</ul>"
        result << "</div>"
        result.join("\n")
      end

      def convert_verse(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        classes = ["verseblock"]
        classes << node.role.not_nil! if node.role
        class_attr = %( class="#{classes.join(" ")}")
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(\n<div class="title">#{node.title}</div>) : ""
        content = node.is_a?(AbstractBlock) ? (node.content || "") : ""
        attribution = node.attr?("attribution") ? node.attr("attribution") : nil
        citetitle = node.attr?("citetitle") ? node.attr("citetitle") : nil
        attribution_el = if attribution || citetitle
                           cite_el = citetitle ? %(<cite>#{citetitle}</cite>) : ""
                           attr_text = attribution ? %(&#8212; #{attribution}#{citetitle ? "<br#{slash}>\n" : ""}) : ""
                           %(\n<div class="attribution">\n#{attr_text}#{cite_el}\n</div>)
                         else
                           ""
                         end
        %(<div#{id_attr}#{class_attr}>#{title_el}\n<pre class="content">#{content}</pre>#{attribution_el}\n</div>)
      end

      def convert_video(node : AbstractNode) : String
        id_attr = node.id ? %( id="#{node.id}") : ""
        classes = ["videoblock"]
        classes << node.attr("float").not_nil! if node.attr?("float")
        classes << "text-#{node.attr("align")}" if node.attr?("align")
        classes << node.role.not_nil! if node.role
        class_attr = %( class="#{classes.join(" ")}")
        title_el = node.is_a?(AbstractBlock) && node.title? ? %(\n<div class="title">#{node.title}</div>) : ""
        width_attr = node.attr?("width") ? %( width="#{node.attr("width")}") : ""
        height_attr = node.attr?("height") ? %( height="#{node.attr("height")}") : ""
        raw_target = node.attr("target") || ""
        poster = node.attr("poster") || ""
        asset_uri_scheme = node.document.attr("asset-uri-scheme", "https")
        asset_uri_scheme = "#{asset_uri_scheme}:" unless asset_uri_scheme.empty?
        case poster
        when "vimeo"
          start_anchor = node.attr?("start") ? %(#at=#{node.attr("start")}) : ""
          delimiter = ["?"]
          target_parts = raw_target.split("/", 2)
          target = target_parts[0]
          hash = target_parts.size > 1 ? target_parts[1] : node.attr("hash")
          hash_param = hash ? %(#{delimiter.pop? || "&amp;"}h=#{hash}) : ""
          autoplay_param = node.option?("autoplay") ? %(#{delimiter.pop? || "&amp;"}autoplay=1) : ""
          loop_param = node.option?("loop") ? %(#{delimiter.pop? || "&amp;"}loop=1) : ""
          muted_param = node.option?("muted") ? %(#{delimiter.pop? || "&amp;"}muted=1) : ""
          nofullscreen = node.option?("nofullscreen") ? "" : append_boolean_attribute("allowfullscreen")
          %(<div#{id_attr}#{class_attr}>#{title_el}\n<div class="content">\n<iframe#{width_attr}#{height_attr} src="#{asset_uri_scheme}//player.vimeo.com/video/#{target}#{hash_param}#{autoplay_param}#{loop_param}#{muted_param}#{start_anchor}" frameborder="0"#{nofullscreen}></iframe>\n</div>\n</div>)
        when "youtube"
          rel_param_val = node.option?("related") ? 1 : 0
          start_param = node.attr?("start") ? %(&amp;start=#{node.attr("start")}) : ""
          end_param = node.attr?("end") ? %(&amp;end=#{node.attr("end")}) : ""
          autoplay_param = node.option?("autoplay") ? "&amp;autoplay=1" : ""
          has_loop_param = node.option?("loop")
          loop_param = has_loop_param ? "&amp;loop=1" : ""
          mute_param = node.option?("muted") ? "&amp;mute=1" : ""
          controls_param = node.option?("nocontrols") ? "&amp;controls=0" : ""
          if node.option?("nofullscreen")
            fs_param = "&amp;fs=0"
            fs_attribute = ""
          else
            fs_param = ""
            fs_attribute = append_boolean_attribute("allowfullscreen")
          end
          modest_param = node.option?("modest") ? "&amp;modestbranding=1" : ""
          theme_param = node.attr?("theme") ? %(&amp;theme=#{node.attr("theme")}) : ""
          hl_param = node.attr?("lang") ? %(&amp;hl=#{node.attr("lang")}) : ""
          target_parts = raw_target.split("/", 2)
          target = target_parts[0]
          list = target_parts.size > 1 ? target_parts[1] : node.attr("list")
          if list
            list_param = %(&amp;list=#{list})
          else
            target_playlist = target.split(",", 2)
            target = target_playlist[0]
            playlist = target_playlist.size > 1 ? target_playlist[1] : node.attr("playlist")
            if playlist
              list_param = %(&amp;playlist=#{target},#{playlist})
            else
              list_param = has_loop_param ? %(&amp;playlist=#{target}) : ""
            end
          end
          %(<div#{id_attr}#{class_attr}>#{title_el}\n<div class="content">\n<iframe#{width_attr}#{height_attr} src="#{asset_uri_scheme}//www.youtube.com/embed/#{target}?rel=#{rel_param_val}#{start_param}#{end_param}#{autoplay_param}#{loop_param}#{mute_param}#{controls_param}#{list_param}#{fs_param}#{modest_param}#{theme_param}#{hl_param}" frameborder="0"#{fs_attribute}></iframe>\n</div>\n</div>)
        else
          target = raw_target.starts_with?("http://") || raw_target.starts_with?("https://") ? raw_target : node.media_uri(raw_target)
          start_t = node.attr("start")
          end_t = node.attr("end")
          time_anchor = (start_t || end_t) ? "#t=#{start_t || ""}#{end_t ? ",#{end_t}" : ""}" : ""
          poster_attr = if !poster.empty?
                          poster_uri = poster.starts_with?("http://") || poster.starts_with?("https://") ? poster : node.media_uri(poster)
                          %( poster="#{poster_uri}")
                        else
                          ""
                        end
          %(<div#{id_attr}#{class_attr}>#{title_el}\n<div class="content">\n<video src="#{target}#{time_anchor}"#{width_attr}#{height_attr}#{poster_attr}#{node.option?("autoplay") ? append_boolean_attribute("autoplay") : ""}#{node.option?("muted") ? append_boolean_attribute("muted") : ""}#{node.option?("nocontrols") ? "" : append_boolean_attribute("controls")}#{node.option?("loop") ? append_boolean_attribute("loop") : ""}>
Your browser does not support the video tag.
</video>\n</div>\n</div>)
        end
      end

      # Helper: void element slash for self-closing tags.
      private def slash : String
        @void_element_slash.empty? ? "" : " #{@void_element_slash}"
      end

      # Helper: append a boolean attribute.
      private def append_boolean_attribute(name : String) : String
        @xml_mode ? %( #{name}="#{name}") : %( #{name})
      end

      # Helper: append link constraint attributes.
      private def append_link_constraint_attrs(node : AbstractNode, attrs : Array(String) = [] of String) : Array(String)
        rel = "nofollow" if node.option?("nofollow")
        if (window = node.attributes["window"]?)
          attrs << %( target="#{window}")
          attrs << (rel ? %( rel="#{rel} noopener") : %( rel="noopener")) if window == "_blank" || node.option?("noopener")
        elsif rel
          attrs << %( rel="#{rel}")
        end
        attrs
      end

      # Helper: encode an attribute value for safe inclusion in HTML.
      private def encode_attribute_value(val : String) : String
        val.includes?('"') ? val.gsub('"', "&quot;") : val
      end
    end
  end
end
