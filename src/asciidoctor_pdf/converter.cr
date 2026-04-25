require "crystal-asciidoctor/src/crystal-asciidoctor"
require "crystal-pdf/src/pdf"
require "crystal-flags/src/crystal_flags"
require "crystal-emojis-lite/src/crystal_emojis"
require "./inline_flags"

module AsciidoctorPDF
  # Convertisseur AsciiDoc → PDF pour crystal-asciidoctor.
  # Suit le pattern des convertisseurs crystal-asciidoctor (HTML5, DocBook5, ManPage).
  # S'enregistre sous le backend "pdf".
  class Converter < Asciidoctor::Converter::Base
    register_for "pdf"

    # Métadonnées de page pour les en-têtes/pieds de page
    record PageMeta, number : Int32, section_title : String

    # Entrée d'index
    record IndexEntry, term : String, page_number : Int32

    # Note de bas de page
    record FootnoteEntry, index : Int32, text : String, page_number : Int32

    # --- Polices ---
    # Les polices sont résolues au démarrage : si le thème définit des chemins TTF,
    # elles sont chargées ; sinon les polices Type1 standard sont utilisées.
    # Ceci permet de mesurer le texte et de rendre avec les mêmes polices.
    @font_body : PDF::Fonts::Base?
    @font_body_bold : PDF::Fonts::Base?
    @font_body_italic : PDF::Fonts::Base?
    @font_body_bold_italic : PDF::Fonts::Base?
    @font_mono : PDF::Fonts::Base?
    @font_mono_bold : PDF::Fonts::Base?
    @font_heading : PDF::Fonts::Base?

    # Noms de polices utilisés dans les appels page.font()
    @fn_body : String = "Helvetica"
    @fn_body_bold : String = "Helvetica-Bold"
    @fn_body_italic : String = "Helvetica-Oblique"
    @fn_body_bold_italic : String = "Helvetica-BoldOblique"
    @fn_mono : String = "Courier"
    @fn_mono_bold : String = "Courier-Bold"
    @fn_heading : String = "Helvetica-Bold"

    # --- État interne ---
    @doc : PDF::Document
    @theme : Theme
    @current_page : PDF::Page?
    @current_y : Float64 = 0.0
    @page_number : Int32 = 0
    @page_metas : Array(PageMeta) = [] of PageMeta
    @current_section_title : String = ""
    @document_title : String = ""
    @index_entries : Array(IndexEntry) = [] of IndexEntry
    # Entrées de la table des matières.
    # Chaque entrée capture {titre, niveau, page (1-based), nom de destination
    # PDF, coordonnée Y (PDF, repère bas-gauche) du haut du titre}. Le nom
    # de destination est unique dans le document et permet à la TOC ainsi
    # qu'à l'outline (bookmarks) de pointer précisément sur le début de la
    # section, pas seulement sur la page.
    @toc_entries : Array({String, Int32, Int32, String, Float64}) = [] of {String, Int32, Int32, String, Float64}
    # Compteur pour générer des noms de destination uniques quand la
    # section n'a pas d'id explicite côté AsciiDoc.
    @dest_counter : Int32 = 0
    @anchor_positions : Hash(String, Float64) = {} of String => Float64 # {id => y_position}
    @footnotes : Array(FootnoteEntry) = [] of FootnoteEntry             # notes de bas de page
    @footnotes_by_page : Hash(Int32, Array(FootnoteEntry)) = {} of Int32 => Array(FootnoteEntry)
    @output_path : String = "output.pdf"
    # Caractères hors WinAnsi déjà signalés à l'utilisateur pendant
    # cette conversion. On dédup pour ne pas spammer STDERR si un
    # même emoji apparaît N fois dans le source.
    @warned_chars : Set(Char) = Set(Char).new

    # Dimensions de la page (A4 par défaut)
    @page_width : Float64 = 595.28
    @page_height : Float64 = 841.89
    @margin : Float64 = 36.0
    @content_width : Float64 = 0.0

    def initialize(backend : String = "pdf", theme : Theme? = nil)
      super(backend)
      @theme = theme || Theme.new
      @doc = PDF::Document.new
      @backend_traits = Asciidoctor::Converter::BackendTraits.new(
        basebackend: "pdf",
        filetype: "pdf",
        outfilesuffix: ".pdf"
      )
      @margin = @theme.page_margin
      @content_width = @page_width - (2 * @margin)

      # Charger les polices TTF si définies dans le thème
      load_theme_fonts
    end

    # Point d'entrée principal : convertit le document et écrit le PDF
    def convert(node : Asciidoctor::AbstractNode, transform : String? = nil) : String
      transform ||= node.node_name
      dispatch(node, transform)
    end

    def dispatch(node : Asciidoctor::AbstractNode, transform : String) : String
      case transform
      when "document"         then convert_document(node)
      when "section"          then convert_section(node)
      when "paragraph"        then convert_paragraph(node)
      when "listing"          then convert_listing(node)
      when "literal"          then convert_literal(node)
      when "admonition"       then convert_admonition(node)
      when "ulist"            then convert_ulist(node)
      when "olist"            then convert_olist(node)
      when "dlist"            then convert_dlist(node)
      when "table"            then convert_table(node)
      when "image"            then convert_image(node)
      when "page_break"       then convert_page_break(node)
      when "thematic_break"   then convert_thematic_break(node)
      when "quote"            then convert_quote(node)
      when "verse"            then convert_verse(node)
      when "sidebar"          then convert_sidebar(node)
      when "example"          then convert_example(node)
      when "open"             then convert_open(node)
      when "preamble"         then convert_preamble(node)
      when "toc"              then "" # géré dans convert_document
      when "floating_title"   then convert_floating_title(node)
      when "inline_anchor"    then convert_inline_anchor(node)
      when "inline_break"     then ""
      when "inline_button"    then ""
      when "inline_callout"   then ""
      when "inline_footnote"  then convert_inline_footnote(node)
      when "inline_image"     then ""
      when "inline_indexterm" then convert_inline_indexterm(node)
      when "inline_kbd"       then ""
      when "inline_menu"      then ""
      when "inline_quoted"    then ""
      when "pass"             then ""
      when "stem"             then ""
      when "audio"            then ""
      when "video"            then ""
      when "colist"           then ""
      when "outline"          then ""
      when "embedded"         then convert_embedded(node)
      else                         ""
      end
    end

    # =========================================================================
    # Document
    # =========================================================================

    def convert_document(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Document)

      # Decode HTML entities in the document title once here so every
      # downstream renderer (title page, headers, PDF metadata, index
      # title, …) sees a plain-text title. NBSPs remain as U+00A0 so
      # `wrap_text` preserves the non-break property ; they become
      # ASCII spaces only just before each `page.text` call.
      @document_title = decode_html_entities(node.doctitle || "")
      @output_path = determine_output_path(node)

      # Métadonnées PDF
      @doc.title = @document_title unless @document_title.empty?
      @doc.author = node.attr("author") if node.attr?("author")
      @doc.subject = node.attr("subject") if node.attr?("subject")
      @doc.producer = "crystal-asciidoctor-pdf #{AsciidoctorPDF::VERSION}"

      # Page de titre
      if @theme.title_page_enabled && !@document_title.empty?
        render_title_page(node)
      end

      # Table des matières (page réservée, sera remplie après le rendu du contenu)
      toc_page_index = -1
      if @theme.toc_enabled && node.attr?("toc")
        toc_page_index = @page_number # index 0-based de la page TOC
        new_page
        # Créer une nouvelle page pour le contenu afin d'éviter que le corps
        # ne se superpose à la TOC (qui sera rendue en post-traitement)
        new_page
      end

      # Contenu principal
      node.blocks.each do |block|
        convert(block)
      end

      # Rendre la table des matières sur la page réservée
      if toc_page_index >= 0
        render_toc(toc_page_index)
      end

      # Générer la page d'index si activée et si des entrées ont été collectées
      if @theme.index_enabled && !@index_entries.empty?
        render_index
      end
      # Générer les bookmarks PDF (outline) à partir des entrées TOC
      generate_pdf_outline

      # Rendre les en-têtes et pieds de page sur toutes les pages
      render_headers_footers
      # Écrire le PDF
      write_pdf
      ""
    end

    def convert_embedded(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Document)
      node.blocks.each { |b| convert(b) }
      ""
    end

    # =========================================================================
    # Sections
    # =========================================================================

    def convert_section(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Section)

      level = node.level
      raw_title = node.title || ""
      # Strip HTML tags from the title (e.g., <code>Crystal</code> → Crystal)
      title = decode_html_entities(raw_title.gsub(/<[^>]+>/, ""))

      # Prepend section number when :sectnums: is enabled
      if node.numbered
        title = "#{node.sectnum} #{title}"
      end

      @current_section_title = title

      # Forge un nom de destination PDF stable et unique pour cette
      # section. Préfère l'id AsciiDoc (`[[anchor]]` ou auto-généré
      # par le parseur) s'il existe, sinon retombe sur un compteur.
      # Les noms PDF n'ont pas besoin d'être lisibles ; ils servent
      # juste de clé pour l'`Annot.link_dest` de la TOC et pour
      # l'outline.
      @dest_counter += 1
      dest_name = node.id || "_sect_#{@dest_counter}"

      ensure_page

      # Marge supérieure
      margin_top = @theme.heading_margin_top(level)
      @current_y -= margin_top if @current_y < (@page_height - @margin - margin_top)

      # Rendu du titre de section
      font_size = @theme.heading_font_size(level)
      heading_line_h = font_size * @theme.base_line_height

      # Découper le titre en lignes si il dépasse la largeur de contenu.
      # Sans ce wrapping, un titre long est rendu tronqué (le texte déborde
      # la page et le dernier mot est coupé).
      title_lines = wrap_text(title, @content_width, font_size, @fn_heading)
      heading_block_h = font_size + (title_lines.size - 1) * heading_line_h

      # Ensure heading is not orphaned: require room for the whole heading
      # plus at least 4 lines of body text below it.
      min_content_below = @theme.base_font_size * @theme.base_line_height * 4
      check_page_break(heading_block_h + @theme.heading_margin_bottom(level) + min_content_below)

      # Acquérir la page après check_page_break (qui peut créer une nouvelle page).
      # On enregistre l'entrée TOC ici (et non avant `check_page_break`) pour
      # que le numéro de page reflète bien la page sur laquelle le titre
      # va effectivement être dessiné — sinon une section qui déborde
      # apparaîtrait dans la TOC avec le numéro de la page précédente.
      page = @current_page.not_nil!

      # Crée une destination nommée pointant sur le haut du titre. La TOC
      # et l'outline (bookmarks) y feront référence pour amener le lecteur
      # exactement sur le titre — pas juste « quelque part » sur la page.
      # Petit padding au-dessus pour ne pas coller le scroll au sommet.
      top_y = @current_y + 4.0
      @doc.add_dest(dest_name, PDF::Destination.xyz(page.page_reference, top: top_y))

      @toc_entries << {title, level, @page_number, dest_name, top_y}

      set_font(page, @fn_heading, font_size)
      page.fill_color(@theme.heading_font_color)

      y = @current_y - font_size
      title_lines.each_with_index do |line, idx|
        page.text(line, at: {@margin, y})
        y -= heading_line_h unless idx == title_lines.size - 1
      end
      @current_y -= heading_block_h + @theme.heading_margin_bottom(level)

      # Ligne de séparation pour h1 et h2
      if level <= 2
        page.stroke_color("cccccc")
        page.line_width(0.5)
        page.line({@margin, @current_y}, {@margin + @content_width, @current_y})
        page.stroke
        @current_y -= 4.0
      end

      # Rendu des blocs enfants
      node.blocks.each { |b| convert(b) }
      ""
    end

    # =========================================================================
    # Paragraphes
    # =========================================================================

    def convert_paragraph(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)

      ensure_page
      html = node.content || ""
      return "" if html.empty?

      font_size = @theme.base_font_size
      line_height = @theme.base_line_height
      line_h = font_size * line_height

      # Découper le HTML en lignes de texte brut pour le calcul de la hauteur
      plain = strip_inline_markup(html)
      lines = wrap_text(plain, @content_width, font_size)
      total_h = lines.size * line_h + @theme.prose_margin_bottom

      check_page_break(total_h)

      page = @current_page.not_nil!

      # Rendre chaque ligne avec le markup inline
      render_inline_lines(page, html, @margin, @content_width, font_size, line_h)
      @current_y -= @theme.prose_margin_bottom
      ""
    end

    # =========================================================================
    # Blocs de code (listing, literal)
    # =========================================================================

    def convert_listing(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      render_code_block(node)
    end

    def convert_literal(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      render_code_block(node)
    end

    private def render_code_block(node : Asciidoctor::Block) : String
      ensure_page

      source = node.source
      language = node.attr("language") || ""
      lines = source.split("\n")
      font_size = @theme.code_font_size
      line_h = font_size * 1.4
      padding = @theme.code_padding
      highlight = @theme.code_highlight_enabled && !language.empty?
      bottom_limit = @margin + 20.0

      total_h = lines.size * line_h + (2 * padding) + @theme.code_margin_top + @theme.code_margin_bottom

      # If the whole block fits on the current page, use the simple path
      if @current_y - total_h >= bottom_limit
        render_code_block_simple(lines, language, font_size, line_h, padding, highlight)
      else
        # Split the code block across pages
        render_code_block_paginated(lines, language, font_size, line_h, padding, highlight, bottom_limit)
      end

      ""
    end

    # Render a code block that fits entirely on the current page.
    private def render_code_block_simple(lines : Array(String), language : String, font_size : Float64, line_h : Float64, padding : Float64, highlight : Bool) : Nil
      check_page_break(lines.size * line_h + (2 * padding) + @theme.code_margin_top + @theme.code_margin_bottom)
      page = @current_page.not_nil!
      @current_y -= @theme.code_margin_top

      block_h = lines.size * line_h + (2 * padding)
      draw_code_block_background(page, @current_y, block_h)
      draw_code_language_label(page, language, font_size, padding)

      y = @current_y - padding - font_size
      lines.each do |line|
        render_code_line(page, line, y, font_size, padding, highlight, language)
        y -= line_h
      end

      @current_y -= block_h + @theme.code_margin_bottom
    end

    # Render a code block that may span multiple pages.
    private def render_code_block_paginated(lines : Array(String), language : String, font_size : Float64, line_h : Float64, padding : Float64, highlight : Bool, bottom_limit : Float64) : Nil
      # Start a new page if the current page can't even fit a few lines
      min_first_chunk = padding + font_size + 3 * line_h + padding + @theme.code_margin_top
      check_page_break(min_first_chunk)

      page = @current_page.not_nil!
      @current_y -= @theme.code_margin_top

      line_idx = 0
      first_chunk = true

      while line_idx < lines.size
        page = @current_page.not_nil!

        # Calculate how many lines fit on the current page
        available_h = @current_y - bottom_limit - (2 * padding)
        max_lines = (available_h / line_h).to_i
        max_lines = 1 if max_lines < 1

        chunk_lines = lines[line_idx, [max_lines, lines.size - line_idx].min]
        chunk_block_h = chunk_lines.size * line_h + (2 * padding)

        # Draw background & border for this chunk
        draw_code_block_background(page, @current_y, chunk_block_h)

        # Language label only on the first chunk
        if first_chunk
          draw_code_language_label(page, language, font_size, padding)
          first_chunk = false
        end

        # Render lines
        y = @current_y - padding - font_size
        chunk_lines.each do |line|
          render_code_line(page, line, y, font_size, padding, highlight, language)
          y -= line_h
        end

        line_idx += chunk_lines.size
        @current_y -= chunk_block_h

        # If there are more lines, move to a new page
        if line_idx < lines.size
          new_page
        end
      end

      @current_y -= @theme.code_margin_bottom
    end

    # Draw code block background rectangle and border.
    private def draw_code_block_background(page : PDF::Page, top_y : Float64, block_h : Float64) : Nil
      page.fill_color(@theme.code_background_color)
      page.rectangle(@margin, top_y - block_h, @content_width, block_h)
      page.fill

      page.stroke_color(@theme.code_border_color)
      page.line_width(@theme.code_border_width)
      page.rectangle(@margin, top_y - block_h, @content_width, block_h)
      page.stroke
    end

    # Draw the language indicator label in the top-right corner.
    private def draw_code_language_label(page : PDF::Page, language : String, font_size : Float64, padding : Float64) : Nil
      return if language.empty?
      set_font(page, @fn_body, font_size * 0.75)
      page.fill_color("888888")
      lang_x = @margin + @content_width - text_width(language, @fn_body, font_size * 0.75) - padding
      page.text(language, at: {lang_x, @current_y - font_size * 0.75})
    end

    # Render a single line of code text.
    private def render_code_line(page : PDF::Page, line : String, y : Float64, font_size : Float64, padding : Float64, highlight : Bool, language : String) : Nil
      if highlight
        tokens = SyntaxHighlighter.tokenize(line, language)
        x = @margin + padding
        tokens.each do |token|
          set_font(page, @fn_mono, font_size)
          page.fill_color(token.color)
          page.text(token.text, at: {x, y})
          x += text_width(token.text, @fn_mono, font_size)
        end
      else
        set_font(page, @fn_mono, font_size)
        page.fill_color(@theme.code_font_color)
        page.text(line, at: {@margin + padding, y})
      end
    end

    # =========================================================================
    # Admonitions
    # =========================================================================

    def convert_admonition(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)

      ensure_page
      name = node.attr("name") || "note"
      text = node.content || ""
      text = strip_inline_markup(text)

      border_color = case name.downcase
                     when "tip"       then @theme.admonition_tip_color
                     when "warning"   then @theme.admonition_warning_color
                     when "caution"   then @theme.admonition_caution_color
                     when "important" then @theme.admonition_important_color
                     else                  @theme.admonition_note_color
                     end

      font_size = @theme.base_font_size
      line_h = font_size * @theme.base_line_height
      padding = @theme.admonition_padding

      # Espace réservé au label (NOTE, TIP, IMPORTANT, WARNING, CAUTION) :
      # au minimum 60pt pour aligner les labels entre admonitions, plus si
      # le texte du label mesuré est plus long (évite qu'il mange le début
      # du texte de l'admonition).
      label_text = name.upcase
      label_size = font_size - 1
      label_offset = @theme.admonition_border_width + 4.0
      label_gap = 8.0
      label_space = [60.0, label_offset + text_width(label_text, @fn_body_bold, label_size) + label_gap].max
      content_w = @content_width - label_space - padding

      lines = wrap_text(text, content_w, font_size)
      block_h = [lines.size * line_h + (2 * padding), font_size * 2 + (2 * padding)].max
      total_h = block_h + @theme.admonition_margin_top + @theme.admonition_margin_bottom

      check_page_break(total_h)

      page = @current_page.not_nil!
      @current_y -= @theme.admonition_margin_top

      # Bande de couleur à gauche
      page.fill_color(border_color)
      page.rectangle(@margin, @current_y - block_h, @theme.admonition_border_width, block_h)
      page.fill

      # Label (NOTE, TIP, etc.)
      set_font(page, @fn_body_bold, label_size)
      page.fill_color(border_color)
      page.text(label_text, at: {@margin + label_offset, @current_y - padding - font_size})

      # Texte de l'admonition
      set_font(page, @fn_body, font_size)
      page.fill_color(@theme.base_font_color)

      y = @current_y - padding - font_size
      lines.each do |line|
        draw_text_run(page, line, @margin + label_space, y, @fn_body, font_size)
        y -= line_h
      end

      @current_y -= block_h + @theme.admonition_margin_bottom
      ""
    end

    # =========================================================================
    # Listes
    # =========================================================================

    def convert_ulist(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::List)
      render_list(node, ordered: false)
    end

    def convert_olist(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::List)
      render_list(node, ordered: true)
    end

    def convert_dlist(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::List)
      # Liste de définitions : terme :: définition
      node.items.each_with_index do |item, _idx|
        next unless item.is_a?(Asciidoctor::ListItem)
        ensure_page
        page = @current_page.not_nil!
        term = strip_inline_markup(item.text || "")
        set_font(page, @fn_body_bold, @theme.base_font_size)
        page.fill_color(@theme.base_font_color)
        draw_text_run(page, term, @margin, @current_y - @theme.base_font_size, @fn_body_bold, @theme.base_font_size)
        @current_y -= @theme.base_font_size * @theme.base_line_height

        if item.blocks?
          item.blocks.each { |b| convert(b) }
        end
      end
      ""
    end

    private def render_list(node : Asciidoctor::List, ordered : Bool, indent : Float64 = 0.0) : String
      node.items.each_with_index do |item, idx|
        next unless item.is_a?(Asciidoctor::ListItem)
        ensure_page

        text = strip_inline_markup(item.text || "")
        font_size = @theme.base_font_size
        line_h = font_size * @theme.base_line_height
        content_w = @content_width - @theme.list_indent - indent

        lines = wrap_text(text, content_w, font_size)
        total_h = lines.size * line_h + @theme.list_item_spacing
        check_page_break(total_h)

        page = @current_page.not_nil!
        marker = ordered ? "#{idx + 1}." : "•"
        x_marker = @margin + indent
        x_text = x_marker + @theme.list_indent

        set_font(page, @fn_body, font_size)
        page.fill_color(@theme.list_marker_color)
        page.text(marker, at: {x_marker, @current_y - font_size})

        page.fill_color(@theme.base_font_color)
        lines.each do |line|
          draw_text_run(page, line, x_text, @current_y - font_size, @fn_body, font_size)
          @current_y -= line_h
        end
        @current_y -= @theme.list_item_spacing

        # Sous-listes
        item.blocks.each do |sub_block|
          if sub_block.is_a?(Asciidoctor::List)
            render_list(sub_block, ordered: sub_block.context == :olist, indent: indent + @theme.list_indent)
          end
        end
      end
      ""
    end

    # =========================================================================
    # Tableaux
    # =========================================================================

    def convert_table(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Table)

      ensure_page
      @current_y -= @theme.table_margin_top

      col_count = node.columns.size
      return "" if col_count == 0

      # Calculer les largeurs de colonnes proportionnelles (via colpcwidth)
      col_widths = node.columns.map do |col|
        pcw = col.attr("colpcwidth")
        pcw ? (pcw.to_f / 100.0 * @content_width) : (@content_width / col_count)
      end

      font_size = @theme.base_font_size
      padding = @theme.table_cell_padding
      line_h = font_size * @theme.base_line_height

      page = @current_page.not_nil!

      # Titre du tableau (caption)
      if (caption = node.title) && !caption.empty?
        set_font(page, @fn_body, font_size - 1)
        page.fill_color("888888")
        draw_text_run(page, caption, @margin, @current_y - (font_size - 1), @fn_body, font_size - 1)
        @current_y -= (font_size - 1) * 1.4
      end

      # En-têtes
      if node.has_header_option
        node.rows.head.each do |row|
          # Pre-calculate wrapped lines for each cell to determine row height
          cell_lines = row.map_with_index do |cell, ci|
            cw = col_widths[ci]? || (@content_width / col_count)
            text = strip_inline_markup(cell.text || "")
            wrap_text(text, cw - 2 * padding, font_size, @fn_body_bold)
          end
          max_lines = cell_lines.max_of(&.size)
          row_h = (max_lines * line_h) + (2 * padding)

          check_page_break(row_h)
          page = @current_page.not_nil!
          x = @margin

          row.each_with_index do |cell, ci|
            cw = col_widths[ci]? || (@content_width / col_count)
            page.fill_color(@theme.table_header_background_color)
            page.rectangle(x, @current_y - row_h, cw, row_h)
            page.fill

            page.stroke_color(@theme.table_border_color)
            page.line_width(@theme.table_border_width)
            page.rectangle(x, @current_y - row_h, cw, row_h)
            page.stroke

            set_font(page, @fn_body_bold, font_size)
            page.fill_color(@theme.table_header_font_color)
            lines = cell_lines[ci]
            halign = cell.attr("halign") || "left"
            lines.each_with_index do |line, li|
              tw = text_width(line, @fn_body_bold, font_size)
              tx = case halign
                   when "center" then x + (cw - tw) / 2
                   when "right"  then x + cw - tw - padding
                   else               x + padding
                   end
              draw_text_run(page, line, tx, @current_y - padding - font_size - (li * line_h), @fn_body_bold, font_size)
            end
            x += cw
          end
          @current_y -= row_h
        end
      end

      # Corps du tableau avec alternance de couleurs
      row_idx = 0
      node.rows.body.each do |row|
        # Pre-calculate wrapped lines for each cell to determine row height
        cell_lines = row.map_with_index do |cell, ci|
          cw = col_widths[ci]? || (@content_width / col_count)
          text = strip_inline_markup(cell.text || "")
          wrap_text(text, cw - 2 * padding, font_size, @fn_body)
        end
        max_lines = cell_lines.max_of(&.size)
        row_h = (max_lines * line_h) + (2 * padding)

        check_page_break(row_h)
        page = @current_page.not_nil!
        x = @margin
        bg_color = (row_idx % 2 == 1) ? @theme.table_row_alt_background_color : nil

        row.each_with_index do |cell, ci|
          cw = col_widths[ci]? || (@content_width / col_count)

          # Fond alterné
          if bg_color
            page.fill_color(bg_color)
            page.rectangle(x, @current_y - row_h, cw, row_h)
            page.fill
          end

          page.stroke_color(@theme.table_border_color)
          page.line_width(@theme.table_border_width)
          page.rectangle(x, @current_y - row_h, cw, row_h)
          page.stroke

          set_font(page, @fn_body, font_size)
          page.fill_color(@theme.base_font_color)
          lines = cell_lines[ci]
          halign = cell.attr("halign") || "left"
          lines.each_with_index do |line, li|
            tw = text_width(line, @fn_body, font_size)
            tx = case halign
                 when "center" then x + (cw - tw) / 2
                 when "right"  then x + cw - tw - padding
                 else               x + padding
                 end
            draw_text_run(page, line, tx, @current_y - padding - font_size - (li * line_h), @fn_body, font_size)
          end
          x += cw
        end
        @current_y -= row_h
        row_idx += 1
      end

      # Pied de tableau
      unless node.rows.foot.empty?
        node.rows.foot.each do |row|
          # Pre-calculate wrapped lines for each cell to determine row height
          cell_lines = row.map_with_index do |cell, ci|
            cw = col_widths[ci]? || (@content_width / col_count)
            text = strip_inline_markup(cell.text || "")
            wrap_text(text, cw - 2 * padding, font_size, @fn_body_bold)
          end
          max_lines = cell_lines.max_of(&.size)
          row_h = (max_lines * line_h) + (2 * padding)

          check_page_break(row_h)
          page = @current_page.not_nil!
          x = @margin
          row.each_with_index do |cell, ci|
            cw = col_widths[ci]? || (@content_width / col_count)
            page.fill_color(@theme.table_footer_background_color)
            page.rectangle(x, @current_y - row_h, cw, row_h)
            page.fill

            page.stroke_color(@theme.table_border_color)
            page.line_width(@theme.table_border_width)
            page.rectangle(x, @current_y - row_h, cw, row_h)
            page.stroke

            set_font(page, @fn_body_bold, font_size)
            page.fill_color(@theme.base_font_color)
            lines = cell_lines[ci]
            lines.each_with_index do |line, li|
              page.text(line, at: {x + padding, @current_y - padding - font_size - (li * line_h)})
            end
            x += cw
          end
          @current_y -= row_h
        end
      end

      @current_y -= @theme.table_margin_bottom
      ""
    end

    # =========================================================================
    # Images
    # =========================================================================

    def convert_image(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)

      target = node.attr("target") || ""
      return "" if target.empty?

      ensure_page
      alt = node.attr("alt") || target
      width_attr = node.attr("width")
      height_attr = node.attr("height")

      image_path = resolve_image_path(node, target)

      if image_path && File.exists?(image_path)
        begin
          img = PDF::Images::Image.load(image_path)

          max_w = @content_width
          display_w = width_attr ? [width_attr.to_f, max_w].min : [img.width.to_f, max_w].min
          ratio = display_w / img.width.to_f
          display_h = height_attr ? height_attr.to_f : img.height.to_f * ratio

          check_page_break(display_h + 8.0)
          page = @current_page.not_nil!

          align = node.attr("align") || "left"
          x = case align
              when "center" then @margin + (@content_width - display_w) / 2
              when "right"  then @margin + @content_width - display_w
              else               @margin
              end

          page.image(img, at: {x, @current_y}, width: display_w)
          @current_y -= display_h + 8.0
        rescue
          render_image_placeholder(alt)
        end
      else
        render_image_placeholder(alt)
      end
      ""
    end

    private def resolve_image_path(node : Asciidoctor::Block, target : String) : String?
      return nil if target.empty?
      return target if File.exists?(target)
      if (docdir = node.document.attr("docdir"))
        candidate = File.join(docdir, target)
        return candidate if File.exists?(candidate)
        candidate2 = File.join(docdir, "images", target)
        return candidate2 if File.exists?(candidate2)
      end
      nil
    end

    private def render_image_placeholder(alt : String) : Nil
      ensure_page
      page = @current_page.not_nil!
      block_h = 40.0
      @current_y -= 8.0
      page.stroke_color("cccccc")
      page.line_width(0.5)
      page.rectangle(@margin, @current_y - block_h, @content_width, block_h)
      page.stroke
      set_font(page, @fn_body, @theme.base_font_size - 1)
      page.fill_color("888888")
      page.text("[Image: #{alt}]", at: {@margin + 8.0, @current_y - 24.0})
      @current_y -= block_h + 8.0
    end

    # =========================================================================
    # Sauts de page et séparateurs
    # =========================================================================

    def convert_page_break(node : Asciidoctor::AbstractNode) : String
      new_page
      ""
    end

    def convert_thematic_break(node : Asciidoctor::AbstractNode) : String
      ensure_page
      page = @current_page.not_nil!
      @current_y -= 8.0
      page.stroke_color("cccccc")
      page.line_width(1.0)
      page.line({@margin, @current_y}, {@margin + @content_width, @current_y})
      page.stroke
      @current_y -= 8.0
      ""
    end

    # =========================================================================
    # Blocs de citation, verse, sidebar, example, open, preamble
    # =========================================================================

    def convert_quote(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      ensure_page
      render_indented_block(node, left_bar_color: "aaaaaa", indent: 16.0)
    end

    def convert_verse(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      ensure_page
      render_indented_block(node, left_bar_color: "aaaaaa", indent: 16.0)
    end

    def convert_sidebar(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      ensure_page
      node.blocks.each { |b| convert(b) }
      ""
    end

    def convert_example(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      ensure_page
      node.blocks.each { |b| convert(b) }
      ""
    end

    def convert_open(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      node.blocks.each { |b| convert(b) }
      ""
    end

    def convert_preamble(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      node.blocks.each { |b| convert(b) }
      ""
    end

    def convert_floating_title(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Block)
      ensure_page
      level = node.level
      title = node.title || ""
      font_size = @theme.heading_font_size(level)
      check_page_break(font_size + 8.0)
      page = @current_page.not_nil!
      set_font(page, @fn_body_bold, font_size)
      page.fill_color(@theme.heading_font_color)
      draw_text_run(page, title, @margin, @current_y - font_size, @fn_body_bold, font_size)
      @current_y -= font_size + 6.0
      ""
    end

    def convert_inline_indexterm(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Inline)
      term = node.text || ""
      @index_entries << IndexEntry.new(term, @page_number) unless term.empty?
      ""
    end

    # Gestion des notes de bas de page
    # Les notes sont collectées pendant le rendu, puis affichées en bas de chaque page.
    def convert_inline_footnote(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Inline)
      index_str = node.attr("index")
      index = index_str ? index_str.to_i : (@footnotes.size + 1)
      text = node.text || ""
      return "" if text.empty? && node.type == :xref

      # Enregistrer la note
      entry = FootnoteEntry.new(index, text, @page_number)
      @footnotes << entry
      (@footnotes_by_page[@page_number] ||= [] of FootnoteEntry) << entry

      # Afficher le numéro de note en exposant dans le texte courant
      ensure_page
      page = @current_page.not_nil!
      font_size = @theme.base_font_size * 0.7
      set_font(page, @fn_body, font_size)
      page.fill_color("0645ad")
      page.text("[#{index}]", at: {@margin, @current_y - @theme.base_font_size})
      page.fill_color(@theme.base_font_color)
      ""
    end

    # Rend les notes de bas de page pour une page donnée.
    # Appelé après le rendu de chaque page.
    private def render_page_footnotes(page : PDF::Page, page_num : Int32) : Nil
      notes = @footnotes_by_page[page_num]?
      return unless notes && !notes.empty?

      font_size = @theme.base_font_size * 0.8
      line_h = font_size * 1.3
      separator_y = @margin + @theme.footer_height + notes.size * line_h + 8.0

      # Ligne de séparation
      page.stroke_color("cccccc")
      page.line_width(0.5)
      page.line({@margin, separator_y}, {@margin + @content_width / 3, separator_y})
      page.stroke

      y = separator_y - 4.0
      notes.each do |note|
        set_font(page, @fn_body, font_size)
        page.fill_color(@theme.base_font_color)
        page.text("[#{note.index}] #{note.text}", at: {@margin, y - font_size})
        y -= line_h
      end
    end

    # Gestion des liens et références internes (XRefs)
    # Les liens sont rendus en couleur bleue soulignée dans le PDF.
    # Pour les références internes, le texte de la référence est affiché entre crochets.
    def convert_inline_anchor(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Inline)
      case node.type
      when :xref
        # Référence interne : afficher le texte ou l'id entre crochets
        reftext = node.text || node.attr("refid") || node.target || ""
        ensure_page
        page = @current_page.not_nil!
        font_size = @theme.base_font_size
        set_font(page, @fn_body, font_size)
        page.fill_color("0645ad")
        page.text("[» #{reftext}]", at: {@margin, @current_y - font_size})
        page.fill_color(@theme.base_font_color)
        @current_y -= font_size * @theme.base_line_height
      when :link
        # Lien externe : afficher le texte du lien en bleu avec annotation cliquable
        link_text = node.text || node.target || ""
        target = node.target || ""
        ensure_page
        page = @current_page.not_nil!
        font_size = @theme.base_font_size
        set_font(page, @fn_body, font_size)
        page.fill_color("0645ad")
        display = link_text.empty? ? target : link_text
        text_y = @current_y - font_size
        page.text(display, at: {@margin, text_y})

        # Annotation lien URI cliquable
        unless target.empty?
          tw = text_width(display, @fn_body, font_size)
          page.link_uri(rect: {@margin, text_y - 2, @margin + tw, text_y + font_size}, uri: target)
        end

        page.fill_color(@theme.base_font_color)
        @current_y -= font_size * @theme.base_line_height
      when :ref
        # Ancre de destination : enregistrer la position pour les XRefs
        @anchor_positions[node.id || ""] = @current_y if node.id
      when :bibref
        # Référence bibliographique
        id = node.id || ""
        reftext = node.reftext || id
        ensure_page
        page = @current_page.not_nil!
        font_size = @theme.base_font_size
        set_font(page, @fn_body, font_size)
        page.fill_color(@theme.base_font_color)
        page.text("[#{reftext}]", at: {@margin, @current_y - font_size})
        @current_y -= font_size * @theme.base_line_height
      end
      ""
    end

    # =========================================================================
    # Helpers de rendu
    # =========================================================================

    private def render_indented_block(node : Asciidoctor::Block, left_bar_color : String, indent : Float64) : String
      text = node.content || ""
      text = strip_inline_markup(text)
      font_size = @theme.base_font_size
      line_h = font_size * @theme.base_line_height
      content_w = @content_width - indent - 8.0

      lines = wrap_text(text, content_w, font_size)
      block_h = lines.size * line_h + 8.0

      check_page_break(block_h + 12.0)

      page = @current_page.not_nil!
      @current_y -= 6.0

      # Barre de couleur à gauche
      page.fill_color(left_bar_color)
      page.rectangle(@margin, @current_y - block_h, 3.0, block_h)
      page.fill

      # Texte en italique
      set_font(page, @fn_body_italic, font_size)
      page.fill_color(@theme.base_font_color)

      y = @current_y - font_size
      lines.each do |line|
        page.text(line, at: {@margin + indent, y})
        y -= line_h
      end

      @current_y -= block_h + 6.0

      # Attribution
      if (attribution = node.attr("attribution"))
        set_font(page, @fn_body, font_size - 1)
        page.fill_color("555555")
        page.text("— #{attribution}", at: {@margin + indent, @current_y - font_size})
        @current_y -= font_size + 4.0
      end
      ""
    end

    # =========================================================================
    # Index
    # =========================================================================
    # Rend la page d'index alphabétique à la fin du document.
    # Les entrées sont groupées par lettre initiale et affichées sur plusieurs colonnes.
    private def render_index : Nil
      return if @index_entries.empty?

      # Créer une nouvelle page pour l'index
      new_page
      page = @current_page.not_nil!

      font_size = @theme.index_font_size
      line_h = font_size * 1.5
      col_count = @theme.index_columns.clamp(1, 4)
      col_width = @content_width / col_count
      col_gap = 8.0
      entry_w = col_width - col_gap

      # Titre de l'index
      title_font_size = font_size + 6.0
      set_font(page, @fn_body_bold, title_font_size)
      page.fill_color(@theme.heading_font_color)
      page.text(@theme.index_title, at: {@margin, @page_height - @margin - title_font_size})
      y_start = @page_height - @margin - title_font_size * 2.0

      # Regrouper et trier les entrées
      # Structure : Hash(String, Hash(String, Array(Int32)))
      # lettre => terme => [pages]
      grouped = {} of String => Hash(String, Array(Int32))

      @index_entries.each do |entry|
        term = entry.term.strip
        next if term.empty?
        # Gestion des sous-termes (séparés par virgule : "terme principal, sous-terme")
        parts = term.split(",", 2).map(&.strip)
        primary = parts[0]
        secondary = parts[1]?
        letter = primary[0..0].upcase
        grouped[letter] ||= {} of String => Array(Int32)
        key = secondary ? "#{primary}\t#{secondary}" : primary
        grouped[letter][key] ||= [] of Int32
        grouped[letter][key] << entry.page_number unless grouped[letter][key].includes?(entry.page_number)
      end

      # Trier les lettres et les termes
      sorted_letters = grouped.keys.sort

      # Construire la liste aplatie des lignes à rendre
      # Chaque ligne est un tuple {type, text, pages}
      # type : :letter (en-tête de lettre), :primary, :secondary
      lines = [] of {Symbol, String, Array(Int32)}
      sorted_letters.each do |letter|
        lines << {:letter, letter, [] of Int32}
        sorted_terms = grouped[letter].keys.sort
        sorted_terms.each do |key|
          pages = grouped[letter][key].sort.uniq
          if key.includes?("\t")
            parts = key.split("\t", 2)
            lines << {:primary, parts[0], [] of Int32}
            lines << {:secondary, parts[1], pages}
          else
            lines << {:primary, key, pages}
          end
        end
      end

      # Rendre les lignes en colonnes
      col_idx = 0
      x = @margin + col_idx * col_width
      y = y_start

      lines.each do |type, text, pages|
        # Saut de colonne si nécessaire
        if y < @margin + line_h
          col_idx += 1
          if col_idx >= col_count
            # Nouvelle page
            new_page
            page = @current_page.not_nil!
            col_idx = 0
            y = @page_height - @margin
          else
            y = y_start
          end
          x = @margin + col_idx * col_width
        end

        case type
        when :letter
          # En-tête de lettre (ex. : "A")
          set_font(page, @fn_body_bold, font_size + 1.0)
          page.fill_color(@theme.heading_font_color)
          page.text(text, at: {x, y - (font_size + 1.0)})
          y -= (font_size + 1.0) * 1.8
        when :primary
          # Terme principal
          set_font(page, @fn_body, font_size)
          page.fill_color(@theme.base_font_color)
          entry_text = text
          unless pages.empty?
            page_str = pages.map(&.to_s).join(", ")
            page_str_w = text_width(page_str, @fn_body, font_size)
            # Texte du terme
            page.text(entry_text, at: {x, y - font_size})
            # Numéros de page alignés à droite
            page.fill_color(@theme.index_page_number_color)
            page.text(page_str, at: {x + entry_w - page_str_w, y - font_size})
            page.fill_color(@theme.base_font_color)
          else
            page.text(entry_text, at: {x, y - font_size})
          end
          y -= line_h
        when :secondary
          # Sous-terme (indenté)
          set_font(page, @fn_body, font_size - 0.5)
          page.fill_color(@theme.base_font_color)
          indent = 10.0
          entry_text = text
          page.text(entry_text, at: {x + indent, y - (font_size - 0.5)})
          unless pages.empty?
            page_str = pages.map(&.to_s).join(", ")
            page_str_w = text_width(page_str, @fn_body, font_size - 0.5)
            page.fill_color(@theme.index_page_number_color)
            page.text(page_str, at: {x + entry_w - page_str_w, y - (font_size - 0.5)})
            page.fill_color(@theme.base_font_color)
          end
          y -= line_h * 0.9
        end
      end
    end

    # Table des matières
    # =========================================================================
    # Rend la table des matières sur la page réservée (index 0-based).
    # La TOC est rendue après le contenu principal pour avoir les numéros de page corrects.
    private def render_toc(page_index : Int32) : Nil
      return if @toc_entries.empty?
      return if page_index < 0 || page_index >= @doc.pages.size

      page = @doc.pages[page_index]
      y = @page_height - @margin
      font_size = @theme.toc_font_size
      # Espacement entre les entrées : au moins 1.5x la taille de police
      line_h = font_size * 1.8
      dot_color = @theme.toc_dot_leader_color
      text_color = @theme.base_font_color

      # Titre de la TOC
      toc_title_size = font_size + 6.0
      set_font(page, @fn_body_bold, toc_title_size)
      page.fill_color(@theme.heading_font_color)
      page.text(@theme.toc_title, at: {@margin, y - toc_title_size})
      y -= toc_title_size * 2.0

      # Entrées de la TOC
      @toc_entries.each do |entry|
        raw_title, level, page_num, dest_name, _top_y = entry
        title = decode_html_entities(raw_title)
        # Indentation : niveau 1 = 0, niveau 2 = 20pt, niveau 3 = 40pt, etc.
        indent = (level - 1) * 20.0
        entry_x = @margin + indent
        entry_w = @content_width - indent

        # Vérifier qu'il reste de la place sur la page
        if y - line_h < @margin
          # La TOC déborde sur une seule page — on s'arrête ici.
          # (Un support multi-page de la TOC pourrait être ajouté ultérieurement.)
          break
        end

        # Texte du titre
        toc_font_name = level <= 1 ? @fn_body_bold : @fn_body
        set_font(page, toc_font_name, font_size)
        page.fill_color(text_color)
        draw_text_run(page, title, entry_x, y - font_size, toc_font_name, font_size)

        # Numéro de page (aligné à droite)
        page_str = page_num.to_s
        page_num_w = text_width(page_str, toc_font_name, font_size)
        page.fill_color(text_color)
        page.text(page_str, at: {@margin + @content_width - page_num_w, y - font_size})

        # Annotation Link : toute la ligne (titre + dots + numéro) est
        # cliquable et navigue vers la destination nommée enregistrée
        # par `convert_section`. Le rectangle est exprimé dans le
        # repère PDF (origine en bas à gauche).
        rect_top = y + 2.0
        rect_bottom = y - font_size - 2.0
        rect_right = @margin + @content_width
        page.link_dest(
          rect: {entry_x, rect_bottom, rect_right, rect_top},
          dest: dest_name,
        )

        # Pointillés entre le titre et le numéro de page
        title_w = text_width(title, toc_font_name, font_size)
        dot_x_start = entry_x + title_w + 4.0
        dot_x_end = @margin + @content_width - page_num_w - 4.0
        if dot_x_end > dot_x_start
          page.fill_color(dot_color)
          dot_spacing = font_size * 0.5
          dot_x = dot_x_start
          while dot_x < dot_x_end
            page.text(".", at: {dot_x, y - font_size})
            dot_x += dot_spacing
          end
        end

        y -= line_h
      end
    end

    # =========================================================================
    # Page de titre
    # =========================================================================

    private def render_title_page(doc : Asciidoctor::Document) : Nil
      new_page
      page = @current_page.not_nil!
      center_x = @page_width / 2

      # Titre principal — wrap long titles to fit within the page width.
      # Use `@document_title` (already decoded) so HTML entities like
      # `&#160;` don't leak through as literal text.
      title = @document_title
      title_font_size = @theme.title_font_size
      set_font(page, @fn_body_bold, title_font_size)
      page.fill_color(@theme.title_font_color)
      title_y = @page_height * 0.55

      # Wrap the title into multiple lines if it exceeds the content width
      title_lines = wrap_text(title, @content_width, title_font_size, @fn_body_bold)
      title_line_height = title_font_size * 1.3
      title_lines.each_with_index do |line, i|
        draw_text_run(page, line, @margin, title_y - (i * title_line_height), @fn_body_bold, title_font_size)
      end
      title_total_height = title_lines.size * title_line_height

      # Sous-titre
      if (subtitle = doc.attr("subtitle"))
        set_font(page, @fn_body, @theme.subtitle_font_size)
        page.fill_color(@theme.subtitle_font_color)
        draw_text_run(page, decode_html_entities(subtitle), @margin, title_y - title_total_height - 10.0, @fn_body, @theme.subtitle_font_size)
      end

      # Auteur
      if (author = doc.attr("author"))
        set_font(page, @fn_body, @theme.author_font_size)
        page.fill_color(@theme.author_font_color)
        draw_text_run(page, decode_html_entities(author), @margin, @page_height * 0.35, @fn_body, @theme.author_font_size)
      end

      # Date
      if (revdate = doc.attr("revdate"))
        set_font(page, @fn_body, @theme.base_font_size)
        page.fill_color("888888")
        draw_text_run(page, decode_html_entities(revdate), @margin, @page_height * 0.35 - @theme.author_font_size - 8.0, @fn_body, @theme.base_font_size)
      end

      # Ligne de séparation
      page.stroke_color("cccccc")
      page.line_width(1.0)
      sep_y = title_y - title_total_height - 30.0
      page.line({@margin, sep_y}, {@margin + @content_width, sep_y})
      page.stroke
    end

    # =========================================================================
    # En-têtes et pieds de page
    # =========================================================================

    private def render_headers_footers : Nil
      return unless @theme.header_enabled || @theme.footer_enabled

      @page_metas.each do |meta|
        page_idx = meta.number - 1
        next if page_idx < 0 || page_idx >= @doc.pages.size
        page = @doc.pages[page_idx]

        # Notes de bas de page
        render_page_footnotes(page, meta.number)

        if @theme.footer_enabled
          render_page_footer(page, meta)
        end
        if @theme.header_enabled
          render_page_header(page, meta)
        end
      end
    end

    private def render_page_footer(page : PDF::Page, meta : PageMeta) : Nil
      y = @margin / 2
      font_size = @theme.footer_font_size

      page.stroke_color(@theme.footer_border_color)
      page.line_width(@theme.footer_border_width)
      page.line({@margin, y + @theme.footer_height}, {@margin + @content_width, y + @theme.footer_height})
      page.stroke

      set_font(page, @fn_body, font_size)
      page.fill_color(@theme.footer_font_color)

      left = resolve_page_vars(@theme.footer_left, meta)
      center = resolve_page_vars(@theme.footer_center, meta)
      right = resolve_page_vars(@theme.footer_right, meta)

      page.text(left, at: {@margin, y + font_size}) unless left.empty?
      page.text(center, at: {@page_width / 2 - 20.0, y + font_size}) unless center.empty?
      page.text(right, at: {@margin + @content_width - 20.0, y + font_size}) unless right.empty?
    end

    private def render_page_header(page : PDF::Page, meta : PageMeta) : Nil
      y = @page_height - @margin / 2
      font_size = @theme.header_font_size

      page.stroke_color(@theme.header_border_color)
      page.line_width(@theme.header_border_width)
      page.line({@margin, y - @theme.header_height}, {@margin + @content_width, y - @theme.header_height})
      page.stroke

      set_font(page, @fn_body, font_size)
      page.fill_color(@theme.header_font_color)

      left = resolve_page_vars(@theme.header_left, meta)
      center = resolve_page_vars(@theme.header_center, meta)
      right = resolve_page_vars(@theme.header_right, meta)

      page.text(left, at: {@margin, y - font_size}) unless left.empty?
      page.text(center, at: {@page_width / 2 - 20.0, y + font_size}) unless center.empty?
      page.text(right, at: {@margin + @content_width - 20.0, y - font_size}) unless right.empty?
    end

    private def resolve_page_vars(template : String, meta : PageMeta) : String
      template
        .gsub("{page_number}", meta.number.to_s)
        .gsub("{section_title}", meta.section_title)
        .gsub("{document_title}", @document_title)
        # Replace U+00A0 with ASCII space just before the string is
        # handed to `page.text` in header/footer rendering (those
        # paths don't go through `draw_text_run`).
        .gsub('\u00A0', ' ')
    end

    # =========================================================================
    # Gestion des pages
    # =========================================================================

    private def new_page : Nil
      @page_number += 1
      @current_page = @doc.page(@page_width, @page_height) do |p|
        # Le bloc est requis, mais le contenu est ajouté de manière séquentielle.
      end
      @current_y = @page_height - @margin
      @page_metas << PageMeta.new(@page_number, @current_section_title)
    end

    private def ensure_page : Nil
      new_page if @current_page.nil?
    end

    private def check_page_break(needed_height : Float64) : Nil
      return unless @current_page
      if @current_y - needed_height < @margin + 20.0
        new_page
      end
    end

    # =========================================================================
    # Bookmarks PDF (outline)
    # =========================================================================

    # Génère le document outline (bookmarks) à partir des entrées TOC collectées.
    # Chaque section devient un bookmark dans le panneau de navigation, et
    # le clic amène le lecteur précisément au début du titre (et non au
    # haut de la page entière), grâce à la coordonnée Y mémorisée par
    # `convert_section`.
    private def generate_pdf_outline : Nil
      return if @toc_entries.empty?

      @doc.outline.define do |o|
        @toc_entries.each do |entry|
          title, _level, page_num, _dest_name, top_y = entry
          page_idx = page_num - 1
          next if page_idx < 0 || page_idx >= @doc.pages.size

          page_ref = @doc.pages[page_idx].page_reference
          dest = PDF::Destination.xyz(page_ref, top: top_y)

          # Niveaux 1 = sections principales, reste = items plats
          # (une arborescence complète nécessiterait de tracker les niveaux,
          #  on simplifie pour l'instant)
          o.item(title, dest: dest)
        end
      end
    end

    # =========================================================================
    # Écriture du PDF
    # =========================================================================

    private def write_pdf : Nil
      File.write(@output_path, @doc.to_slice)
    end

    private def determine_output_path(doc : Asciidoctor::Document) : String
      if (outfile = doc.attr("outfile"))
        outfile
      elsif (docfile = doc.attr("docfile"))
        File.join(File.dirname(docfile), File.basename(docfile, File.extname(docfile)) + ".pdf")
      else
        "output.pdf"
      end
    end

    # =========================================================================
    # Utilitaires de texte
    # =========================================================================

    # Rend le contenu HTML inline ligne par ligne sur la page PDF courante.
    # Gère le retour à la ligne automatique et le rendu des segments stylisés.
    private def render_inline_lines(
      page : PDF::Page,
      html : String,
      x : Float64,
      width : Float64,
      font_size : Float64,
      line_h : Float64,
    ) : Nil
      segments = InlineRenderer.parse(html)

      # Regrouper les segments en lignes avec mesure exacte
      current_line_segs = [] of InlineSegment
      current_line_width = 0.0

      segments.each do |seg|
        font_name = resolve_inline_font(seg)
        font = get_font(font_name)
        space_w = font.string_width(" ", font_size)

        words = seg.text.split(" ")
        words.each_with_index do |word, idx|
          word_w = font.string_width(word, font_size)
          sep_w = (idx > 0 || !current_line_segs.empty?) ? space_w : 0.0

          if current_line_width + sep_w + word_w > width && !current_line_segs.empty?
            render_segment_line(page, current_line_segs, x, @current_y - font_size, font_size)
            @current_y -= line_h
            current_line_segs = [] of InlineSegment
            current_line_width = 0.0
            sep_w = 0.0
          end

          prefix = sep_w > 0 ? " " : ""
          current_line_segs << InlineSegment.new(
            text: prefix + word,
            bold: seg.bold,
            italic: seg.italic,
            mono: seg.mono,
            color: seg.color,
            link: seg.link
          )
          current_line_width += sep_w + word_w
        end
      end

      unless current_line_segs.empty?
        render_segment_line(page, current_line_segs, x, @current_y - font_size, font_size)
        @current_y -= line_h
      end
    end

    # Rend une ligne de segments inline sur la page PDF.
    # Utilise les métriques exactes des polices pour l'avancement horizontal.
    private def render_segment_line(
      page : PDF::Page,
      segments : Array(InlineSegment),
      x : Float64,
      y : Float64,
      font_size : Float64,
    ) : Nil
      current_x = x
      segments.each do |seg|
        next if seg.text.empty?
        font_name = resolve_inline_font(seg)
        font = get_font(font_name)
        set_font(page, font_name, font_size)
        page.fill_color(seg.color || @theme.base_font_color)
        page.text(seg.text, at: {current_x, y})

        # Ajouter une annotation lien si le segment contient un lien
        if (link = seg.link) && !link.empty?
          seg_w = font.string_width(seg.text, font_size)
          page.link_uri(
            rect: {current_x, y - 2, current_x + seg_w, y + font_size},
            uri: link
          )
        end

        current_x += font.string_width(seg.text, font_size)
      end
    end

    # Résout le nom de la police à partir des attributs d'un segment inline.
    # Utilise les polices TTF du thème si disponibles.
    private def resolve_inline_font(seg : InlineSegment) : String
      if seg.mono
        @fn_mono
      elsif seg.bold && seg.italic
        @fn_body_bold_italic
      elsif seg.bold
        @fn_body_bold
      elsif seg.italic
        @fn_body_italic
      else
        @fn_body
      end
    end

    # Décode les entités HTML courantes en leurs caractères Unicode.
    # Couvre les entités nommées et numériques les plus fréquentes.
    private def decode_html_entities(text : String) : String
      text
        .gsub(/&#8217;/, "\u2019") # right single quotation mark
        .gsub(/&#8216;/, "\u2018") # left single quotation mark
        .gsub(/&#8220;/, "\u201C") # left double quotation mark
        .gsub(/&#8221;/, "\u201D") # right double quotation mark
        .gsub(/&#8212;/, "\u2014") # em dash
        .gsub(/&#8211;/, "\u2013") # en dash
        .gsub(/&#8230;/, "\u2026") # ellipsis
        .gsub(/&#39;/, "'")        # apostrophe
        .gsub(/&quot;/, "\"")
        .gsub(/&lt;/, "<")
        .gsub(/&gt;/, ">")
        .gsub(/&amp;/, "&")
        # Non-breaking space: replace with a regular space. The Type1
        # standard fonts used by the inline renderer don't always
        # expose a drawable NBSP glyph, so a real U+00A0 character
        # shows up as a tofu box in the PDF. Swapping it for an
        # ordinary space keeps the layout visually correct at the
        # cost of losing the non-break property.
        .gsub(/&#160;/, " ")
        .gsub(/&nbsp;/, " ")
        .gsub('\u00A0', " ")
        # Collapse newlines / whitespace runs introduced by the HTML
        # paragraph formatting. A bare `\n` would otherwise end up
        # in the drawn string and render as a tofu glyph.
        .gsub(/\s+/, " ")
    end

    # Supprime le markup inline HTML généré par asciidoctor
    private def strip_inline_markup(text : String) : String
      decoded = text.gsub(/<[^>]+>/, "")
      decode_html_entities(decoded).strip
    end

    # Charge les polices TTF définies dans le thème.
    # Si aucun chemin n'est défini, les polices Type1 standard sont utilisées.
    private def load_theme_fonts : Nil
      if (path = @theme.base_font_path) && File.exists?(path)
        ttf = @doc.load_font(path)
        @font_body = ttf
        @fn_body = ttf.name
      end
      if (path = @theme.base_font_bold_path) && File.exists?(path)
        ttf = @doc.load_font(path)
        @font_body_bold = ttf
        @fn_body_bold = ttf.name
        @fn_heading = ttf.name
      end
      if (path = @theme.base_font_italic_path) && File.exists?(path)
        ttf = @doc.load_font(path)
        @font_body_italic = ttf
        @fn_body_italic = ttf.name
      end
      if (path = @theme.base_font_bold_italic_path) && File.exists?(path)
        ttf = @doc.load_font(path)
        @font_body_bold_italic = ttf
        @fn_body_bold_italic = ttf.name
      end
      if (path = @theme.mono_font_path) && File.exists?(path)
        ttf = @doc.load_font(path)
        @font_mono = ttf
        @fn_mono = ttf.name
      end
      if (path = @theme.mono_font_bold_path) && File.exists?(path)
        ttf = @doc.load_font(path)
        @font_mono_bold = ttf
        @fn_mono_bold = ttf.name
      end
    end

    # Applique une police sur la page courante, en utilisant l'objet TTF si disponible.
    # Ceci est nécessaire car page.font(String) ne fonctionne que pour les Type1,
    # alors que page.font(TrueTypeFont) est requis pour les polices TTF.
    private def set_font(page : PDF::Page, font_name : String, size : Float64) : Nil
      ttf = case font_name
            when @fn_body             then @font_body
            when @fn_body_bold        then @font_body_bold
            when @fn_body_italic      then @font_body_italic
            when @fn_body_bold_italic then @font_body_bold_italic
            when @fn_mono             then @font_mono
            when @fn_mono_bold        then @font_mono_bold
            when @fn_heading          then @font_body_bold
            else                           nil
            end

      if ttf && ttf.is_a?(PDF::Fonts::TrueTypeFont)
        page.font(ttf, size: size)
      else
        page.font(font_name, size: size)
      end
    end

    # Retourne l'objet police pour la mesure de texte.
    # Utilise les polices TTF chargées si disponibles, sinon les Type1.
    private def get_font(font_name : String) : PDF::Fonts::Base
      # Vérifier d'abord les polices TTF chargées
      case font_name
      when @fn_body             then @font_body || @doc.font("Helvetica")
      when @fn_body_bold        then @font_body_bold || @doc.font("Helvetica-Bold")
      when @fn_body_italic      then @font_body_italic || @doc.font("Helvetica-Oblique")
      when @fn_body_bold_italic then @font_body_bold_italic || @doc.font("Helvetica-BoldOblique")
      when @fn_mono             then @font_mono || @doc.font("Courier")
      when @fn_mono_bold        then @font_mono_bold || @doc.font("Courier-Bold")
      when @fn_heading          then @font_body_bold || @doc.font("Helvetica-Bold")
      else                           @doc.font(font_name)
      end
    end

    # Mesure la largeur d'un texte en points en utilisant les métriques
    # exactes des polices (Type1 ou TrueType). Les drapeaux emoji
    # (paires de regional indicators, rendus comme SVG via
    # crystal-flags) comptent pour une largeur fixe dérivée de la
    # taille de police, pas comme les glyphes `.notdef` de la police
    # texte.
    private def text_width(text : String, font_name : String, font_size : Float64) : Float64
      measure_width(text, get_font(font_name), font_size)
    end

    # Même mesure que `text_width` mais prend un objet `PDF::Fonts::Base`
    # déjà résolu. Utilisé en interne par `wrap_text` et
    # `break_long_word`.
    private def measure_width(text : String, font : PDF::Fonts::Base, font_size : Float64) : Float64
      total = 0.0
      InlineFlags.segments(text).each do |(kind, value)|
        total += if kind == :flag
                   InlineFlags.flag_width(font_size)
                 else
                   font.string_width(value, font_size)
                 end
      end
      total
    end

    # Sanitise `text` pour qu'il puisse être rendu par les polices
    # Type1 standard (encodage WinAnsi). Tout caractère hors plage
    # est remplacé par `?` et l'auteur est prévenu via STDERR — une
    # seule fois par caractère et par conversion, pour ne pas
    # spammer la sortie quand un même emoji apparaît N fois.
    #
    # Cette méthode protège contre le cas le plus pénible : un
    # emoji ou dingbat dans le source AsciiDoc qui sortirait en
    # tofu silencieux dans le PDF. Mieux vaut un `?` visible plus
    # un warning lisible.
    #
    # NOTE : c'est une mesure conservatoire. Les emojis colorés
    # (✅ ❌ 🔴 …) seront rendus correctement quand le shard
    # `crystal-emojis` sera intégré (cf. roadmap).
    def safe_text(text : String) : String
      WinAnsi.sanitize(text) { |char| warn_unrenderable(char) }
    end

    private def warn_unrenderable(char : Char) : Nil
      return if @warned_chars.includes?(char)
      @warned_chars << char
      hex = char.ord.to_s(16).upcase.rjust(4, '0')
      STDERR.puts %(Avertissement : caractère « #{char} » (U+#{hex}) absent de WinAnsi, remplacé par « ? » dans le PDF.)
    end

    # Dessine `text` à la position `(x, y)` sur `page`. Les drapeaux
    # emoji sont rendus comme SVG (via `crystal-flags`) au lieu du
    # tofu produit par une police texte standard qui n'a pas de
    # glyphes pour ces codepoints. Le curseur X avance de la largeur
    # exacte de chaque segment (texte ou drapeau) pour que les runs
    # suivants soient positionnés correctement.
    private def draw_text_run(page : PDF::Page, text : String, x : Float64, y : Float64, font_name : String, font_size : Float64) : Nil
      font = get_font(font_name)
      cursor = x
      flag_w = InlineFlags.flag_width(font_size)
      flag_h = InlineFlags.flag_height(font_size)

      InlineFlags.segments(text).each do |(kind, value)|
        if kind == :flag
          if (svg_data = CrystalFlags.svg(value))
            # `page.svg(at: {x, y})` treats `y` as the top of the SVG
            # bounding box (the renderer flips y internally). To align
            # the flag with the text's x-height, position the top of
            # the flag at `y + flag_h` (so its bottom sits on the
            # baseline, matching the visual height of a capital).
            page.svg(svg_data, at: {cursor, y + flag_h}, width: flag_w, height: flag_h)
          else
            # Fallback : afficher le code ISO en texte quand le drapeau
            # n'est pas disponible (ex : pays invalide ou absent du set).
            page.text("[#{value}]", at: {cursor, y})
          end
          cursor += flag_w
        else
          # Substitue U+00A0 par un espace ASCII au moment du dessin.
          # Le NBSP a été préservé jusqu'ici pour que `wrap_text` ne
          # casse pas dessus (insécabilité conservée) ; l'emit PDF
          # utilise un espace ordinaire pour éviter un tofu avec les
          # polices qui n'ont pas de glyphe NBSP.
          softened = value.gsub('\u00A0', ' ')
          # Coupe la chaîne autour de chaque emoji connu de
          # crystal-emojis-lite : le texte plain est rendu via
          # `page.text` (avec sanitize WinAnsi pour les caractères
          # restant hors plage), les emojis comme glyphes SVG
          # alignés sur la baseline (mêmes dimensions qu un
          # drapeau pour rester cohérent visuellement).
          emoji_w = flag_w
          emoji_h = flag_h
          text_with_emoji_segments(softened).each do |(kind2, value2)|
            if kind2 == :emoji
              if (svg_data = CrystalEmojis.svg(value2[0]))
                page.svg(svg_data, at: {cursor, y + emoji_h}, width: emoji_w, height: emoji_h)
                cursor += emoji_w
              else
                printable = safe_text(value2)
                page.text(printable, at: {cursor, y})
                cursor += font.string_width(printable, font_size)
              end
            else
              printable = safe_text(value2)
              page.text(printable, at: {cursor, y})
              cursor += font.string_width(printable, font_size)
            end
          end
        end
      end
    end

    # Découpe un texte en lignes selon la largeur disponible.
    # Utilise les métriques de police exactes pour le calcul.
    # Les mots qui dépassent seuls la largeur disponible (par exemple un
    # nom propre long dans une colonne étroite) sont découpés caractère
    # Découpe `text` en alternance de segments :text et :emoji selon
    # ce que `crystal-emojis-lite` reconnaît. Les emojis sont rendus
    # comme glyphes SVG en couleur par `draw_text_run`, le reste
    # part dans le pipeline texte standard.
    #
    # Format : Array de tuples `{Symbol, String}` où :
    #   * `{:text,  "..."}` — texte sans emoji connu, à passer à `page.text`
    #   * `{:emoji, "X"}`   — un seul codepoint emoji, à rendre en SVG
    #
    # Les emojis multi-codepoint (ZWJ, tons de peau, drapeaux) ne sont
    # pas couverts par crystal-emojis-lite : ils retombent dans la
    # branche `:text`, où le sanitize WinAnsi les remplacera par `?`.
    # Pour les couvrir, l'utilisateur peut ajouter crystal-emojis-full
    # à ses dépendances et fournir un patch dans cette méthode.
    private def text_with_emoji_segments(text : String) : Array({Symbol, String})
      result = [] of {Symbol, String}
      buf = String::Builder.new
      text.each_char do |char|
        if CrystalEmojis.includes?(char)
          unless buf.bytesize == 0
            result << {:text, buf.to_s}
            buf = String::Builder.new
          end
          result << {:emoji, char.to_s}
        else
          buf << char
        end
      end
      result << {:text, buf.to_s} unless buf.bytesize == 0
      result
    end

    # Découpe un texte en lignes selon la largeur disponible.
    # Utilise les métriques de police exactes pour le calcul.
    # Les mots qui dépassent seuls la largeur disponible (par exemple un
    # nom propre long dans une colonne étroite) sont découpés caractère
    # par caractère pour éviter que la cellule déborde visuellement.
    private def wrap_text(text : String, width : Float64, font_size : Float64, font_name : String? = nil) : Array(String)
      font = get_font(font_name || @fn_body)
      space_w = font.string_width(" ", font_size)
      lines = [] of String

      text.split("\n").each do |paragraph|
        words = paragraph.split(" ")
        current_line = ""
        current_width = 0.0

        words.each do |word|
          word_w = measure_width(word, font, font_size)
          sep_w = current_line.empty? ? 0.0 : space_w

          if current_width + sep_w + word_w <= width
            current_line = current_line.empty? ? word : "#{current_line} #{word}"
            current_width += sep_w + word_w
          elsif word_w > width
            # Le mot ne tient pas seul : on le découpe en morceaux qui tiennent.
            lines << current_line unless current_line.empty?
            chunks = break_long_word(word, width, font, font_size)
            # Les n-1 premiers morceaux occupent une ligne complète.
            chunks[0..-2].each { |chunk| lines << chunk } if chunks.size > 1
            current_line = chunks.last
            current_width = measure_width(current_line, font, font_size)
          else
            lines << current_line unless current_line.empty?
            current_line = word
            current_width = word_w
          end
        end
        lines << current_line unless current_line.empty?
      end

      lines.empty? ? [""] : lines
    end

    # Découpe un mot en morceaux dont chacun tient dans `width`.
    # Utilisé par `wrap_text` quand un mot seul dépasse la largeur (par
    # exemple dans des cellules de tableau très étroites).
    #
    # Priorité de césure, du plus lisible au plus brutal :
    # 1. Trait d'union interne : `Pays-Bas` -> `Pays-` + `Bas`.
    # 2. Majuscule interne (camelCase) : `RoyaumeUni` -> `Royaume` + `Uni`.
    # 3. Caractère par caractère, en dernier recours.
    #
    # Les sous-parties peuvent elles-mêmes dépasser `width` : on les
    # réinjecte récursivement dans l'algorithme pour les découper plus
    # finement jusqu'à ce qu'elles tiennent.
    private def break_long_word(word : String, width : Float64, font : PDF::Fonts::Base, font_size : Float64) : Array(String)
      return [word] if font.string_width(word, font_size) <= width

      # 1. Tirets internes : découpe en gardant le tiret sur le morceau de gauche.
      if word.includes?('-') && word.index('-') != 0 && word.index('-') != word.size - 1
        parts = split_keep_separator(word, '-')
        return parts.flat_map { |p| break_long_word(p, width, font, font_size) } if parts.size > 1
      end

      # 2. Majuscules internes (casse mixte type `RoyaumeUni`, `GitHub`).
      parts = split_on_internal_uppercase(word)
      if parts.size > 1
        return parts.flat_map { |p| break_long_word(p, width, font, font_size) }
      end

      # 3. Découpe caractère par caractère.
      chunks = [] of String
      buf = ""
      word.each_char do |c|
        candidate = buf + c
        if !buf.empty? && font.string_width(candidate, font_size) > width
          chunks << buf
          buf = c.to_s
        else
          buf = candidate
        end
      end
      chunks << buf unless buf.empty?
      chunks
    end

    # Découpe `text` sur chaque occurrence de `sep`, en conservant `sep`
    # à la fin du morceau qui le précède. Exemple :
    # `split_keep_separator("Pays-Bas", '-')` -> `["Pays-", "Bas"]`.
    private def split_keep_separator(text : String, sep : Char) : Array(String)
      parts = [] of String
      buf = String::Builder.new
      text.each_char do |c|
        buf << c
        if c == sep
          parts << buf.to_s
          buf = String::Builder.new
        end
      end
      tail = buf.to_s
      parts << tail unless tail.empty?
      parts
    end

    # Découpe `text` aux transitions minuscule -> majuscule (casse mixte
    # interne, type `RoyaumeUni`). Renvoie un tableau singleton si le
    # mot n'a pas de frontière interne exploitable.
    private def split_on_internal_uppercase(text : String) : Array(String)
      return [text] if text.size < 2
      parts = [] of String
      buf = String::Builder.new
      prev : Char? = nil
      text.each_char do |c|
        if (p = prev) && p.lowercase? && c.uppercase?
          parts << buf.to_s
          buf = String::Builder.new
        end
        buf << c
        prev = c
      end
      tail = buf.to_s
      parts << tail unless tail.empty?
      parts
    end
  end
end
