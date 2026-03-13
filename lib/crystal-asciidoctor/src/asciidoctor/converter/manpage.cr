module Asciidoctor
  module Converter
    class ManPageConverter < Base
      register_for "manpage"

      ESC    = "\u001b"
      ESC_BS = "#{ESC}\\"
      ESC_FS = "#{ESC}."
      ET     = " " * 8

      WHITESPACE_CHARS = "\n\t "

      LiteralBackslashRx  = /\A\\|(#{Regex.escape ESC})?\\/
      LeadingPeriodRx     = /^\./m
      LiteralBackslashInlineRx = /\\(?=[^\\]|$)/
      TroffEscapeRx       = /\\(?=[a-zA-Z(])/
      EmDashCharRefRx     = /&#8212;(?:&#8203;)?/
      EllipsisCharRefRx   = /&#8230;(?:&#8203;)?/
      WrappedIndentRx     = /\h*\n\h*/
      MockMacroRx         = /<\/?(#{Regex.escape ESC_BS}[^>]+)>/
      EscapedMacroRx      = /^(?:#{Regex.escape ESC_BS}c\n)?#{Regex.escape ESC_FS}((?:URL|MTO) ".*?" ".*?" )( |[^\s]*)(.*?)(?: *#{Regex.escape ESC_BS}c)?$/m
      XMLMarkupRx         = /&#?[a-z\d]+;|</
      PCDATAFilterRx      = /(&#?[a-z\d]+;|<#{Regex.escape ESC_BS}f\(CR.*?<\/#{Regex.escape ESC_BS}fP>|<[^>]+>)|([^&<]+)/

      def initialize(backend : String = "manpage")
        super(backend)
        init_backend_traits(basebackend: "manpage", filetype: "man", htmlsyntax: "", outfilesuffix: ".man")
      end

      def convert(node : AbstractNode, transform : String? = nil) : String
        if transform == "embedded" && node.is_a?(Document)
          convert_embedded(node)
        elsif transform == "document" && node.is_a?(Document)
          convert_document(node)
        else
          case node
          when Document then node.attributes.has_key?("embedded") ? convert_embedded(node) : convert_document(node)
          when Section  then node.style == "discrete" ? convert_floating_title(node) : convert_section(node)
          when Block    then convert_block(node)
          when List     then convert_list(node)
          when Table    then convert_table(node)
          when Inline   then convert_inline(node)
          else ""
          end
        end
      end

      def dispatch(node : AbstractNode, transform : String) : String
        convert(node, transform)
      end

      def convert_admonition(node : AbstractBlock) : String
        textlabel = node.attr("textlabel") || (node.attr("name") || "Note").capitalize
        title_part = node.title? ? "\\fP: #{manify(node.title.to_s)}" : ""
        ".if n .sp\n.RS 4\n.it 1 an-trap\n.nr an-no-space-flag 1\n.nr an-break-flag 1\n.br\n.ps +1\n.B #{textlabel}#{title_part}\n.ps -1\n.br\n#{enclose_content(node)}\n.sp .5v\n.RE"
      end

      def convert_block(node : Block) : String
        case node.context
        when :admonition     then convert_admonition(node)
        when :example        then convert_example(node)
        when :floating_title then convert_floating_title(node)
        when :image          then convert_image(node)
        when :listing        then convert_listing(node)
        when :literal        then convert_literal(node)
        when :open           then convert_open(node)
        when :page_break     then convert_page_break(node)
        when :paragraph      then convert_paragraph(node)
        when :pass           then node.content.to_s
        when :preamble       then node.content.to_s
        when :quote          then convert_quote(node)
        when :sidebar        then convert_sidebar(node)
        when :stem           then convert_stem(node)
        when :thematic_break then convert_thematic_break(node)
        when :verse          then convert_verse(node)
        else ""
        end
      end

      def convert_document(node : Document) : String
        mantitle = (node.attr("mantitle") || "untitled").to_s
        manvolnum = node.attr("manvolnum") || "1"
        manname = node.attr("manname") || mantitle
        manmanual = node.attr("manmanual")
        mansource = node.attr("mansource")
        docdate = node.attr?("reproducible") ? nil : node.attr("docdate")
        authors_str = node.attr?("authors") ? node.attr("authors").to_s : "[see the \"AUTHOR(S)\" section]"

        result = [] of String
        result << %('\" t\n.\"     Title: #{mantitle}\n.\"    Author: #{authors_str}\n.\" Generator: Asciidoctor Crystal #{VERSION})
        result << %(.\"      Date: #{docdate}) if docdate
        manual_str = manmanual ? manmanual.to_s.tr(WHITESPACE_CHARS, " ").squeeze(' ') : "\\ \\&"
        source_str = mansource ? mansource.to_s.tr(WHITESPACE_CHARS, " ").squeeze(' ') : "\\ \\&"
        result << %(.\"    Manual: #{manual_str}\n.\"    Source: #{source_str}\n.\"  Language: English\n.\\")
        result << %(.TH "#{manify(manname.to_s.upcase)}" "#{manvolnum}" "#{docdate}" "#{mansource ? manify(mansource.to_s) : "\\ \\&"}" "#{manmanual ? manify(manmanual.to_s) : "\\ \\&"}")
        result << ".ie \\n(.g .ds Aq \\(aq"
        result << ".el       .ds Aq '"
        result << ".ss \\n[.ss] 0"
        result << ".nh"
        result << ".ad l"
        result << ".de URL\n\\fI\\\\$2\\fP <\\\\$1>\\\\$3\n..\n.als MTO URL\n.if \\n[.g] \\{\\\n.  mso www.tmac\n.  am URL\n.    ad l\n.  .\n.  am MTO\n.    ad l\n.  ."
        result << %(.  LINKSTYLE #{node.attr("man-linkstyle") || "blue R < >"})
        result << ".\\}"

        unless node.noheader
          if node.attr?("manpurpose")
            manname_title = (node.attr("manname-title") || "NAME").to_s.upcase
            mannames = node.attr?("mannames") ? node.attr("mannames").to_s.split(", ") : [manname.to_s]
            mannames_str = mannames.map { |n| manify(n).gsub("\\-", "-") }.join(", ")
            result << %(.SH "#{manname_title}"\n#{mannames_str} \\- #{manify(node.attr("manpurpose").to_s, whitespace: :normalize)})
          end
        end

         result << node.content.to_s
        append_footnotes(result, node)
        result.join("\n")
      end
      def convert_embedded(node : Document) : String
        result = [node.content.to_s]
        append_footnotes(result, node)
        result.join("\n")
      end

      def convert_example(node : AbstractBlock) : String
        title_part = node.title? ? ".sp\n.B #{manify(node.captioned_title)}\n.br" : ".sp"
        "#{title_part}\n.RS 4\n#{enclose_content(node)}\n.RE"
      end

      def convert_floating_title(node : AbstractNode) : String
        title = node.is_a?(AbstractBlock) ? node.title.to_s : ""
        %(.SS "#{manify(title)}")
      end

      def convert_image(node : AbstractBlock) : String
        alt = node.attr("alt") || ""
        title_part = node.title? ? ".sp\n.B #{manify(node.captioned_title)}\n.br" : ".sp"
        "#{title_part}\n[#{manify(alt)}]"
      end

      def convert_inline(node : Inline) : String
        case node.context
        when :anchor    then convert_inline_anchor(node)
        when :break     then convert_inline_break(node)
        when :button    then convert_inline_button(node)
        when :callout   then convert_inline_callout(node)
        when :footnote  then convert_inline_footnote(node)
        when :image     then convert_inline_image(node)
        when :indexterm then convert_inline_indexterm(node)
        when :kbd       then convert_inline_kbd(node)
        when :menu      then convert_inline_menu(node)
        when :quoted    then convert_inline_quoted(node)
        else ""
        end
      end

      def convert_inline_anchor(node : Inline) : String
        target = node.target || ""
        case node.type
        when :link
          if target.starts_with?("mailto:")
            groff_macro = "MTO"
            target = target[7..]
          else
            groff_macro = "URL"
          end
          text = node.text || ""
          text = "" if text == target
          dq_esc = "#{ESC_BS}(dq"
          at_esc = "#{ESC_BS}(at"
          unless text.empty?
            text = text.gsub('"', dq_esc)
          end
          target = target.sub("@", at_esc) if groff_macro == "MTO"
          %(#{ESC_BS}c\n#{ESC_FS}#{groff_macro} "#{target}" "#{text}" )
        when :xref
          node.text || "[#{node.attributes["refid"]? || ""}]"
        when :ref, :bibref
          ""
        else
          ""
        end
      end

      def convert_inline_break(node : Inline) : String
        "#{node.text}\n#{ESC_FS}br"
      end

      def convert_inline_button(node : Inline) : String
        %(<#{ESC_BS}fB>[#{ESC_BS}0#{node.text}#{ESC_BS}0]</#{ESC_BS}fP>)
      end

      def convert_inline_callout(node : Inline) : String
        %(<#{ESC_BS}fB>(#{node.text})<#{ESC_BS}fP>)
      end

      def convert_inline_footnote(node : Inline) : String
        if (index = node.attr("index"))
          "[#{index}]"
        elsif node.type == :xref
          "[#{node.text}]"
        else
          ""
        end
      end

      def convert_inline_image(node : Inline) : String
        alt = node.attr("alt") || node.target || ""
        if node.attr?("link")
          "[#{alt}] <#{node.attr("link")}>"
        else
          "[#{alt}]"
        end
      end

      def convert_inline_indexterm(node : Inline) : String
        node.type == :visible ? (node.text || "") : ""
      end

      def convert_inline_kbd(node : Inline) : String
        keys_val = node.attr("keys") || ""
        keys = keys_val.is_a?(String) ? keys_val.split("+").map(&.strip) : [keys_val.to_s]
        if keys.size == 1
          "<#{ESC_BS}f(CR>#{keys[0]}</#{ESC_BS}fP>"
        else
          "<#{ESC_BS}f(CR>#{keys.join("#{ESC_BS}0+#{ESC_BS}0")}</#{ESC_BS}fP>"
        end
      end

      def convert_inline_menu(node : Inline) : String
        caret = "#{ESC_BS}0#{ESC_BS}(fc#{ESC_BS}0"
        menu = node.attr("menu") || ""
        submenus = (node.attr("submenus") || "").to_s
        menuitem = node.attr("menuitem") || ""
        if !submenus.empty?
          subs = submenus.split(",").map(&.strip)
          submenu_path = subs.map { |item| %(<#{ESC_BS}fI>#{item}</#{ESC_BS}fP>) }.join(caret)
          %(<#{ESC_BS}fI>#{menu}</#{ESC_BS}fP>#{caret}#{submenu_path}#{caret}<#{ESC_BS}fI>#{menuitem}</#{ESC_BS}fP>)
        elsif !menuitem.to_s.empty?
          %(<#{ESC_BS}fI>#{menu}#{caret}#{menuitem}</#{ESC_BS}fP>)
        else
          %(<#{ESC_BS}fI>#{menu}</#{ESC_BS}fP>)
        end
      end

      def convert_inline_quoted(node : Inline) : String
        text = node.text || ""
        case node.type
        when :emphasis  then %(<#{ESC_BS}fI>#{text}</#{ESC_BS}fP>)
        when :strong    then %(<#{ESC_BS}fB>#{text}</#{ESC_BS}fP>)
        when :monospaced then "<#{ESC_BS}f(CR>#{text}</#{ESC_BS}fP>"
        when :single    then "<#{ESC_BS}(oq>#{text}</#{ESC_BS}(cq>"
        when :double    then "<#{ESC_BS}(lq>#{text}</#{ESC_BS}(rq>"
        else text
        end
      end

      def convert_list(node : List) : String
        case node.context
        when :colist then convert_colist(node)
        when :dlist  then convert_dlist(node)
        when :olist  then convert_olist(node)
        when :ulist  then convert_ulist(node)
        else ""
        end
      end

      def convert_listing(node : AbstractBlock) : String
        content = node.is_a?(Block) ? node.source : ""
        result = [] of String
        if node.title?
          result << ".sp\n.B #{manify(node.captioned_title)}\n.br"
        end
        result << ".sp\n.if n .RS 4\n.nf\n.fam C\n#{manify(content, whitespace: :preserve)}\n.fam\n.fi\n.if n .RE"
        result.join("\n")
      end

      def convert_literal(node : AbstractBlock) : String
        content = node.is_a?(Block) ? node.source : ""
        result = [] of String
        if node.title?
          result << ".sp\n.B #{manify(node.title.to_s)}\n.br"
        end
        result << ".sp\n.if n .RS 4\n.nf\n.fam C\n#{manify(content, whitespace: :preserve)}\n.fam\n.fi\n.if n .RE"
        result.join("\n")
      end

      def convert_colist(node : List) : String
        result = [] of String
        if node.title?
          result << ".sp\n.B #{manify(node.title.to_s)}\n.br"
        end
        result << ".TS\ntab(:);\nr lw(\\n(.lu*75u/100u)."
        num = 0
        node.items.each do |_item|
          item = _item.as(ListItem)
          num += 1
          result << "\\fB(#{num})\\fP\\h'-2n':T{"
          result << manify(item.text || "", whitespace: :normalize)
          result << item.content.to_s if item.blocks?
          result << "T}"
        end
        result << ".TE"
        result.join("\n")
      end

      def convert_dlist(node : List) : String
        result = [] of String
        if node.title?
          result << ".sp\n.B #{manify(node.title.to_s)}\n.br"
        end
        node.items.each do |_item|
          item = _item.as(ListItem)
          result << ".sp\n#{manify(item.text || "", whitespace: :normalize)}\n.RS 4"
          result << item.content.to_s if item.blocks?
          result << ".RE"
        end
        result.join("\n")
      end

      def convert_olist(node : List) : String
        result = [] of String
        if node.title?
          result << ".sp\n.B #{manify(node.title.to_s)}\n.br"
        end
        start = (node.attr("start") || "1").to_s.to_i
        node.items.each_with_index do |_item, idx|
          item = _item.as(ListItem)
          numeral = idx + start
          list_text = manify(item.text || "", whitespace: :normalize)
          result << ".sp\n.RS 4\n.ie n \\{\\\\\\h'-04' #{numeral}.\\h'+01'\\c\n.\\}\n.el \\{\\\n.  sp -1\n.  IP \" #{numeral}.\" 4.2\n.\\}#{list_text.empty? ? "" : "\n" + list_text}"
          result << item.content.to_s if item.blocks?
          result << ".RE"
        end
        result.join("\n")
      end

      def convert_open(node : AbstractBlock) : String
        case node.style
        when "abstract", "partintro"
          enclose_content(node)
        else
          node.content.to_s
        end
      end

      def convert_page_break(node : AbstractBlock) : String
        ".bp"
      end

      def convert_paragraph(node : AbstractBlock) : String
        content = node.content.to_s
        if node.title?
          ".sp\n.B #{manify(node.title.to_s)}\n.br\n#{manify(content, whitespace: :normalize)}"
        else
          ".sp\n#{manify(content, whitespace: :normalize)}"
        end
      end

      def convert_quote(node : AbstractBlock) : String
        result = [] of String
        if node.title?
          result << ".sp\n.RS 3\n.B #{manify(node.title.to_s)}\n.br\n.RE"
        end
        attribution_line = node.attr?("citetitle") ? "#{node.attr("citetitle")} " : nil
        attribution_line = node.attr?("attribution") ? "#{attribution_line}\\(em #{node.attr("attribution")}" : nil
        result << ".RS 3\n.ll -.6i\n#{enclose_content(node)}\n.br\n.RE\n.ll"
        if attribution_line
          result << ".RS 5\n.ll -.10i\n#{attribution_line}\n.RE\n.ll"
        end
        result.join("\n")
      end

      def convert_section(node : Section) : String
        if node.level > 1
          groff_cmd = "SS"
          stitle = node.captioned_title
        else
          groff_cmd = "SH"
          stitle = uppercase_pcdata(node.title.to_s)
        end
        %(.#{groff_cmd} "#{manify(stitle)}"\n#{node.content})
      end

      def convert_sidebar(node : AbstractBlock) : String
        title_part = node.title? ? ".sp\n.B #{manify(node.title.to_s)}\n.br" : ".sp"
        "#{title_part}\n.RS 4\n#{enclose_content(node)}\n.RE"
      end

      def convert_stem(node : AbstractBlock) : String
        title_part = node.title? ? ".sp\n.B #{manify(node.title.to_s)}\n.br" : ".sp"
        content = node.content.to_s
        style = node.style || "asciimath"
        "#{title_part}\n#{manify(content, whitespace: :preserve)} (#{style})"
      end

      def convert_table(node : Table) : String
        result = [] of String
        if node.title?
          result << ".sp\n.it 1 an-trap\n.nr an-no-space-flag 1\n.nr an-break-flag 1\n.br\n.B #{manify(node.captioned_title)}\n"
        end
        result << ".TS\nallbox tab(:);"
        col_count = node.columns.size
        col_count = 1 if col_count == 0

        rows = node.rows
        all_rows = rows.head + rows.body + rows.foot
        if !all_rows.empty?
          header_spec = all_rows.map { |_row| (["lt"] * col_count).join(" ") + "." }.first
          result << "\n#{header_spec}"
          all_rows.each do |row|
            row_texts = [] of String
            row.each_with_index do |cell, i|
              cell_text = manify(cell.text || "", whitespace: :normalize)
              if i < row.size - 1
                row_texts << "T{\n#{cell_text}\nT}:"
              else
                row_texts << "T{\n#{cell_text}\nT}\n"
              end
            end
            result << row_texts.join
          end
        else
          result << "\nlt.\n"
        end
        result << ".TE\n.sp"
        result.join
      end

      def convert_thematic_break(node : AbstractBlock) : String
        ".sp\n.ce\n\\l'\\n(.lu*25u/100u\\(ap'"
      end

      def convert_ulist(node : List) : String
        result = [] of String
        if node.title?
          result << ".sp\n.B #{manify(node.title.to_s)}\n.br"
        end
        node.items.each do |_item|
          item = _item.as(ListItem)
          list_text = manify(item.text || "", whitespace: :normalize)
          result << ".sp\n.RS 4\n.ie n \\{\\\\h'-04'\\(bu\\h'+03'\\c\n.\\}\n.el \\{\\\n.  sp -1\n.  IP \\(bu 2.3\n.\\}#{list_text.empty? ? "" : "\n" + list_text}"
          result << item.content.to_s if item.blocks?
          result << ".RE"
        end
        result.join("\n")
      end

      def convert_verse(node : AbstractBlock) : String
        result = [] of String
        if node.title?
          result << ".sp\n.B #{manify(node.title.to_s)}\n.br"
        end
        attribution_line = node.attr?("citetitle") ? "#{node.attr("citetitle")} " : nil
        attribution_line = node.attr?("attribution") ? "#{attribution_line}\\(em #{node.attr("attribution")}" : nil
        result << ".sp\n.nf\n#{manify(node.content.to_s, whitespace: :preserve)}\n.fi\n.br"
        if attribution_line
          result << ".in +.5i\n.ll -.5i\n#{attribution_line}\n.in\n.ll"
        end
        result.join("\n")
      end

      # --- Private helpers ---

      private def enclose_content(node : AbstractBlock) : String
        if node.content_model == ContentModel::Compound
          node.content.to_s
        else
          ".sp\n#{manify(node.content.to_s, whitespace: :normalize)}"
        end
      end

      private def manify(str : String, whitespace : Symbol = :collapse) : String
        case whitespace
        when :preserve
          str = str.gsub("\t", ET)
        when :normalize
          str = str.gsub(WrappedIndentRx, "\n")
        else
          str = str.tr(WHITESPACE_CHARS, " ").squeeze(' ')
        end
        # First, convert literal backslashes in content to \(rs (before generating new backslashes)
        # Protect ESC_BS markers from being converted
        str = str
          .gsub(ESC_BS, "\u001c")  # temporarily hide ESC_BS markers
          .gsub("\\", "\\(rs")  # convert literal backslashes in content to \(rs
          .gsub("\u001c", ESC_BS)  # restore ESC_BS markers
        str = str
          .gsub(EllipsisCharRefRx, ".|.|.")
          .gsub(LeadingPeriodRx, "#{ESC_BS}&.")  # use ESC_BS so it won't be re-converted
          .gsub(EscapedMacroRx) { |_, md|  # unescape troff macro, quote adjacent char, isolate macro line
            macro_part = md[1]? || ""
            adj_char = md[2]? || ""
            rest = (md[3]? || "").lstrip
            dq = '"'
            if rest.empty?
              ".#{macro_part}#{dq}#{adj_char}#{dq}"
            else
              ".#{macro_part}#{dq}#{adj_char.rstrip}#{dq}\n#{rest}"
            end
          }
          .gsub("-", "#{ESC_BS}-")
          .gsub("&lt;", "<")
          .gsub("&gt;", ">")
          .gsub("&#43;", "+")
          .gsub("&#160;", "#{ESC_BS}~")
          .gsub("&#169;", "#{ESC_BS}(co")
          .gsub("&#174;", "#{ESC_BS}(rg")
          .gsub("&#8482;", "#{ESC_BS}(tm")
          .gsub("&#176;", "#{ESC_BS}(de")
          .gsub("&#8201;", " ")
          .gsub("&#8211;", "#{ESC_BS}(en")
          .gsub(EmDashCharRefRx, "#{ESC_BS}(em")
          .gsub("&#8216;", "#{ESC_BS}(oq")
          .gsub("&#8217;", "#{ESC_BS}(cq")
          .gsub("&#8220;", "#{ESC_BS}(lq")
          .gsub("&#8221;", "#{ESC_BS}(rq")
          .gsub("&#8592;", "#{ESC_BS}(<-")
          .gsub("&#8594;", "#{ESC_BS}(->")
          .gsub("&#8656;", "#{ESC_BS}(lA")
          .gsub("&#8658;", "#{ESC_BS}(rA")
          .gsub("&#8203;", "#{ESC_BS}:")
          .gsub("&amp;", "&")
          .gsub("'", "#{ESC_BS}*(Aq")
          .gsub(MockMacroRx) { |_, md| md[1]? || "" }  # remove mock boundary markers
          .gsub(ESC_BS, "\\")  # restore all ESC_BS as real backslashes
          .gsub(ESC_FS, ".")
          .rstrip
        str
      end

      private def append_footnotes(result : Array(String), node : Document) : Nil
        return unless node.footnotes? && !node.attr?("nofootnotes")
        result << ".SH \"NOTES\""
        node.footnotes.each do |fn|
          result << ".IP [#{fn.index}]"
          text = fn.text || ""
          result << manify(text, whitespace: :normalize)
        end
      end

      private def uppercase_pcdata(string : String) : String
        if XMLMarkupRx =~ string
          string.gsub(PCDATAFilterRx) do |_, md|
            if (plain = md[2]?)
              plain.upcase
            else
              md[1]? || ""
            end
          end
        else
          string.upcase
        end
      end
    end
  end
end
