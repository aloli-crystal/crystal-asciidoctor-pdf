require "crystal-pdf/src/pdf"

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

      # Décoder les entités HTML basiques
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
        .gsub(/&#160;/, " ")

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
      theme : Theme
    ) : Float64
      current_x = x
      segments.each do |seg|
        next if seg.text.empty?

        font_name = resolve_font(seg, theme)
        page.font(font_name, size: base_font_size)
        page.fill_color(seg.color || base_color)
        page.text(seg.text, at: {current_x, y})

        # Use proper font metrics for text width advancement
        font = PDF::Fonts::Type1.new(font_name)
        current_x += font.string_width(seg.text, base_font_size)
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
            when "br"          then buf += "\n"
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
