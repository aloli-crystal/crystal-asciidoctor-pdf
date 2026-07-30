module AsciicrystalPDF
  # Helpers pour l'encodage WinAnsi (Windows-1252) utilisé par les
  # polices Type1 standard (Helvetica, Courier) — par défaut dans
  # asciicrystal-pdf.
  #
  # WinAnsi couvre ~220 codepoints :
  #
  # * ASCII imprimable (U+0020 à U+007E)
  # * Latin-1 Supplement (U+00A0 à U+00FF) — accents européens
  # * Une vingtaine d'extras dans la zone 0x80-0x9F de Windows-1252
  #   (€, smart quotes, em-dash, …) qui correspondent à des
  #   codepoints au-delà de Latin-1 dans Unicode
  #
  # Tout caractère hors de cette plage (emojis ✅ ❌ 🔴, dingbats
  # ✓ ✗, idéogrammes CJK, etc.) ne peut pas être rendu par les
  # polices Type1 — il sortirait en tofu silencieux.
  #
  # `sanitize` substitue ces caractères par `?` et signale chaque
  # substitution via le bloc fourni, ce qui permet à l'appelant
  # d'émettre un warning unique (cf. `Converter#warn_unrenderable`).
  module WinAnsi
    # Codepoints Unicode de la zone 0x80-0x9F de Windows-1252.
    # Cette table doit rester synchronisée avec celle de
    # `crystal-watermark/src/crystal_watermark/pdf_watermarker.cr`.
    EXTRA_CHARS = Set{
      0x0152, 0x0153, # Œ œ
      0x0160, 0x0161, # Š š
      0x0178,         # Ÿ
      0x017D, 0x017E, # Ž ž
      0x0192,         # ƒ
      0x02C6, 0x02DC, # ˆ ˜
      0x2013, 0x2014, # – —
      0x2018, 0x2019, # ' '
      0x201A,         # ‚
      0x201C, 0x201D, # " "
      0x201E,         # „
      0x2020, 0x2021, # † ‡
      0x2022,         # •
      0x2026,         # …
      0x2030,         # ‰
      0x2039, 0x203A, # ‹ ›
      0x20AC,         # €
      0x2122,         # ™
    }

    # Vérifie qu'un caractère est représentable par une police Type1
    # à encodage WinAnsi.
    def self.representable?(char : Char) : Bool
      code = char.ord
      return true if code < 0x80                  # ASCII
      return true if (0xA0..0xFF).includes?(code) # Latin-1 Supplement
      EXTRA_CHARS.includes?(code)
    end

    # Substitue tout caractère non représentable par `?` et appelle
    # le bloc pour chaque substitution (avec le caractère original).
    # Retourne la chaîne sanitisée. Les caractères acceptables sont
    # copiés tels quels.
    def self.sanitize(text : String, & : Char ->) : String
      String.build do |io|
        text.each_char do |char|
          if representable?(char)
            io << char
          else
            io << '?'
            yield char
          end
        end
      end
    end

    # Variante sans callback : sanitise silencieusement. À éviter
    # dans le pipeline normal du Converter (qui veut warner) ; utile
    # pour les call-sites où la substitution n'est pas signalable
    # (ex. metadata internes).
    def self.sanitize(text : String) : String
      sanitize(text) { |_| }
    end
  end
end
