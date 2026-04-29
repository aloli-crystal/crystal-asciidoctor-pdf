require "country-flags"

module AsciidoctorPDF
  # Inline flag handling for PDF rendering.
  #
  # Country flag emojis in AsciiDoc are encoded as pairs of consecutive
  # Unicode regional indicator symbols (U+1F1E6 .. U+1F1FF). Standard
  # text fonts (DejaVu Sans and friends) do not contain glyphs for
  # these codepoints, so a naive text render yields tofu boxes and
  # inflated column widths in tables.
  #
  # This helper splits a text string into an ordered list of segments
  # — plain text vs. flag — so the caller can render each segment with
  # the appropriate primitive (text drawing vs. SVG embedding) and
  # compute line widths that account for the flag glyphs.
  module InlineFlags
    # First regional indicator codepoint: 🇦 (U+1F1E6).
    REGIONAL_INDICATOR_A = 0x1F1E6
    # Last regional indicator codepoint: 🇿 (U+1F1FF).
    REGIONAL_INDICATOR_Z = 0x1F1FF

    # Type of a single segment returned by `.segments`.
    # `kind` is `:text` or `:flag`. For `:text`, `value` is the raw
    # substring. For `:flag`, `value` is the ISO 3166-1 alpha-2 code
    # uppercase (e.g. `"FR"`).
    alias Segment = {Symbol, String}

    # Breaks `text` into an alternating sequence of text runs and flag
    # runs. Two consecutive regional indicators collapse into a single
    # `:flag` segment carrying the decoded ISO code.
    #
    # Example:
    # ```
    # InlineFlags.segments("🇫🇷 France")
    # # => [{:flag, "FR"}, {:text, " France"}]
    # ```
    def self.segments(text : String) : Array(Segment)
      result = [] of Segment
      buf = String::Builder.new
      chars = text.chars
      i = 0
      while i < chars.size
        c1 = chars[i]
        c2 = chars[i + 1]?
        if c2 && regional_indicator?(c1) && regional_indicator?(c2)
          if buf.bytesize > 0
            result << {:text, buf.to_s}
            buf = String::Builder.new
          end
          code = String.build(2) do |s|
            s << ('A'.ord + (c1.ord - REGIONAL_INDICATOR_A)).chr
            s << ('A'.ord + (c2.ord - REGIONAL_INDICATOR_A)).chr
          end
          result << {:flag, code}
          i += 2
        else
          buf << c1
          i += 1
        end
      end
      result << {:text, buf.to_s} if buf.bytesize > 0
      result
    end

    # Visual width of a flag glyph at the given font size.
    # Uses the 4:3 aspect ratio of the embedded SVGs with a slight
    # under-sizing so the flag sits visually on the text baseline.
    def self.flag_width(font_size : Float64) : Float64
      flag_height(font_size) * 4.0 / 3.0
    end

    # Visual height of a flag glyph at the given font size. Slightly
    # smaller than the em height so the flag fits inside the line box
    # without clashing with ascenders.
    def self.flag_height(font_size : Float64) : Float64
      font_size * 0.75
    end

    # Returns true if `char` is a Unicode regional indicator symbol.
    private def self.regional_indicator?(char : Char) : Bool
      REGIONAL_INDICATOR_A <= char.ord <= REGIONAL_INDICATOR_Z
    end
  end
end
