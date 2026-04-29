require "yaml"

module AsciidoctorPDF
  # Charge un thème depuis un fichier YAML et peuple un objet Theme.
  # Équivalent du ThemeLoader d'asciidoctor-pdf Ruby.
  module ThemeLoader
    # Thèmes embarqués au moment de la compilation : leur YAML est
    # inliné dans le binaire, pas besoin que les fichiers existent
    # à l'exécution. Ajout d'un nouveau thème :
    #   1. Créer `themes/<nom>.yml`
    #   2. Ajouter une entrée dans BUILTIN_THEMES ci-dessous
    #   3. Documenter dans le README
    BUILTIN_THEMES = {
      "fr"       => {{ read_file("#{__DIR__}/../../themes/fr.yml") }},
      "francais" => {{ read_file("#{__DIR__}/../../themes/fr.yml") }},
      "french"   => {{ read_file("#{__DIR__}/../../themes/fr.yml") }},
    }

    # Liste des noms canoniques (alias compris) des thèmes embarqués,
    # utile pour la complétion CLI ou la validation.
    def self.builtin_names : Array(String)
      BUILTIN_THEMES.keys
    end

    # Charge un thème embarqué (fr, francais, french). Le YAML est
    # inliné dans le binaire — pas de dépendance de fichier à
    # l'exécution. Insensible à la casse.
    def self.builtin(name : String) : Theme
      key = name.downcase
      yaml_str = BUILTIN_THEMES[key]?
      raise ArgumentError.new("Thème embarqué inconnu : '#{name}'. Disponibles : #{builtin_names.join(", ")}") unless yaml_str

      theme = Theme.new
      apply(theme, YAML.parse(yaml_str))
      theme
    end

    # Charge un thème depuis un fichier YAML.
    # Si le fichier n'existe pas, retourne le thème par défaut.
    def self.load(path : String) : Theme
      theme = Theme.new
      return theme unless File.exists?(path)

      yaml = YAML.parse(File.read(path))
      apply(theme, yaml)
      theme
    rescue ex
      STDERR.puts "Warning: impossible de charger le thème '#{path}': #{ex.message}"
      Theme.new
    end

    # Résout un thème par son nom OU son chemin :
    #   * un nom embarqué (ex: "fr") → ThemeLoader.builtin
    #   * un chemin existant → ThemeLoader.load
    # Idéal pour le CLI ou pour respecter `:pdf-theme:` côté source
    # AsciiDoc, où l'utilisateur peut indiquer indifféremment l'un
    # ou l'autre.
    def self.resolve(name_or_path : String) : Theme
      key = name_or_path.downcase
      return builtin(key) if BUILTIN_THEMES.has_key?(key)
      load(name_or_path)
    end

    # Applique les valeurs YAML au thème
    private def self.apply(theme : Theme, yaml : YAML::Any) : Nil
      return unless yaml.as_h?

      yaml.as_h.each do |key, value|
        k = key.as_s? || key.to_s

        case k
        # Page
        when "page_size"   then theme.page_size = value.as_s? || theme.page_size
        when "page_layout" then theme.page_layout = value.as_s? || theme.page_layout
        when "page_margin" then theme.page_margin = parse_float(value, theme.page_margin)
          # Polices de base
        when "base_font_family"           then theme.base_font_family = value.as_s? || theme.base_font_family
        when "base_font_size"             then theme.base_font_size = parse_float(value, theme.base_font_size)
        when "base_line_height"           then theme.base_line_height = parse_float(value, theme.base_line_height)
        when "base_font_color"            then theme.base_font_color = value.as_s? || theme.base_font_color
        when "base_font_path"             then theme.base_font_path = value.as_s?
        when "base_font_bold_path"        then theme.base_font_bold_path = value.as_s?
        when "base_font_italic_path"      then theme.base_font_italic_path = value.as_s?
        when "base_font_bold_italic_path" then theme.base_font_bold_italic_path = value.as_s?
        when "mono_font_path"             then theme.mono_font_path = value.as_s?
        when "mono_font_bold_path"        then theme.mono_font_bold_path = value.as_s?
          # Titres
        when "heading_font_family" then theme.heading_font_family = value.as_s? || theme.heading_font_family
        when "heading_font_color"  then theme.heading_font_color = value.as_s? || theme.heading_font_color
        when "heading_line_height" then theme.heading_line_height = parse_float(value, theme.heading_line_height)
        when "h1_font_size"        then theme.h1_font_size = parse_float(value, theme.h1_font_size)
        when "h1_font_style"       then theme.h1_font_style = value.as_s? || theme.h1_font_style
        when "h1_margin_top"       then theme.h1_margin_top = parse_float(value, theme.h1_margin_top)
        when "h1_margin_bottom"    then theme.h1_margin_bottom = parse_float(value, theme.h1_margin_bottom)
        when "h2_font_size"        then theme.h2_font_size = parse_float(value, theme.h2_font_size)
        when "h2_font_style"       then theme.h2_font_style = value.as_s? || theme.h2_font_style
        when "h2_margin_top"       then theme.h2_margin_top = parse_float(value, theme.h2_margin_top)
        when "h2_margin_bottom"    then theme.h2_margin_bottom = parse_float(value, theme.h2_margin_bottom)
        when "h3_font_size"        then theme.h3_font_size = parse_float(value, theme.h3_font_size)
        when "h3_font_style"       then theme.h3_font_style = value.as_s? || theme.h3_font_style
        when "h3_margin_top"       then theme.h3_margin_top = parse_float(value, theme.h3_margin_top)
        when "h3_margin_bottom"    then theme.h3_margin_bottom = parse_float(value, theme.h3_margin_bottom)
        when "h4_font_size"        then theme.h4_font_size = parse_float(value, theme.h4_font_size)
        when "h4_font_style"       then theme.h4_font_style = value.as_s? || theme.h4_font_style
        when "h4_margin_top"       then theme.h4_margin_top = parse_float(value, theme.h4_margin_top)
        when "h4_margin_bottom"    then theme.h4_margin_bottom = parse_float(value, theme.h4_margin_bottom)
        when "h5_font_size"        then theme.h5_font_size = parse_float(value, theme.h5_font_size)
        when "h5_font_style"       then theme.h5_font_style = value.as_s? || theme.h5_font_style
        when "h5_margin_top"       then theme.h5_margin_top = parse_float(value, theme.h5_margin_top)
        when "h5_margin_bottom"    then theme.h5_margin_bottom = parse_float(value, theme.h5_margin_bottom)
        when "h6_font_size"        then theme.h6_font_size = parse_float(value, theme.h6_font_size)
        when "h6_font_style"       then theme.h6_font_style = value.as_s? || theme.h6_font_style
        when "h6_margin_top"       then theme.h6_margin_top = parse_float(value, theme.h6_margin_top)
        when "h6_margin_bottom"    then theme.h6_margin_bottom = parse_float(value, theme.h6_margin_bottom)
          # Paragraphes
        when "prose_margin_top"    then theme.prose_margin_top = parse_float(value, theme.prose_margin_top)
        when "prose_margin_bottom" then theme.prose_margin_bottom = parse_float(value, theme.prose_margin_bottom)
          # Listes
        when "list_indent"       then theme.list_indent = parse_float(value, theme.list_indent)
        when "list_item_spacing" then theme.list_item_spacing = parse_float(value, theme.list_item_spacing)
        when "list_marker_color" then theme.list_marker_color = value.as_s? || theme.list_marker_color
          # Code
        when "code_font_family"      then theme.code_font_family = value.as_s? || theme.code_font_family
        when "code_font_size"        then theme.code_font_size = parse_float(value, theme.code_font_size)
        when "code_background_color" then theme.code_background_color = value.as_s? || theme.code_background_color
        when "code_border_color"     then theme.code_border_color = value.as_s? || theme.code_border_color
        when "code_border_width"     then theme.code_border_width = parse_float(value, theme.code_border_width)
        when "code_padding"          then theme.code_padding = parse_float(value, theme.code_padding)
        when "code_margin_top"       then theme.code_margin_top = parse_float(value, theme.code_margin_top)
        when "code_margin_bottom"    then theme.code_margin_bottom = parse_float(value, theme.code_margin_bottom)
        when "code_font_color"       then theme.code_font_color = value.as_s? || theme.code_font_color
          # Admonitions
        when "admonition_border_width"    then theme.admonition_border_width = parse_float(value, theme.admonition_border_width)
        when "admonition_padding"         then theme.admonition_padding = parse_float(value, theme.admonition_padding)
        when "admonition_note_color"      then theme.admonition_note_color = value.as_s? || theme.admonition_note_color
        when "admonition_tip_color"       then theme.admonition_tip_color = value.as_s? || theme.admonition_tip_color
        when "admonition_warning_color"   then theme.admonition_warning_color = value.as_s? || theme.admonition_warning_color
        when "admonition_caution_color"   then theme.admonition_caution_color = value.as_s? || theme.admonition_caution_color
        when "admonition_important_color" then theme.admonition_important_color = value.as_s? || theme.admonition_important_color
        when "admonition_note_label"      then theme.admonition_note_label = value.as_s? || theme.admonition_note_label
        when "admonition_tip_label"       then theme.admonition_tip_label = value.as_s? || theme.admonition_tip_label
        when "admonition_warning_label"   then theme.admonition_warning_label = value.as_s? || theme.admonition_warning_label
        when "admonition_caution_label"   then theme.admonition_caution_label = value.as_s? || theme.admonition_caution_label
        when "admonition_important_label" then theme.admonition_important_label = value.as_s? || theme.admonition_important_label
          # Blocs de score (extension x-score-*)
        when "x_score_excellent_color"   then theme.x_score_excellent_color = value.as_s? || theme.x_score_excellent_color
        when "x_score_excellent_label"   then theme.x_score_excellent_label = value.as_s? || theme.x_score_excellent_label
        when "x_score_tres_bien_color"   then theme.x_score_tres_bien_color = value.as_s? || theme.x_score_tres_bien_color
        when "x_score_tres_bien_label"   then theme.x_score_tres_bien_label = value.as_s? || theme.x_score_tres_bien_label
        when "x_score_bien_color"        then theme.x_score_bien_color = value.as_s? || theme.x_score_bien_color
        when "x_score_bien_label"        then theme.x_score_bien_label = value.as_s? || theme.x_score_bien_label
        when "x_score_insuffisant_color" then theme.x_score_insuffisant_color = value.as_s? || theme.x_score_insuffisant_color
        when "x_score_insuffisant_label" then theme.x_score_insuffisant_label = value.as_s? || theme.x_score_insuffisant_label
        when "x_score_a_revoir_color"    then theme.x_score_a_revoir_color = value.as_s? || theme.x_score_a_revoir_color
        when "x_score_a_revoir_label"    then theme.x_score_a_revoir_label = value.as_s? || theme.x_score_a_revoir_label
          # Tableaux
        when "table_border_color"            then theme.table_border_color = value.as_s? || theme.table_border_color
        when "table_border_width"            then theme.table_border_width = parse_float(value, theme.table_border_width)
        when "table_header_background_color" then theme.table_header_background_color = value.as_s? || theme.table_header_background_color
        when "table_header_font_style"       then theme.table_header_font_style = value.as_s? || theme.table_header_font_style
        when "table_cell_padding"            then theme.table_cell_padding = parse_float(value, theme.table_cell_padding)
        when "table_margin_top"              then theme.table_margin_top = parse_float(value, theme.table_margin_top)
        when "table_margin_bottom"           then theme.table_margin_bottom = parse_float(value, theme.table_margin_bottom)
          # Page de titre
        when "title_page_enabled"    then theme.title_page_enabled = parse_bool(value, theme.title_page_enabled)
        when "title_font_size"       then theme.title_font_size = parse_float(value, theme.title_font_size)
        when "title_font_color"      then theme.title_font_color = value.as_s? || theme.title_font_color
        when "title_font_style"      then theme.title_font_style = value.as_s? || theme.title_font_style
        when "subtitle_font_size"    then theme.subtitle_font_size = parse_float(value, theme.subtitle_font_size)
        when "subtitle_font_color"   then theme.subtitle_font_color = value.as_s? || theme.subtitle_font_color
        when "author_font_size"      then theme.author_font_size = parse_float(value, theme.author_font_size)
        when "author_font_color"     then theme.author_font_color = value.as_s? || theme.author_font_color
        when "x_title_page_with_toc" then theme.x_title_page_with_toc = parse_bool(value, theme.x_title_page_with_toc)
          # Table des matières
        when "toc_enabled"          then theme.toc_enabled = parse_bool(value, theme.toc_enabled)
        when "toc_title"            then theme.toc_title = value.as_s? || theme.toc_title
        when "toc_font_size"        then theme.toc_font_size = parse_float(value, theme.toc_font_size)
        when "toc_dot_leader_color" then theme.toc_dot_leader_color = value.as_s? || theme.toc_dot_leader_color
          # En-têtes et pieds de page
        when "header_enabled"    then theme.header_enabled = parse_bool(value, theme.header_enabled)
        when "header_height"     then theme.header_height = parse_float(value, theme.header_height)
        when "header_font_size"  then theme.header_font_size = parse_float(value, theme.header_font_size)
        when "header_font_color" then theme.header_font_color = value.as_s? || theme.header_font_color
        when "header_left"       then theme.header_left = value.as_s? || theme.header_left
        when "header_center"     then theme.header_center = value.as_s? || theme.header_center
        when "header_right"      then theme.header_right = value.as_s? || theme.header_right
        when "footer_enabled"    then theme.footer_enabled = parse_bool(value, theme.footer_enabled)
        when "footer_height"     then theme.footer_height = parse_float(value, theme.footer_height)
        when "footer_font_size"  then theme.footer_font_size = parse_float(value, theme.footer_font_size)
        when "footer_font_color" then theme.footer_font_color = value.as_s? || theme.footer_font_color
        when "footer_left"       then theme.footer_left = value.as_s? || theme.footer_left
        when "footer_center"     then theme.footer_center = value.as_s? || theme.footer_center
        when "footer_right"      then theme.footer_right = value.as_s? || theme.footer_right
          # Index
        when "index_enabled"           then theme.index_enabled = parse_bool(value, theme.index_enabled)
        when "index_title"             then theme.index_title = value.as_s? || theme.index_title
        when "index_columns"           then theme.index_columns = value.as_i? || theme.index_columns
        when "index_font_size"         then theme.index_font_size = parse_float(value, theme.index_font_size)
        when "index_page_number_color" then theme.index_page_number_color = value.as_s? || theme.index_page_number_color
        end
      end
    end

    private def self.parse_float(value : YAML::Any, default : Float64) : Float64
      value.as_f? || value.as_i?.try(&.to_f) || default
    end

    private def self.parse_bool(value : YAML::Any, default : Bool) : Bool
      value.as_bool? || default
    end
  end
end
