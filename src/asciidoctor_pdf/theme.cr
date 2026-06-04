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
    # Alignement par défaut du texte des paragraphes.
    # Valeurs : "left", "center", "right", "justify".
    # Défaut conforme à la spec asciidoctor-pdf Ruby (base_align: justify).
    property base_text_align : String = "justify"

    # --- Typographie française (extension `x-`) ---
    # Si vrai, le converter remplace l'espace ordinaire devant les
    # signes de ponctuation à deux parties (`:`, `;`, `!`, `?`, `»`)
    # et après le guillemet ouvrant `«` par un espace insécable
    # (U+00A0). Respecte la règle de l'Imprimerie nationale. Activé
    # par défaut dans le thème `fr`, désactivé dans les autres pour
    # ne pas surprendre les documents non-francophones.
    property x_french_typography : Bool = false

    # --- Code inline (codespan) ---
    # Spec asciidoctor-pdf Ruby — catégorie `codespan` du thème :
    # rendu HTML `<code>` (issu de `` `text` ``) avec fond grisé,
    # bordure optionnelle, padding et couleur de texte.
    property codespan_background_color : String = "f5f5f5"
    property codespan_border_color : String = ""
    property codespan_border_width : Float64 = 0.0
    property codespan_font_color : String = ""
    property codespan_padding_x : Float64 = 2.0
    property codespan_padding_y : Float64 = 1.0

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
    # Transformation typographique appliquée au texte des titres
    # (sections, doctitle, page de garde). Valeurs reconnues :
    # `"uppercase"`, `"smallcaps"`, `"capitalize"`. nil ⇒ aucune.
    property heading_text_transform : String? = nil
    property title_page_text_transform : String? = nil

    # Niveau 0 = « part » en AsciiDoc (rare, mais valide quand le
    # doctitle a été redéfini en section de niveau 0 par défaut, ou
    # quand un `=` apparaît à l'intérieur du flux). On le typographie
    # comme un grand titre, sensiblement plus gros que h1.
    property h0_font_size : Float64 = 26.0
    # Saut de page automatique avant un titre de niveau ≤ valeur
    # (mode « chapter »). 0 = désactivé (défaut, mode article).
    # Mettre à 1 pour qu'un H1 commence systématiquement sur une
    # nouvelle page — convention pour les livres et les rapports.
    property heading_chapter_break_before : Int32 = 0
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
    # Couleur du marqueur « ↳ » signalant une ligne de code repliée
    # automatiquement (trop longue pour l'encadré). Ambre par défaut
    # (couleur d'avertissement) : alerte le lecteur que la ligne a
    # été coupée et que le copier-coller insérera un saut de ligne.
    property code_wrap_marker_color : String = "f0ad4e"

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

    # Mode encadré pour les admonitions. Quand `true`, le rendu ajoute
    # un rectangle entourant (avec fond, bordure et ombre portée
    # optionnelle). La bande verticale colorée et le label restent
    # *à l'intérieur* du cadre. Activable globalement via le thème, ou
    # ponctuellement via le rôle AsciiDoc `[NOTE,role=boxed]`.
    property admonition_boxed : Bool = false
    property admonition_box_background_color : String = "ffffff"
    property admonition_box_border_color : String = "cccccc"
    property admonition_box_border_width : Float64 = 0.5
    # Ombre portée façon « card » : un rectangle gris décalé en
    # bas-droite. Désactivable.
    property admonition_box_shadow_enabled : Bool = true
    property admonition_box_shadow_color : String = "dddddd"
    property admonition_box_shadow_offset : Float64 = 2.5

    # Étiquettes des admonitions. Défauts en anglais (parité Ruby
    # asciidoctor-pdf). Pour traduire : soit redéfinir ici via le thème
    # YAML (`admonition_note_label: NOTE` etc.), soit per-document via
    # les attributs AsciiDoc `:note-caption: NOTE`, `:tip-caption: …`,
    # `:warning-caption: …`, `:caution-caption: …`,
    # `:important-caption: …` — l'attribut document écrase le thème.
    # --- Sidebar (`****` ou `[sidebar]`) ---
    # Encadré gris clair, type aside, pour mettre en valeur une digression.
    property sidebar_background_color : String = "f5f5f5"
    property sidebar_border_color : String = "cccccc"
    property sidebar_border_width : Float64 = 0.6
    property sidebar_padding : Float64 = 10.0
    property sidebar_margin_top : Float64 = 8.0
    property sidebar_margin_bottom : Float64 = 8.0
    property sidebar_title_font_color : String = "1a1a1a"
    property sidebar_title_font_size : Float64 = 11.0

    # --- Example block (`====` ou `[example]`) ---
    # Encadré simple à fond très léger pour les exemples illustratifs.
    property example_background_color : String = "fafafa"
    property example_border_color : String = "dddddd"
    property example_border_width : Float64 = 0.5
    property example_padding : Float64 = 10.0
    property example_margin_top : Float64 = 8.0
    property example_margin_bottom : Float64 = 8.0
    property example_title_font_color : String = "555555"
    property example_title_font_size : Float64 = 10.0

    property admonition_note_label : String = "NOTE"
    property admonition_tip_label : String = "TIP"
    property admonition_warning_label : String = "WARNING"
    property admonition_caution_label : String = "CAUTION"
    property admonition_important_label : String = "IMPORTANT"

    # --- Blocs de score (extension `x-score-*`) ---
    # Cinq niveaux qualitatifs prédéfinis pour les barèmes de quiz.
    # Activés via le rôle AsciiDoc `[.x-score-<niveau>]` sur un bloc
    # delimited (`====` example ou `--` open). Couleurs/libellés
    # personnalisables ci-dessous.
    #
    # Les **identifiants** des niveaux (`excellent`, `tres-bien`, `bien`,
    # `insuffisant`, `a-revoir`) sont en français — ils sont gravés dans
    # la syntaxe AsciiDoc côté utilisateur. Les **libellés** par défaut
    # sont en anglais, parité avec le reste du thème (NOTE, TIP, …) ;
    # le thème embarqué `fr` les surcharge en français.
    property x_score_excellent_color : String = "2e7d32"
    property x_score_excellent_label : String = "EXCELLENT"
    property x_score_tres_bien_color : String = "66bb6a"
    property x_score_tres_bien_label : String = "VERY GOOD"
    property x_score_bien_color : String = "fbc02d"
    property x_score_bien_label : String = "GOOD"
    property x_score_insuffisant_color : String = "ff9800"
    property x_score_insuffisant_label : String = "INSUFFICIENT"
    property x_score_a_revoir_color : String = "d32f2f"
    property x_score_a_revoir_label : String = "NEEDS REVIEW"

    # Mode encadré pour les blocs `[.x-score-*]` (mêmes options que
    # les admonitions). Le cadre + l'ombre rendent la mise en valeur
    # plus marquée pour un barème de quiz / fiche d'évaluation.
    property x_score_boxed : Bool = false
    property x_score_box_background_color : String = "ffffff"
    property x_score_box_border_color : String = "cccccc"
    property x_score_box_border_width : Float64 = 0.5
    property x_score_box_shadow_enabled : Bool = true
    property x_score_box_shadow_color : String = "dddddd"
    property x_score_box_shadow_offset : Float64 = 2.5

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
    # AsciiDoc `:x-title-page-toc:`.
    #
    # Le préfixe `x_` (pour `x-` côté YAML) marque cette propriété
    # comme **extension non standard** propre au shard, sans équivalent
    # dans AsciiDoc / Ruby asciidoctor-pdf — convention héritée de
    # `X-*` dans HTTP/MIME.
    property x_title_page_with_toc : Bool = false

    # Alignement horizontal du titre H1 sur les pages de garde et le
    # doctitle inline. Valeurs reconnues : `"left"` (défaut),
    # `"center"`, `"right"`. Override per-document via l'attribut
    # AsciiDoc `:title-page-align: center`.
    property title_page_align : String = "left"

    # --- Table des matières ---
    property toc_enabled : Bool = true
    property toc_title : String = "Table des matières"
    property toc_font_size : Float64 = 10.0
    property toc_dot_leader_color : String = "aaaaaa"

    # --- En-têtes et pieds de page ---
    # Convention recto-verso (parité Ruby asciidoctor-pdf) :
    #   * `header_left` / `header_center` / `header_right`
    #     sont les défauts, appliqués à toutes les pages.
    #   * `header_recto_*` surchargent sur les pages impaires (recto)
    #     si non vide (chaîne vide → fallback sur le défaut neutre).
    #   * `header_verso_*` surchargent sur les pages paires (verso)
    #     si non vide.
    # Idem pour le pied de page. Activé via le thème uniquement —
    # n'a d'intérêt que pour les documents destinés à l'impression
    # double-face (livres, rapports formels).
    property header_enabled : Bool = false
    property header_height : Float64 = 20.0
    property header_border_width : Float64 = 0.5
    property header_border_color : String = "cccccc"
    property header_font_size : Float64 = 9.0
    property header_font_color : String = "888888"
    property header_left : String = ""
    property header_center : String = ""
    property header_right : String = "{page_number}"
    # Recto-verso optionnels (vide ⇒ on garde le défaut neutre)
    property header_recto_left : String = ""
    property header_recto_center : String = ""
    property header_recto_right : String = ""
    property header_verso_left : String = ""
    property header_verso_center : String = ""
    property header_verso_right : String = ""

    property footer_enabled : Bool = true
    property footer_height : Float64 = 20.0
    property footer_border_width : Float64 = 0.5
    property footer_border_color : String = "cccccc"
    property footer_font_size : Float64 = 9.0
    property footer_font_color : String = "888888"
    property footer_left : String = "{document_title}"
    property footer_center : String = ""
    property footer_right : String = "{page_number}"
    property footer_recto_left : String = ""
    property footer_recto_center : String = ""
    property footer_recto_right : String = ""
    property footer_verso_left : String = ""
    property footer_verso_center : String = ""
    property footer_verso_right : String = ""

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

    # Retourne la taille de police pour un niveau de titre donné (0-6).
    # Le niveau 0 (« part ») est rendu comme un grand titre dédié.
    def heading_font_size(level : Int32) : Float64
      case level
      when 0 then h0_font_size
      when 1 then h1_font_size
      when 2 then h2_font_size
      when 3 then h3_font_size
      when 4 then h4_font_size
      when 5 then h5_font_size
      else        h6_font_size
      end
    end

    # Retourne la marge supérieure pour un niveau de titre donné.
    # Le niveau 0 (part) reprend la marge de h1.
    def heading_margin_top(level : Int32) : Float64
      case level
      when 0 then h1_margin_top
      when 1 then h1_margin_top
      when 2 then h2_margin_top
      when 3 then h3_margin_top
      when 4 then h4_margin_top
      when 5 then h5_margin_top
      else        h6_margin_top
      end
    end

    # Retourne la marge inférieure pour un niveau de titre donné.
    # Le niveau 0 (part) reprend la marge de h1.
    def heading_margin_bottom(level : Int32) : Float64
      case level
      when 0 then h1_margin_bottom
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
