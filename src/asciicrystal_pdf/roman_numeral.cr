module AsciicrystalPDF
  # Conversion arabe → romain pour la numérotation front-matter
  # (« i, ii, iii, iv, … »). Parité avec `roman_numeral.rb` de
  # Ruby asciicrystal-pdf, sauf qu'ici on émet en *minuscules* par
  # défaut — c'est la convention typographique des front-matter.
  module RomanNumeral
    # Couples (valeur, symbole) ordonnés du plus grand au plus petit
    # pour la conversion gloutonne classique.
    PAIRS = [
      {1000, "m"}, {900, "cm"}, {500, "d"}, {400, "cd"},
      {100, "c"}, {90, "xc"}, {50, "l"}, {40, "xl"},
      {10, "x"}, {9, "ix"}, {5, "v"}, {4, "iv"}, {1, "i"},
    ]

    # Convertit `n` (entier positif) en chiffres romains minuscules.
    # `n` doit être ≥ 1 ; pour 0 ou négatif, retourne une chaîne vide
    # — pas d'équivalent romain.
    def self.format(n : Int32) : String
      return "" if n < 1
      result = String.build do |s|
        remaining = n
        PAIRS.each do |(value, sym)|
          while remaining >= value
            s << sym
            remaining -= value
          end
        end
      end
      result
    end

    # Variante majuscules pour les rares cas où le typographe préfère.
    def self.format_upper(n : Int32) : String
      format(n).upcase
    end
  end
end
