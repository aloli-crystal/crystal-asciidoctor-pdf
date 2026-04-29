require "pdf"
require "country-flags"
require "./inline_flags"

module AsciidoctorPDF
  # Segment de texte inline avec ses attributs de style.
  # `sup`/`sub` activent l'exposant / l'indice (taille réduite + décalage
  # vertical au rendu). `mark` active un fond de surlignage. `kbd`,
  # `button`, `menu` correspondent aux macros AsciiDoc :
  # `kbd:[Ctrl+C]`, `btn:[OK]`, `menu:[Fichier > Quitter]`.
  record InlineSegment,
    text : String,
    bold : Bool = false,
    italic : Bool = false,
    mono : Bool = false,
    sup : Bool = false,
    sub : Bool = false,
    mark : Bool = false,
    kbd : Bool = false,
    button : Bool = false,
    menu : Bool = false,
    color : String? = nil,
    link : String? = nil

  # Rend le markup inline HTML généré par crystal-asciidoctor sur une page PDF.
  # Gère les balises <strong>, <em>, <code>, <a href>, <span style="color:...">, etc.
  module InlineRenderer
    # Parse une chaîne HTML inline et retourne une liste de segments stylisés.
    def self.parse(html : String) : Array(InlineSegment)
      segments = [] of InlineSegment
      return segments if html.empty?

      # Normalise les retours à la ligne en espaces (en HTML, un `\n`
      # dans un paragraphe est de l'espace, mais les polices l'affichent
      # sinon en tofu). Les espaces insécables sont décodés vers le vrai
      # caractère U+00A0 pour que `wrap_text` (qui ne casse que sur
      # l'espace ASCII) conserve la propriété insécable ; ils seront
      # remplacés par un espace ASCII juste avant chaque `page.text`
      # pour éviter un tofu quand la police n'a pas de glyphe NBSP.
      text = html
        .gsub(/&amp;/, "&")
        .gsub(/&lt;/, "<")
        .gsub(/&gt;/, ">")
        .gsub(/&quot;/, "\"")
        .gsub(/&#8220;/, "\u201C")
        .gsub(/&#8221;/, "\u201D")
        .gsub(/&#8216;/, "\u2018")
        .gsub(/&#8217;/, "\u2019")
        .gsub(/&#8230;/, "\u2026")
        .gsub(/&#8249;/, "\u2039") # single left-pointing angle quote
        .gsub(/&#8250;/, "\u203a") # single right-pointing angle quote (caret menu)
        .gsub(/&hellip;/, "\u2026")
        .gsub(/&laquo;/, "\u00ab")
        .gsub(/&raquo;/, "\u00bb")
        .gsub(/&mdash;/, "\u2014")
        .gsub(/&ndash;/, "\u2013")
        .gsub(/&#160;/, "\u00A0")
        .gsub(/&nbsp;/, "\u00A0")
        .gsub(/\s+/, " ")

      # Parcourir le HTML avec un état de style courant
      parse_html(text, segments)
      segments
    end

    # Rend une liste de segments inline sur une page PDF à la position donnée.
    # Retourne la nouvelle position X après le rendu (pour le texte sur une ligne).
    def self.render_line(
      page : PDF::Page,
      segments : Array(InlineSegment),
      x : Float64,
      y : Float64,
      base_font_size : Float64,
      base_color : String,
      theme : Theme,
    ) : Float64
      current_x = x
      flag_w = InlineFlags.flag_width(base_font_size)
      flag_h = InlineFlags.flag_height(base_font_size)

      segments.each do |seg|
        next if seg.text.empty?

        font_name = resolve_font(seg, theme)
        page.font(font_name, size: base_font_size)
        page.fill_color(seg.color || base_color)
        font = PDF::Fonts::Type1.new(font_name)

        # Split the segment into text and flag runs. Flag emojis are
        # drawn as real colour SVGs; plain text keeps the segment's
        # styling (bold/italic/mono/colour).
        InlineFlags.segments(seg.text).each do |(kind, value)|
          if kind == :flag
            if (svg_data = CountryFlags.svg(value))
              page.svg(svg_data, at: {current_x, y + flag_h}, width: flag_w, height: flag_h)
            else
              page.text("[#{value}]", at: {current_x, y})
            end
            current_x += flag_w
          else
            # Substitue U+00A0 par un espace ASCII au moment du dessin.
            # Le NBSP a été préservé jusqu'ici pour que le wrap ne le
            # casse pas (insécabilité conservée) ; l'emit PDF utilise
            # un espace ordinaire pour éviter un tofu avec les polices
            # qui n'ont pas de glyphe NBSP.
            printable = value.gsub('\u00A0', ' ')
            page.text(printable, at: {current_x, y})
            current_x += font.string_width(printable, base_font_size)
          end
        end
      end
      current_x
    end

    # Résout le nom de la police PDF en fonction des attributs du segment.
    private def self.resolve_font(seg : InlineSegment, theme : Theme) : String
      if seg.mono
        "Courier"
      elsif seg.bold && seg.italic
        "Helvetica-BoldOblique"
      elsif seg.bold
        "Helvetica-Bold"
      elsif seg.italic
        "Helvetica-Oblique"
      else
        "Helvetica"
      end
    end

    # Parse le HTML inline et peuple le tableau de segments.
    private def self.parse_html(html : String, segments : Array(InlineSegment)) : Nil
      # Pile de contextes de style
      bold_depth = 0
      italic_depth = 0
      mono_depth = 0
      sup_depth = 0
      sub_depth = 0
      mark_depth = 0
      kbd_depth = 0
      button_depth = 0
      menu_depth = 0
      color_stack = [] of String
      link_stack = [] of String

      flush = ->(buffered : String) {
        return if buffered.empty?
        segments << InlineSegment.new(
          text: buffered,
          bold: bold_depth > 0,
          italic: italic_depth > 0,
          mono: mono_depth > 0 || kbd_depth > 0,
          sup: sup_depth > 0,
          sub: sub_depth > 0,
          mark: mark_depth > 0,
          kbd: kbd_depth > 0,
          button: button_depth > 0,
          menu: menu_depth > 0,
          color: color_stack.last?,
          link: link_stack.last?
        )
      }

      i = 0
      buf = ""

      while i < html.size
        if html[i] == '<'
          flush.call(buf)
          buf = ""

          # Trouver la fin de la balise
          j = html.index('>', i)
          break unless j
          tag = html[i + 1, j - i - 1].strip
          i = j + 1

          if tag.starts_with?('/')
            # Balise fermante
            tag_name = tag[1..].split(/[\s>]/)[0].downcase
            case tag_name
            when "strong", "b"
              # `<b class="button|menu|menuitem|submenu|caret">` : on a
              # déjà géré l'ouverture comme un button/menu, donc fermer
              # ces compteurs prioritairement avant de toucher au gras.
              if button_depth > 0
                button_depth -= 1
              elsif menu_depth > 0
                menu_depth -= 1
              else
                bold_depth = [0, bold_depth - 1].max
              end
            when "em", "i"    then italic_depth = [0, italic_depth - 1].max
            when "code", "tt" then mono_depth = [0, mono_depth - 1].max
            when "kbd"        then kbd_depth = [0, kbd_depth - 1].max
            when "sup"        then sup_depth = [0, sup_depth - 1].max
            when "sub"        then sub_depth = [0, sub_depth - 1].max
            when "mark"       then mark_depth = [0, mark_depth - 1].max
            when "span"
              # `<span class="keyseq|menuseq">` ou `<span style="color:...">`
              # — on dépile la couleur uniquement si on en a empilé une.
              # Pour les keyseq/menuseq, l'ouverture n'a rien empilé.
              color_stack.pop? if !color_stack.empty?
            when "a" then link_stack.pop? if !link_stack.empty?
            end
          else
            # Balise ouvrante
            tag_name = tag.split(/[\s>]/)[0].downcase
            case tag_name
            when "strong" then bold_depth += 1
            when "b"
              # `<b class="button">` (btn:[]), `<b class="menu|menuitem|
              # submenu|caret">` (menu:[]) : typographier différemment
              # selon le rôle. Sans classe : c'est un gras générique.
              if (m = tag.match(/class\s*=\s*["']([^"']+)["']/))
                klass = m[1]
                case klass
                when "button" then button_depth += 1
                when "menu", "menuitem", "submenu", "caret", "menuref"
                  menu_depth += 1
                else bold_depth += 1
                end
              else
                bold_depth += 1
              end
            when "em", "i"    then italic_depth += 1
            when "code", "tt" then mono_depth += 1
            when "kbd"        then kbd_depth += 1
            when "sup"        then sup_depth += 1
            when "sub"        then sub_depth += 1
            when "mark"       then mark_depth += 1
            when "br"         then buf += " " # hard line break — espace
            # pour l'instant. Un vrai `<br>` exigerait un saut de ligne
            # explicite dans la render pipeline ; un `\n` litéral
            # afficherait un tofu (pas de glyphe newline en Type1).
            when "span"
              # Extraire la couleur du style si présente, sinon ne rien
              # empiler (les `<span class="keyseq|menuseq">` n'apportent
              # pas de style typographique en eux-mêmes — ce sont leurs
              # enfants `<kbd>` / `<b class="menu">` qui le font).
              if (m = tag.match(/style\s*=\s*["']?[^"'>]*color\s*:\s*#?([0-9a-fA-F]{6})/))
                color_stack << m[1]
              elsif tag.includes?("color")
                color_stack << (color_stack.last? || "333333")
              end
            when "a"
              if (m = tag.match(/href\s*=\s*["']([^"']+)["']/))
                link_stack << m[1]
              end
            end
          end
        else
          buf += html[i].to_s
          i += 1
        end
      end

      # Flush le buffer restant
      flush.call(buf)
    end
  end
end
