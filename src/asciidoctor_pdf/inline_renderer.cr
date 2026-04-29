require "pdf/src/pdf"
require "flags/src/crystal_flags"
require "./inline_flags"

module AsciidoctorPDF
  # Segment de texte inline avec ses attributs de style
  record InlineSegment,
    text : String,
    bold : Bool = false,
    italic : Bool = false,
    mono : Bool = false,
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
            if (svg_data = CrystalFlags.svg(value))
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
      color_stack = [] of String
      link_stack = [] of String

      i = 0
      buf = ""

      while i < html.size
        if html[i] == '<'
          # Flush le buffer courant
          unless buf.empty?
            segments << InlineSegment.new(
              text: buf,
              bold: bold_depth > 0,
              italic: italic_depth > 0,
              mono: mono_depth > 0,
              color: color_stack.last?,
              link: link_stack.last?
            )
            buf = ""
          end

          # Trouver la fin de la balise
          j = html.index('>', i)
          break unless j
          tag = html[i + 1, j - i - 1].strip
          i = j + 1

          if tag.starts_with?('/')
            # Balise fermante
            tag_name = tag[1..].split(/[\s>]/)[0].downcase
            case tag_name
            when "strong", "b" then bold_depth = [0, bold_depth - 1].max
            when "em", "i"     then italic_depth = [0, italic_depth - 1].max
            when "code", "tt"  then mono_depth = [0, mono_depth - 1].max
            when "span"        then color_stack.pop? if !color_stack.empty?
            when "a"           then link_stack.pop? if !link_stack.empty?
            end
          else
            # Balise ouvrante
            tag_name = tag.split(/[\s>]/)[0].downcase
            case tag_name
            when "strong", "b" then bold_depth += 1
            when "em", "i"     then italic_depth += 1
            when "code", "tt"  then mono_depth += 1
            when "br"          then buf += " " # hard line break: treat
            # as a space for now. A real `<br>` would need the render
            # pipeline to emit an explicit line split at this point;
            # keeping a literal `\n` draws a tofu box because Type1
            # fonts have no glyph for newline.
            when "span"
              # Extraire la couleur du style
              if (m = tag.match(/style\s*=\s*["']?[^"'>]*color\s*:\s*#?([0-9a-fA-F]{6})/))
                color_stack << m[1]
              else
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
      unless buf.empty?
        segments << InlineSegment.new(
          text: buf,
          bold: bold_depth > 0,
          italic: italic_depth > 0,
          mono: mono_depth > 0,
          color: color_stack.last?,
          link: link_stack.last?
        )
      end
    end
  end
end
