module AsciidoctorPDF
  # Répertoire data/fonts/ contenant les polices TTF embarquées (DejaVu Sans).
  # Résolu à la compilation par rapport au fichier source.
  FONTS_DIR = File.join(File.dirname(File.dirname(__DIR__)), "data", "fonts")

  # Thème PDF : définit toutes les propriétés visuelles du document PDF généré.
  # Équivalent du système de thèmes YAML d'asciidoctor-pdf Ruby.
  class Theme
    # --- Page ---
    property page_size : String = "A4"
    property page_layout : String = "portrait"
    property page_margin : Float64 = 36.0 # 0.5 inch en points

    # --- Polices ---
    property base_font_family : String = "DejaVu Sans"
    property base_font_size : Float64 = 10.0
    property base_line_height : Float64 = 1.5
    property base_font_color : String = "333333"

    # Polices TrueType — par défaut DejaVu Sans (Unicode complet).
    # Mettre à nil pour revenir aux polices Type1 intégrées (pas d'Unicode étendu).
    property base_font_path : String? = File.join(FONTS_DIR, "DejaVuSans.ttf")
    property base_font_bold_path : String? = File.join(FONTS_DIR, "DejaVuSans-Bold.ttf")
    property base_font_italic_path : String? = File.join(FONTS_DIR, "DejaVuSans-Oblique.ttf")
    property base_font_bold_italic_path : String? = nil
    property mono_font_path : String? = File.join(FONTS_DIR, "DejaVuSansMono.ttf")
    property mono_font_bold_path : String? = nil

    # --- Titres ---
    property heading_font_family : String = "Helvetica"
    property heading_font_color : String = "1a1a1a"
    property heading_line_height : Float64 = 1.2

    property h1_font_size : Float64 = 22.0
    property h1_font_style : String = "bold"
    property h1_margin_top : Float64 = 12.0
    property h1_margin_bottom : Float64 = 6.0

    property h2_font_size : Float64 = 18.0
    property h2_font_style : String = "bold"
    property h2_margin_top : Float64 = 10.0
    property h2_margin_bottom : Float64 = 5.0

    property h3_font_size : Float64 = 14.0
    property h3_font_style : String = "bold"
    property h3_margin_top : Float64 = 8.0
    property h3_margin_bottom : Float64 = 4.0

    property h4_font_size : Float64 = 12.0
    property h4_font_style : String = "bold"
    property h4_margin_top : Float64 = 6.0
    property h4_margin_bottom : Float64 = 3.0

    property h5_font_size : Float64 = 11.0
    property h5_font_style : String = "bold"
    property h5_margin_top : Float64 = 5.0
    property h5_margin_bottom : Float64 = 2.0

    property h6_font_size : Float64 = 10.5
    property h6_font_style : String = "bold_italic"
    property h6_margin_top : Float64 = 4.0
    property h6_margin_bottom : Float64 = 2.0

    # --- Paragraphes ---
    property prose_margin_top : Float64 = 0.0
    property prose_margin_bottom : Float64 = 10.0

    # --- Listes ---
    property list_indent : Float64 = 20.0
    property list_item_spacing : Float64 = 4.0
    property list_marker_color : String = "555555"

    # --- Code ---
    property code_font_family : String = "Courier"
    property code_font_size : Float64 = 9.0
    property code_background_color : String = "f5f5f5"
    property code_border_color : String = "cccccc"
    property code_border_width : Float64 = 0.5
    property code_padding : Float64 = 8.0
    property code_margin_top : Float64 = 6.0
    property code_margin_bottom : Float64 = 6.0
    property code_font_color : String = "333333"

    # --- Admonitions ---
    property admonition_border_width : Float64 = 2.0
    property admonition_padding : Float64 = 8.0
    property admonition_margin_top : Float64 = 8.0
    property admonition_margin_bottom : Float64 = 8.0

    property admonition_note_color : String = "3b9ddd"
    property admonition_tip_color : String = "3bdd6a"
    property admonition_warning_color : String = "f0ad4e"
    property admonition_caution_color : String = "d9534f"
    property admonition_important_color : String = "d9534f"

    # --- Tableaux ---
    property table_border_color : String = "dddddd"
    property table_border_width : Float64 = 0.5
    property table_header_background_color : String = "e8e8e8"
    property table_header_font_color : String = "333333"
    property table_header_font_style : String = "bold"
    property table_row_alt_background_color : String? = "f9f9f9"
    property table_footer_background_color : String = "eeeeee"
    property table_cell_padding : Float64 = 4.0
    property table_margin_top : Float64 = 8.0
    property table_margin_bottom : Float64 = 8.0

    # --- Page de titre ---
    property title_page_enabled : Bool = true
    property title_font_size : Float64 = 28.0
    property title_font_color : String = "1a1a1a"
    property title_font_style : String = "bold"
    property subtitle_font_size : Float64 = 18.0
    property subtitle_font_color : String = "555555"
    property author_font_size : Float64 = 12.0
    property author_font_color : String = "333333"
    # Quand true, rend la table des matières directement sur la page de
    # garde (pas de page TOC séparée). Le titre n'est plus centré-bas
    # mais positionné en tête de zone de contenu, suivi de la TOC, puis
    # auteur + date en bas. Override per-document via l'attribut
    # AsciiDoc `:title-page-toc:`.
    property title_page_with_toc : Bool = false

    # --- Table des matières ---
    property toc_enabled : Bool = true
    property toc_title : String = "Table des matières"
    property toc_font_size : Float64 = 10.0
    property toc_dot_leader_color : String = "aaaaaa"

    # --- En-têtes et pieds de page ---
    property header_enabled : Bool = false
    property header_height : Float64 = 20.0
    property header_border_width : Float64 = 0.5
    property header_border_color : String = "cccccc"
    property header_font_size : Float64 = 9.0
    property header_font_color : String = "888888"
    property header_left : String = ""
    property header_center : String = ""
    property header_right : String = "{page_number}"

    property footer_enabled : Bool = true
    property footer_height : Float64 = 20.0
    property footer_border_width : Float64 = 0.5
    property footer_border_color : String = "cccccc"
    property footer_font_size : Float64 = 9.0
    property footer_font_color : String = "888888"
    property footer_left : String = "{document_title}"
    property footer_center : String = ""
    property footer_right : String = "{page_number}"

    # --- Couleurs de syntax highlighting ---
    property code_highlight_enabled : Bool = true
    property code_highlight_keyword_color : String = "0000ff"
    property code_highlight_string_color : String = "008000"
    property code_highlight_comment_color : String = "808080"
    property code_highlight_number_color : String = "800000"
    property code_highlight_type_color : String = "0000aa"
    property code_highlight_operator_color : String = "555555"
    property code_highlight_constant_color : String = "aa0000"
    property code_highlight_symbol_color : String = "008080"
    property code_highlight_annotation_color : String = "808000"

    # --- Index ---
    property index_enabled : Bool = false
    property index_title : String = "Index"
    property index_columns : Int32 = 2
    property index_font_size : Float64 = 9.0
    property index_page_number_color : String = "555555"

    # Retourne la taille de police pour un niveau de titre donné (1-6)
    def heading_font_size(level : Int32) : Float64
      case level
      when 1 then h1_font_size
      when 2 then h2_font_size
      when 3 then h3_font_size
      when 4 then h4_font_size
      when 5 then h5_font_size
      else        h6_font_size
      end
    end

    # Retourne la marge supérieure pour un niveau de titre donné
    def heading_margin_top(level : Int32) : Float64
      case level
      when 1 then h1_margin_top
      when 2 then h2_margin_top
      when 3 then h3_margin_top
      when 4 then h4_margin_top
      when 5 then h5_margin_top
      else        h6_margin_top
      end
    end

    # Retourne la marge inférieure pour un niveau de titre donné
    def heading_margin_bottom(level : Int32) : Float64
      case level
      when 1 then h1_margin_bottom
      when 2 then h2_margin_bottom
      when 3 then h3_margin_bottom
      when 4 then h4_margin_bottom
      when 5 then h5_margin_bottom
      else        h6_margin_bottom
      end
    end
  end
end
