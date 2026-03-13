require "crystal-asciidoctor/src/crystal-asciidoctor"
require "crystal-pdf/src/pdf"

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
    @toc_entries : Array({String, Int32, Int32}) = [] of {String, Int32, Int32}  # {titre, niveau, page}
    @output_path : String = "output.pdf"

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
    end

    # Point d'entrée principal : convertit le document et écrit le PDF
    def convert(node : Asciidoctor::AbstractNode, transform : String? = nil) : String
      transform ||= node.node_name
      dispatch(node, transform)
    end

    def dispatch(node : Asciidoctor::AbstractNode, transform : String) : String
      case transform
      when "document"       then convert_document(node)
      when "section"        then convert_section(node)
      when "paragraph"      then convert_paragraph(node)
      when "listing"        then convert_listing(node)
      when "literal"        then convert_literal(node)
      when "admonition"     then convert_admonition(node)
      when "ulist"          then convert_ulist(node)
      when "olist"          then convert_olist(node)
      when "dlist"          then convert_dlist(node)
      when "table"          then convert_table(node)
      when "image"          then convert_image(node)
      when "page_break"     then convert_page_break(node)
      when "thematic_break" then convert_thematic_break(node)
      when "quote"          then convert_quote(node)
      when "verse"          then convert_verse(node)
      when "sidebar"        then convert_sidebar(node)
      when "example"        then convert_example(node)
      when "open"           then convert_open(node)
      when "preamble"       then convert_preamble(node)
      when "toc"            then ""  # géré dans convert_document
      when "floating_title" then convert_floating_title(node)
      when "inline_anchor"  then ""
      when "inline_break"   then ""
      when "inline_button"  then ""
      when "inline_callout" then ""
      when "inline_footnote" then ""
      when "inline_image"   then ""
      when "inline_indexterm" then convert_inline_indexterm(node)
      when "inline_kbd"     then ""
      when "inline_menu"    then ""
      when "inline_quoted"  then ""
      when "pass"           then ""
      when "stem"           then ""
      when "audio"          then ""
      when "video"          then ""
      when "colist"         then ""
      when "outline"        then ""
      when "embedded"       then convert_embedded(node)
      else                       ""
      end
    end

    # =========================================================================
    # Document
    # =========================================================================

    def convert_document(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Document)

      @document_title = node.doctitle || ""
      @output_path = determine_output_path(node)

      # Page de titre
      if @theme.title_page_enabled && !@document_title.empty?
        render_title_page(node)
      end

      # Table des matières (placeholder, sera remplie après le rendu)
      toc_page_number = -1
      if @theme.toc_enabled && node.attr?("toc")
        toc_page_number = @page_number + 1
        new_page
      end

      # Contenu principal
      node.blocks.each do |block|
        convert(block)
      end

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
      title = node.title || ""
      @current_section_title = title

      # Enregistrer pour la table des matières
      @toc_entries << {title, level, @page_number}

      ensure_page

      # Marge supérieure
      margin_top = @theme.heading_margin_top(level)
      @current_y -= margin_top if @current_y < (@page_height - @margin - margin_top)

      # Rendu du titre de section
      font_size = @theme.heading_font_size(level)
      page = @current_page.not_nil!

      page.font("Helvetica-Bold", size: font_size)
      page.fill_color(@theme.heading_font_color)

      text_y = @current_y - font_size
      check_page_break(font_size + @theme.heading_margin_bottom(level) + 5)

      page.text(title, at: {@margin, @current_y - font_size})
      @current_y -= font_size + @theme.heading_margin_bottom(level)

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
      text = node.content || ""
      text = strip_inline_markup(text)
      return "" if text.empty?

      font_size = @theme.base_font_size
      line_height = @theme.base_line_height
      line_h = font_size * line_height

      page = @current_page.not_nil!
      page.font("Helvetica", size: font_size)
      page.fill_color(@theme.base_font_color)

      # Découper le texte en lignes
      lines = wrap_text(text, @content_width, font_size)
      total_h = lines.size * line_h + @theme.prose_margin_bottom

      check_page_break(total_h)

      lines.each do |line|
        page.text(line, at: {@margin, @current_y - font_size})
        @current_y -= line_h
      end
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
      lines = source.split("\n")
      font_size = @theme.code_font_size
      line_h = font_size * 1.4
      padding = @theme.code_padding

      total_h = lines.size * line_h + (2 * padding) + @theme.code_margin_top + @theme.code_margin_bottom
      check_page_break(total_h)

      page = @current_page.not_nil!
      @current_y -= @theme.code_margin_top

      # Fond du bloc de code
      block_h = lines.size * line_h + (2 * padding)
      page.fill_color(@theme.code_background_color)
      page.rectangle(@margin, @current_y - block_h, @content_width, block_h)
      page.fill

      # Bordure
      page.stroke_color(@theme.code_border_color)
      page.line_width(@theme.code_border_width)
      page.rectangle(@margin, @current_y - block_h, @content_width, block_h)
      page.stroke

      # Texte du code
      page.font("Courier", size: font_size)
      page.fill_color(@theme.code_font_color)

      y = @current_y - padding - font_size
      lines.each do |line|
        page.text(line, at: {@margin + padding, y})
        y -= line_h
      end

      @current_y -= block_h + @theme.code_margin_bottom
      ""
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
      label_width = 60.0
      content_w = @content_width - label_width - padding

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
      page.font("Helvetica-Bold", size: font_size - 1)
      page.fill_color(border_color)
      page.text(name.upcase, at: {@margin + @theme.admonition_border_width + 4, @current_y - padding - font_size})

      # Texte de l'admonition
      page.font("Helvetica", size: font_size)
      page.fill_color(@theme.base_font_color)

      y = @current_y - padding - font_size
      lines.each do |line|
        page.text(line, at: {@margin + label_width, y})
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
        page.font("Helvetica-Bold", size: @theme.base_font_size)
        page.fill_color(@theme.base_font_color)
        page.text(term, at: {@margin, @current_y - @theme.base_font_size})
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

        page.font("Helvetica", size: font_size)
        page.fill_color(@theme.list_marker_color)
        page.text(marker, at: {x_marker, @current_y - font_size})

        page.fill_color(@theme.base_font_color)
        lines.each do |line|
          page.text(line, at: {x_text, @current_y - font_size})
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

      col_width = @content_width / col_count
      font_size = @theme.base_font_size
      cell_h = font_size + (2 * @theme.table_cell_padding)

      page = @current_page.not_nil!

      # En-têtes
      if node.has_header_option
        node.rows.head.each do |row|
          x = @margin
          row.each do |cell|
            page.fill_color(@theme.table_header_background_color)
            page.rectangle(x, @current_y - cell_h, col_width, cell_h)
            page.fill

            page.stroke_color(@theme.table_border_color)
            page.line_width(@theme.table_border_width)
            page.rectangle(x, @current_y - cell_h, col_width, cell_h)
            page.stroke

            page.font("Helvetica-Bold", size: font_size)
            page.fill_color(@theme.base_font_color)
            text = strip_inline_markup(cell.text || "")
            page.text(text, at: {x + @theme.table_cell_padding, @current_y - @theme.table_cell_padding - font_size})
            x += col_width
          end
          @current_y -= cell_h
        end
      end

      # Corps du tableau
      node.rows.body.each do |row|
        check_page_break(cell_h)
        x = @margin
        row.each do |cell|
          page = @current_page.not_nil!
          page.stroke_color(@theme.table_border_color)
          page.line_width(@theme.table_border_width)
          page.rectangle(x, @current_y - cell_h, col_width, cell_h)
          page.stroke

          page.font("Helvetica", size: font_size)
          page.fill_color(@theme.base_font_color)
          text = strip_inline_markup(cell.text || "")
          page.text(text, at: {x + @theme.table_cell_padding, @current_y - @theme.table_cell_padding - font_size})
          x += col_width
        end
        @current_y -= cell_h
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
      # Rendu d'un placeholder si l'image n'est pas trouvée
      page = @current_page.not_nil!
      alt = node.attr("alt") || target
      font_size = @theme.base_font_size

      @current_y -= 8.0
      page.stroke_color("cccccc")
      page.line_width(0.5)
      page.rectangle(@margin, @current_y - 40.0, @content_width, 40.0)
      page.stroke

      page.font("Helvetica", size: font_size - 1)
      page.fill_color("888888")
      page.text("[Image: #{alt}]", at: {@margin + 8.0, @current_y - 24.0})
      @current_y -= 48.0
      ""
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
      page = @current_page.not_nil!
      page.font("Helvetica-Bold", size: font_size)
      page.fill_color(@theme.heading_font_color)
      check_page_break(font_size + 8.0)
      page.text(title, at: {@margin, @current_y - font_size})
      @current_y -= font_size + 6.0
      ""
    end

    def convert_inline_indexterm(node : Asciidoctor::AbstractNode) : String
      return "" unless node.is_a?(Asciidoctor::Inline)
      term = node.text || ""
      @index_entries << IndexEntry.new(term, @page_number) unless term.empty?
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
      page.font("Helvetica-Oblique", size: font_size)
      page.fill_color(@theme.base_font_color)

      y = @current_y - font_size
      lines.each do |line|
        page.text(line, at: {@margin + indent, y})
        y -= line_h
      end

      @current_y -= block_h + 6.0

      # Attribution
      if (attribution = node.attr("attribution"))
        page.font("Helvetica", size: font_size - 1)
        page.fill_color("555555")
        page.text("— #{attribution}", at: {@margin + indent, @current_y - font_size})
        @current_y -= font_size + 4.0
      end
      ""
    end

    # =========================================================================
    # Page de titre
    # =========================================================================

    private def render_title_page(doc : Asciidoctor::Document) : Nil
      new_page
      page = @current_page.not_nil!
      center_x = @page_width / 2

      # Titre principal
      title = doc.doctitle || ""
      page.font("Helvetica-Bold", size: @theme.title_font_size)
      page.fill_color(@theme.title_font_color)
      title_y = @page_height * 0.55
      page.text(title, at: {@margin, title_y})

      # Sous-titre
      if (subtitle = doc.attr("subtitle"))
        page.font("Helvetica", size: @theme.subtitle_font_size)
        page.fill_color(@theme.subtitle_font_color)
        page.text(subtitle, at: {@margin, title_y - @theme.title_font_size - 10.0})
      end

      # Auteur
      if (author = doc.attr("author"))
        page.font("Helvetica", size: @theme.author_font_size)
        page.fill_color(@theme.author_font_color)
        page.text(author, at: {@margin, @page_height * 0.35})
      end

      # Date
      if (revdate = doc.attr("revdate"))
        page.font("Helvetica", size: @theme.base_font_size)
        page.fill_color("888888")
        page.text(revdate, at: {@margin, @page_height * 0.35 - @theme.author_font_size - 8.0})
      end

      # Ligne de séparation
      page.stroke_color("cccccc")
      page.line_width(1.0)
      page.line({@margin, title_y - @theme.title_font_size - 30.0}, {@margin + @content_width, title_y - @theme.title_font_size - 30.0})
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

      page.font("Helvetica", size: font_size)
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

      page.font("Helvetica", size: font_size)
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
    end

    # =========================================================================
    # Gestion des pages
    # =========================================================================

    private def new_page : Nil
      @page_number += 1
      @current_page = @doc.page do |p|
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

    # Supprime le markup inline HTML généré par asciidoctor
    private def strip_inline_markup(text : String) : String
      text
        .gsub(/<[^>]+>/, "")
        .gsub(/&amp;/, "&")
        .gsub(/&lt;/, "<")
        .gsub(/&gt;/, ">")
        .gsub(/&quot;/, "\"")
        .gsub(/&#8220;/, "\u201C")
        .gsub(/&#8221;/, "\u201D")
        .gsub(/&#8216;/, "\u2018")
        .gsub(/&#8217;/, "\u2019")
        .gsub(/&#8230;/, "\u2026")
        .strip
    end

    # Découpe un texte en lignes selon la largeur disponible (approximatif)
    private def wrap_text(text : String, width : Float64, font_size : Float64) : Array(String)
      char_width = font_size * 0.55  # approximation pour Helvetica
      max_chars = [1, (width / char_width).to_i].max
      lines = [] of String

      text.split("\n").each do |paragraph|
        words = paragraph.split(" ")
        current_line = ""

        words.each do |word|
          test = current_line.empty? ? word : "#{current_line} #{word}"
          if test.size <= max_chars
            current_line = test
          else
            lines << current_line unless current_line.empty?
            current_line = word.size > max_chars ? word[0, max_chars] : word
          end
        end
        lines << current_line unless current_line.empty?
      end

      lines.empty? ? [""] : lines
    end
  end
end
