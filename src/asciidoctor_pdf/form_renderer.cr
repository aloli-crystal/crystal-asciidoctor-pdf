module AsciidoctorPDF
  # Rendu d'un bloc `[x-form]` parsé par `FormBuilder` vers du PDF
  # interactif (widgets AcroForm) avec labels visuels.
  #
  # Le rendu utilise les méthodes du shard `pdf` :
  #
  # * `PDF::Page#text(content, at: {x, y})` — labels et descriptions
  # * `PDF::AcroForm::Form#text_field`, `#checkbox`, `#radio_group`,
  #   `#dropdown`, `#listbox` — widgets interactifs
  #
  # Le layout est un *flow auto* avec multi-colonnes : les champs
  # remplissent les colonnes gauche → droite, puis sautent à la ligne
  # quand la rangée est pleine ou qu'un span ne tient pas.
  #
  # ## Convention de coordonnées
  #
  # PDF utilise (x, y) avec y croissant vers le haut, origine au coin
  # bas-gauche de la page. `cursor_y` désigne ici la position
  # verticale courante (qui descend lors du rendu).
  module FormRenderer
    # Espacement par défaut entre colonnes (points).
    DEFAULT_GUTTER = 10.0

    # Hauteur du widget text/email/url/tel/number/date/password.
    DEFAULT_FIELD_H = 18.0

    # Hauteur d'une ligne de textarea.
    TEXTAREA_LINE_H = 14.0

    # Hauteur entre deux options d'un radio group.
    RADIO_OPTION_SPACING = 18.0

    # Hauteur du widget select-multi (listbox).
    DEFAULT_LISTBOX_H = 60.0

    # Couleurs des libellés (n'apparaissent qu'en monochrome — le
    # converter actuel gère le noir uniquement).
    LABEL_FONT_SIZE         =  9.0
    LABEL_GAP               =  4.0
    HELP_FONT_SIZE          =  8.0
    HELP_GAP                =  2.0
    SECTION_TITLE_FONT_SIZE = 12.0
    SECTION_DESC_FONT_SIZE  =  9.0
    FORM_TITLE_FONT_SIZE    = 14.0
    FORM_DESC_FONT_SIZE     = 10.0

    # Helper : largeur d'une colonne pour `columns` colonnes
    # totales et `content_width` disponibles.
    def self.column_width(columns : Int32, content_width : Float64,
                          gutter : Float64 = DEFAULT_GUTTER) : Float64
      raise ArgumentError.new("columns must be >= 1") if columns < 1
      ((content_width - gutter * (columns - 1)) / columns).to_f
    end

    # Helper : hauteur estimée du widget pour un champ.
    def self.widget_height(field : FormField) : Float64
      case field.type
      when "textarea"
        ((field.rows || 4) * TEXTAREA_LINE_H).to_f
      when "radio"
        (field.option_codes.size * RADIO_OPTION_SPACING).to_f
      when "select-multi"
        DEFAULT_LISTBOX_H
      else
        DEFAULT_FIELD_H
      end
    end

    # Helper : `field.cols` borné dans `[1, max_cols]`.
    def self.clamped_span(field : FormField, max_cols : Int32) : Int32
      s = field.cols
      s = 1 if s < 1
      s = max_cols if s > max_cols
      s
    end
  end
end
