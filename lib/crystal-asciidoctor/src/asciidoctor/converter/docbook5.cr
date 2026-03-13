module Asciidoctor
  module Converter
    class DocBook5Converter < Base
      register_for "docbook5"

      DLIST_TAGS_DEFAULT = {list: "variablelist", entry: "varlistentry", label: "label", term: "term", item: "listitem"}
      DLIST_TAGS = {
        "qanda"    => {list: "qandaset", entry: "qandaentry", label: "question", term: "simpara", item: "answer"},
        "glossary" => {list: nil, entry: "glossentry", label: nil, term: "glossterm", item: "glossdef"},
      }

      MANPAGE_SECTION_TAGS = {"section" => "refsection", "synopsis" => "refsynopsisdiv"}

      QUOTE_TAGS = {
        :asciimath   => { "", "" },
        :double      => { %(<quote role="double">), "</quote>" },
        :emphasis    => { "<emphasis>", "</emphasis>" },
        :latexmath   => { "", "" },
        :mark        => { %(<emphasis role="marked">), "</emphasis>" },
        :monospaced  => { "<literal>", "</literal>" },
        :single      => { %(<quote role="single">), "</quote>" },
        :strong      => { %(<emphasis role="strong">), "</emphasis>" },
        :subscript   => { "<subscript>", "</subscript>" },
        :superscript => { "<superscript>", "</superscript>" },
      }

      TABLE_PI_NAMES = ["dbhtml", "dbfo", "dblatex"]

      def initialize(backend : String = "docbook5")
        super(backend)
        init_backend_traits(basebackend: "docbook", filetype: "xml", htmlsyntax: "xml", outfilesuffix: ".xml")
      end

      def convert(node : AbstractNode, transform : String? = nil) : String
        if transform == "embedded" && node.is_a?(Document)
          convert_embedded(node)
        elsif transform == "document" && node.is_a?(Document)
          convert_document(node)
        else
          case node
          when Document  then node.attributes.has_key?("embedded") ? convert_embedded(node) : convert_document(node)
          when Section   then node.style == "discrete" ? convert_floating_title(node) : convert_section(node)
          when Block     then convert_block(node)
          when List      then convert_list(node)
          when Table     then convert_table(node)
          when Inline    then convert_inline(node)
          else ""
          end
        end
      end

      def dispatch(node : AbstractNode, transform : String) : String
        convert(node, transform)
      end

      def convert_admonition(node : AbstractBlock) : String
        tag_name = node.attr("name") || "note"
        %(<#{tag_name}#{common_attributes(node.id, node.role, node.reftext)}>\n#{title_tag(node)}#{enclose_content(node)}\n</#{tag_name}>)
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
        when :preamble       then convert_preamble(node)
        when :quote          then convert_quote(node)
        when :sidebar        then convert_sidebar(node)
        when :stem           then convert_stem(node)
        when :thematic_break then convert_thematic_break(node)
        when :verse          then convert_verse(node)
        else ""
        end
      end

      def convert_document(node : Document) : String
        result = [] of String
        result << %(<?xml version="1.0" encoding="UTF-8"?>)
        if node.attr?("toc")
          result << (node.attr?("toclevels") ? %(<?asciidoc-toc maxdepth="#{node.attr("toclevels")}"?>) : "<?asciidoc-toc?>")
        end
        if node.attr?("sectnums")
          result << (node.attr?("sectnumlevels") ? %(<?asciidoc-numbered maxdepth="#{node.attr("sectnumlevels")}"?>) : "<?asciidoc-numbered?>")
        end
        lang_attribute = node.attr?("nolang") ? "" : %( xml:lang="#{node.attr("lang") || "en"}")
        root_tag_name = node.doctype
        manpage = false
        if root_tag_name == "manpage"
          manpage = true
          root_tag_name = "article"
        end
        root_tag_idx = result.size
        id = node.id

        result << document_info_tag(node) unless node.noheader

        if manpage
          result << "<refentry>"
          result << "<refmeta>"
          result << %(<refentrytitle>#{node.attr("mantitle")}</refentrytitle>) if node.attr?("mantitle")
          result << %(<manvolnum>#{node.attr("manvolnum")}</manvolnum>) if node.attr?("manvolnum")
          result << %(<refmiscinfo class="source">#{node.attr("mansource") || "&#160;"}</refmiscinfo>)
          result << %(<refmiscinfo class="manual">#{node.attr("manmanual") || "&#160;"}</refmiscinfo>)
          result << "</refmeta>"
          result << "<refnamediv>"
          result << %(<refpurpose>#{node.attr("manpurpose")}</refpurpose>) if node.attr?("manpurpose")
          result << "</refnamediv>"
        end

        if node.blocks?
          result << node.blocks.map { |block| block.is_a?(AbstractBlock) ? convert(block) : "" }.reject(&.empty?).join("\n")
        end

        result << "</refentry>" if manpage

        node_id = id || "__#{node.doctype}-root__"
        result.insert(root_tag_idx, %(<#{root_tag_name} xmlns="http://docbook.org/ns/docbook" xmlns:xl="http://www.w3.org/1999/xlink" version="5.0"#{lang_attribute}#{common_attributes(node_id)}>))
        result << %(</#{root_tag_name}>)
        result.join("\n")
      end

      def convert_embedded(node : Document) : String
        if node.blocks?
          node.blocks.map { |block| block.is_a?(AbstractBlock) ? convert(block) : "" }.reject(&.empty?).join("\n")
        else
          ""
        end
      end

      def convert_example(node : AbstractBlock) : String
        if node.title?
          %(<example#{common_attributes(node.id, node.role, node.reftext)}>\n<title>#{node.title}</title>\n#{enclose_content(node)}\n</example>)
        else
          %(<informalexample#{common_attributes(node.id, node.role, node.reftext)}>\n#{enclose_content(node)}\n</informalexample>)
        end
      end

      def convert_floating_title(node : AbstractNode) : String
        if node.is_a?(Section)
          %(<bridgehead#{common_attributes(node.id, node.role, node.reftext)} renderas="sect#{node.level}">#{node.title}</bridgehead>)
        else
          ""
        end
      end

      def convert_image(node : AbstractBlock) : String
        target = node.attr("target") || ""
        alt = node.attr("alt") || ""
        align_attribute = node.attr?("align") ? %( align="#{node.attr("align")}") : ""

        mediaobject = %(<mediaobject>\n<imageobject>\n<imagedata fileref="#{node.image_uri(target)}"#{image_size_attributes(node.attributes)}#{align_attribute}/>\n</imageobject>\n<textobject><phrase>#{alt}</phrase></textobject>\n</mediaobject>)

        if node.title?
          %(<figure#{common_attributes(node.id, node.role, node.reftext)}>\n<title>#{node.title}</title>\n#{mediaobject}\n</figure>)
        else
          %(<informalfigure#{common_attributes(node.id, node.role, node.reftext)}>\n#{mediaobject}\n</informalfigure>)
        end
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
        case node.type
        when :ref
          id = node.id || ""
          %(<anchor#{common_attributes(id, nil, node.reftext || "[#{id}]")}/>)
        when :xref
          if (path = node.attributes["path"]?)
            %(<link xl:href="#{node.target}">#{node.text || path}</link>)
          else
            linkend = node.attributes["refid"]? || ""
            if (text = node.text)
              %(<link linkend="#{linkend}">#{text}</link>)
            else
              %(<xref linkend="#{linkend}"/>)
            end
          end
        when :link
          %(<link xl:href="#{node.target}">#{node.text}</link>)
        when :bibref
          id = node.id || ""
          text = "[#{node.reftext || id}]"
          %(<anchor#{common_attributes(id, nil, text)}/>#{text})
        else
          ""
        end
      end

      def convert_inline_break(node : Inline) : String
        %(#{node.text}<?asciidoc-br?>)
      end

      def convert_inline_button(node : Inline) : String
        %(<guibutton>#{node.text}</guibutton>)
      end

      def convert_inline_callout(node : Inline) : String
        %(<co#{common_attributes(node.id || "")}/>)
      end

      def convert_inline_footnote(node : Inline) : String
        if node.type == :xref
          %(<footnoteref linkend="#{node.target}"/>)
        else
          %(<footnote#{common_attributes(node.id || "")}><simpara>#{node.text}</simpara></footnote>)
        end
      end

      def convert_inline_image(node : Inline) : String
        target = node.target || ""
        alt = node.attr("alt") || target
        fileref = if node.type == :icon
                    node.icon_uri(target)
                  else
                    node.image_uri(target)
                  end
        %(<inlinemediaobject#{common_attributes(node.id, node.role)}>\n<imageobject>\n<imagedata fileref="#{fileref}"#{image_size_attributes(node.attributes)}/>\n</imageobject>\n<textobject><phrase>#{alt}</phrase></textobject>\n</inlinemediaobject>)
      end

      def convert_inline_indexterm(node : Inline) : String
        if node.type == :visible
          %(<indexterm>\n<primary>#{node.text}</primary>\n</indexterm>#{node.text})
        else
          terms = node.attr("terms")
          if terms.is_a?(String)
            %(<indexterm>\n<primary>#{terms}</primary>\n</indexterm>)
          else
            ""
          end
        end
      end

      def convert_inline_kbd(node : Inline) : String
        keys_val = node.attr("keys") || ""
        keys = keys_val.is_a?(String) ? keys_val.split("+").map(&.strip) : [keys_val.to_s]
        if keys.size == 1
          %(<keycap>#{keys[0]}</keycap>)
        else
          %(<keycombo><keycap>#{keys.join("</keycap><keycap>")}</keycap></keycombo>)
        end
      end

      def convert_inline_menu(node : Inline) : String
        menu = node.attr("menu") || ""
        submenus = node.attr("submenus") || ""
        menuitem = node.attr("menuitem") || ""
        if submenus.to_s.empty?
          if !menuitem.to_s.empty?
            %(<menuchoice><guimenu>#{menu}</guimenu> <guimenuitem>#{menuitem}</guimenuitem></menuchoice>)
          else
            %(<guimenu>#{menu}</guimenu>)
          end
        else
          subs = submenus.to_s.split(",").map(&.strip)
          %(<menuchoice><guimenu>#{menu}</guimenu> <guisubmenu>#{subs.join("</guisubmenu> <guisubmenu>")}</guisubmenu> <guimenuitem>#{menuitem}</guimenuitem></menuchoice>)
        end
      end

      def convert_inline_quoted(node : Inline) : String
        type = node.type
        if type == :asciimath || type == :latexmath
          equation = node.text || ""
          return %(<inlineequation><mathphrase><![CDATA[#{equation}]]></mathphrase></inlineequation>)
        end

        tag_pair = QUOTE_TAGS[type]? || {"", ""}
        open_tag = tag_pair[0]
        close_tag = tag_pair[1]
        text = node.text || ""

        quoted_text = if node.role
                        if open_tag.includes?("<")
                          %(#{open_tag.rchop} role="#{node.role}">#{text}#{close_tag})
                        else
                          %(#{open_tag}#{text}#{close_tag})
                        end
                      else
                        %(#{open_tag}#{text}#{close_tag})
                      end

        node.id ? %(<anchor#{common_attributes(node.id.not_nil!)}/>#{quoted_text}) : quoted_text
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
        informal = !node.title?
        common_attrs = common_attributes(node.id, node.role, node.reftext)
        content = node.is_a?(Block) ? node.source : ""

        if node.style == "source"
          lang = node.attr("language")
          linenums = node.option?("linenums") || node.option?("linenumbering")
          linenumbering = linenums ? "numbered" : "unnumbered"
          start_attr = linenums && node.attr?("start") ? %( startinglinenumber="#{node.attr("start")}") : ""
          if lang
            wrapped_content = %(<programlisting#{informal ? common_attrs : ""} language="#{lang}" linenumbering="#{linenumbering}"#{start_attr}>#{content}</programlisting>)
          else
            wrapped_content = %(<screen#{informal ? common_attrs : ""} linenumbering="#{linenumbering}"#{start_attr}>#{content}</screen>)
          end
        else
          wrapped_content = %(<screen#{informal ? common_attrs : ""}>#{content}</screen>)
        end

        if informal
          wrapped_content
        else
          %(<formalpara#{common_attrs}>\n<title>#{node.title}</title>\n<para>\n#{wrapped_content}\n</para>\n</formalpara>)
        end
      end

      def convert_literal(node : AbstractBlock) : String
        content = node.is_a?(Block) ? node.source : ""
        if node.title?
          %(<formalpara#{common_attributes(node.id, node.role, node.reftext)}>\n<title>#{node.title}</title>\n<para>\n<literallayout class="monospaced">#{content}</literallayout>\n</para>\n</formalpara>)
        else
          %(<literallayout#{common_attributes(node.id, node.role, node.reftext)} class="monospaced">#{content}</literallayout>)
        end
      end

      def convert_colist(node : List) : String
        result = [] of String
        result << %(<calloutlist#{common_attributes(node.id, node.role, node.reftext)}>)
        result << %(<title>#{node.title}</title>) if node.title?
        node.items.each do |_item|
          item = _item.as(ListItem)
          result << %(<callout arearefs="#{item.attr("coids") || ""}">)
          result << %(<para>#{item.text}</para>)
          result << item.content.to_s if item.blocks?
          result << "</callout>"
        end
        result << "</calloutlist>"
        result.join("\n")
      end

      def convert_dlist(node : List) : String
        result = [] of String
        style = node.style || ""
        tags = DLIST_TAGS[style]? || DLIST_TAGS_DEFAULT
        list_tag = tags[:list]
        entry_tag = tags[:entry]
        term_tag = tags[:term]
        item_tag = tags[:item]

        if list_tag
          result << %(<#{list_tag}#{common_attributes(node.id, node.role, node.reftext)}>)
          result << %(<title>#{node.title}</title>) if node.title?
        end

        node.items.each do |_item|
          item = _item.as(ListItem)
          result << %(<#{entry_tag}>)
          result << %(<#{term_tag}>#{item.text}</#{term_tag}>)
          result << %(<#{item_tag}>)
          result << item.content.to_s if item.blocks?
          result << %(</#{item_tag}>)
          result << %(</#{entry_tag}>)
        end

        result << %(</#{list_tag}>) if list_tag
        result.join("\n")
      end

      def convert_olist(node : List) : String
        result = [] of String
        num_attribute = node.style ? %( numeration="#{node.style}") : ""
        start_attribute = node.attr?("start") ? %( startingnumber="#{node.attr("start")}") : ""
        result << %(<orderedlist#{common_attributes(node.id, node.role, node.reftext)}#{num_attribute}#{start_attribute}>)
        result << %(<title>#{node.title}</title>) if node.title?
        node.items.each do |_item|
          item = _item.as(ListItem)
          result << %(<listitem#{common_attributes(item.id, item.role)}>)
          result << %(<simpara>#{item.text}</simpara>)
          result << item.content.to_s if item.blocks?
          result << "</listitem>"
        end
        result << "</orderedlist>"
        result.join("\n")
      end

      def convert_open(node : AbstractBlock) : String
        case node.style
        when "abstract"
          %(<abstract>\n#{title_tag(node)}#{enclose_content(node)}\n</abstract>)
        when "partintro"
          %(<partintro#{common_attributes(node.id, node.role, node.reftext)}>\n#{title_tag(node)}#{enclose_content(node)}\n</partintro>)
        else
          if node.title?
            %(<formalpara#{common_attributes(node.id, node.role, node.reftext)}>\n<title>#{node.title}</title>\n<para>#{node.content}</para>\n</formalpara>)
          elsif node.id || node.role
            %(<simpara#{common_attributes(node.id, node.role, node.reftext)}>#{node.content}</simpara>)
          else
            enclose_content(node)
          end
        end
      end

      def convert_page_break(node : AbstractBlock) : String
        "<simpara><?asciidoc-pagebreak?></simpara>"
      end

      def convert_paragraph(node : AbstractBlock) : String
        if node.style == "abstract"
          %(<abstract>\n<simpara>#{node.content}</simpara>\n</abstract>)
        elsif node.title?
          %(<formalpara#{common_attributes(node.id, node.role, node.reftext)}>\n<title>#{node.title}</title>\n<para>#{node.content}</para>\n</formalpara>)
        else
          %(<simpara#{common_attributes(node.id, node.role, node.reftext)}>#{node.content}</simpara>)
        end
      end

      def convert_preamble(node : AbstractBlock) : String
        if node.document.doctype == "book"
          # Check if preamble contains an abstract block
          abstract_content = node.blocks.find { |b| b.is_a?(AbstractBlock) && b.style == "abstract" }
          if abstract_content
            abstract_str = %(<abstract>\n<simpara>#{abstract_content.is_a?(AbstractBlock) ? abstract_content.content : ""}</simpara>\n</abstract>)
            other_content = node.blocks.reject { |b| b.is_a?(AbstractBlock) && b.style == "abstract" }
            other_str = other_content.map { |b| b.is_a?(AbstractBlock) ? convert(b) : "" }.join("\n")
            # Use preface-title attribute if set, otherwise use node title (may be empty)
            preface_title = node.document.attributes["preface-title"]? || node.title || ""
            %(<preface#{common_attributes(node.id, node.role, node.reftext)}>\n<title>#{preface_title}</title>\n#{abstract_str}\n#{other_str}\n</preface>)
          else
            # Use preface-title attribute if set, otherwise use node title (may be empty)
            preface_title = node.document.attributes["preface-title"]? || node.title || ""
            %(<preface#{common_attributes(node.id, node.role, node.reftext)}>\n<title>#{preface_title}</title>\n#{node.content}\n</preface>)
          end
        else
          node.content.to_s
        end
      end

      def convert_quote(node : AbstractBlock) : String
        blockquote_tag(node) { enclose_content(node) }
      end

      def convert_section(node : Section) : String
        # Special handling for abstract sections in DocBook
        # The abstract section is rendered without xml:id to match Ruby Asciidoctor behavior
        if node.sectname == "abstract"
          return %(<abstract>\n#{node.content}\n</abstract>)
        end
        tag_name = if node.document.doctype == "manpage"
                     MANPAGE_SECTION_TAGS[node.sectname]? || node.sectname
                   else
                     node.sectname
                   end
        title_el = if node.special? && (node.option?("notitle") || node.option?("untitled"))
                     ""
                   else
                     %(<title>#{node.title}</title>\n)
                   end
        %(<#{tag_name}#{common_attributes(node.id, node.role, node.reftext)}>\n#{title_el}#{node.content}\n</#{tag_name}>)
      end

      def convert_sidebar(node : AbstractBlock) : String
        %(<sidebar#{common_attributes(node.id, node.role, node.reftext)}>\n#{title_tag(node)}#{enclose_content(node)}\n</sidebar>)
      end

      def convert_stem(node : AbstractBlock) : String
        content = node.content.to_s
        equation_data = %(<mathphrase><![CDATA[#{content}]]></mathphrase>)
        if node.title?
          %(<equation#{common_attributes(node.id, node.role, node.reftext)}>\n<title>#{node.title}</title>\n#{equation_data}\n</equation>)
        else
          %(<informalequation#{common_attributes(node.id, node.role, node.reftext)}>\n#{equation_data}\n</informalequation>)
        end
      end

      def convert_table(node : Table) : String
        result = [] of String
        tag_name = node.title? ? "table" : "informaltable"
        frame = node.attr("frame") || "all"
        frame = "topbot" if frame == "ends"
        grid = node.attr("grid") || ""
        rowsep = (grid == "none" || grid == "cols") ? "0" : "1"
        colsep = (grid == "none" || grid == "rows") ? "0" : "1"

        result << %(<#{tag_name}#{common_attributes(node.id, node.role, node.reftext)} frame="#{frame}" rowsep="#{rowsep}" colsep="#{colsep}">)
        result << %(<title>#{node.title}</title>) if tag_name == "table"
        result << %(<tgroup cols="#{node.columns.size}">)

        node.columns.each_with_index do |col, i|
          colwidth = col.attr("colpcwidth") || ""
          result << %(<colspec colname="col_#{i + 1}" colwidth="#{colwidth}*"/>)
        end

        rows = node.rows
        {"head" => rows.head, "body" => rows.body, "foot" => rows.foot}.each do |tsec, section_rows|
          next if section_rows.empty?
          result << %(<t#{tsec}>)
          section_rows.each do |row|
            result << "<row>"
            row.each do |cell|
              halign = cell.attr("halign") || "left"
              valign = cell.attr("valign") || "top"
              entry_start = %(<entry align="#{halign}" valign="#{valign}">)
              cell_content = if tsec == "head"
                               cell.text || ""
                             else
                               cell.text || ""
                             end
              result << %(#{entry_start}#{cell_content}</entry>)
            end
            result << "</row>"
          end
          result << %(</t#{tsec}>)
        end

        result << "</tgroup>"
        result << %(</#{tag_name}>)
        result.join("\n")
      end

      def convert_thematic_break(node : AbstractBlock) : String
        "<simpara><?asciidoc-hr?></simpara>"
      end

      def convert_ulist(node : List) : String
        result = [] of String
        if node.style == "bibliography"
          result << %(<bibliodiv#{common_attributes(node.id, node.role, node.reftext)}>)
          result << %(<title>#{node.title}</title>) if node.title?
          node.items.each do |_item|
          item = _item.as(ListItem)
            result << "<bibliomixed>"
            result << %(<bibliomisc>#{item.text}</bibliomisc>)
            result << item.content.to_s if item.blocks?
            result << "</bibliomixed>"
          end
          result << "</bibliodiv>"
        else
          checklist = node.option?("checklist")
          mark_type = checklist ? "none" : node.style
          mark_attribute = mark_type ? %( mark="#{mark_type}") : ""
          result << %(<itemizedlist#{common_attributes(node.id, node.role, node.reftext)}#{mark_attribute}>)
          result << %(<title>#{node.title}</title>) if node.title?
          node.items.each do |_item|
          item = _item.as(ListItem)
            text_marker = ""
            if checklist && item.attr?("checkbox")
              text_marker = item.attr?("checked") ? "&#10003; " : "&#10063; "
            end
            result << %(<listitem#{common_attributes(item.id, item.role)}>)
            result << %(<simpara>#{text_marker}#{item.text}</simpara>)
            result << item.content.to_s if item.blocks?
            result << "</listitem>"
          end
          result << "</itemizedlist>"
        end
        result.join("\n")
      end

      def convert_verse(node : AbstractBlock) : String
        blockquote_tag(node) { %(<literallayout>#{node.content}</literallayout>) }
      end

      # --- Private helpers ---

      private def blockquote_tag(node : AbstractBlock, tag_name : String? = nil, &) : String
        start_tag = tag_name ? "<#{tag_name}" : "<blockquote"
        end_tag = tag_name ? "</#{tag_name}>" : "</blockquote>"
        result = [] of String
        result << %(#{start_tag}#{common_attributes(node.id, node.role, node.reftext)}>)
        result << %(<title>#{node.title}</title>) if node.title?
        if node.attr?("attribution") || node.attr?("citetitle")
          result << "<attribution>"
          result << (node.attr("attribution") || "") if node.attr?("attribution")
          result << %(<citetitle>#{node.attr("citetitle")}</citetitle>) if node.attr?("citetitle")
          result << "</attribution>"
        end
        result << yield
        result << end_tag
        result.join("\n")
      end

      private def common_attributes(id : String?, role : String? = nil, reftext : String? = nil) : String
        attrs = if id
                  %( xml:id="#{id}"#{role ? %( role="#{role}") : ""})
                elsif role
                  %( role="#{role}")
                else
                  ""
                end
        if reftext
          clean_reftext = reftext.gsub(/<[^>]+>/, "").squeeze(' ').strip
          clean_reftext = clean_reftext.gsub('"', "&quot;") if clean_reftext.includes?('"')
          %(#{attrs} xreflabel="#{clean_reftext}")
        else
          attrs
        end
      end

      private def document_info_tag(doc : Document) : String
        result = ["<info>"]
        unless doc.noheader
          dt = doc.doctitle({:use_fallback => true}) || "Untitled"
          result << %(<title>#{dt}</title>)
        end
        if (date = doc.attr("revdate") || doc.attr("docdate"))
          result << %(<date>#{date}</date>)
        end
        result << "</info>"
        result.join("\n")
      end

      private def enclose_content(node : AbstractBlock) : String
        node.content_model == ContentModel::Compound ? node.content.to_s : %(<simpara>#{node.content}</simpara>)
      end

      private def image_size_attributes(attributes : Hash(String, String)) : String
        if attributes.has_key?("scaledwidth")
          %( width="#{attributes["scaledwidth"]}")
        elsif attributes.has_key?("scale")
          %( scale="#{attributes["scale"]}")
        else
          width_attribute = attributes.has_key?("width") ? %( contentwidth="#{attributes["width"]}") : ""
          depth_attribute = attributes.has_key?("height") ? %( contentdepth="#{attributes["height"]}") : ""
          %(#{width_attribute}#{depth_attribute})
        end
      end

      private def title_tag(node : AbstractBlock, optional : Bool = true) : String
        !optional || node.title? ? %(<title>#{node.title}</title>\n) : ""
      end
    end
  end
end
