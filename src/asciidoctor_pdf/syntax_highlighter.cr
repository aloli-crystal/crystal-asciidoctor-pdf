# Coloration syntaxique pour les blocs de code AsciiDoc.
# Utilise crystal-rouge (233 lexers) pour la tokenisation,
# avec un mapping de couleurs inspiré du thème GitHub.

require "crystal-rouge"

module AsciidoctorPDF
  # Un token de code coloré
  record CodeToken, text : String, color : String

  # Coloration syntaxique via crystal-rouge.
  # Retourne une liste de tokens avec leur couleur hexadécimale.
  module SyntaxHighlighter
    # Couleurs du thème GitHub (fond clair)
    # Mappées depuis les shortnames Rouge/Pygments
    TOKEN_COLORS = {
      # ── Comments ──
      "c"   => "57606a",
      "c1"  => "57606a",
      "cd"  => "57606a",
      "cm"  => "57606a",
      "ch"  => "57606a",
      "cp"  => "cf222e",
      "cpf" => "cf222e",
      "cs"  => "57606a",
      # ── Keywords ──
      "k"  => "cf222e",
      "kc" => "0550ae",
      "kd" => "cf222e",
      "kn" => "cf222e",
      "kp" => "cf222e",
      "kr" => "cf222e",
      "kt" => "953800",
      "kv" => "cf222e",
      # ── Names ──
      "n"  => "1f2328",
      "na" => "116329",
      "nb" => "953800",
      "bp" => "953800",
      "nc" => "953800",
      "no" => "0550ae",
      "nd" => "8250df",
      "ne" => "953800",
      "nf" => "8250df",
      "fm" => "8250df",
      "nl" => "0550ae",
      "nn" => "953800",
      "nx" => "1f2328",
      "nt" => "116329",
      "nv" => "0550ae",
      "vc" => "0550ae",
      "vg" => "0550ae",
      "vi" => "0550ae",
      "vm" => "0550ae",
      "py" => "0550ae",
      "ni" => "1f2328",
      # ── Strings ──
      "s"  => "0a3069",
      "s1" => "0a3069",
      "s2" => "0a3069",
      "sa" => "0a3069",
      "sb" => "0a3069",
      "sc" => "0a3069",
      "sd" => "0a3069",
      "se" => "cf222e",
      "sh" => "0a3069",
      "si" => "0a3069",
      "sr" => "116329",
      "ss" => "0550ae",
      "sx" => "0a3069",
      "dl" => "0a3069",
      # ── Numbers / Literals ──
      "m"  => "0550ae",
      "mb" => "0550ae",
      "mf" => "0550ae",
      "mh" => "0550ae",
      "mi" => "0550ae",
      "il" => "0550ae",
      "mo" => "0550ae",
      "mx" => "0550ae",
      "l"  => "0550ae",
      "ld" => "0550ae",
      # ── Operators ──
      "o"  => "0550ae",
      "ow" => "cf222e",
      # ── Punctuation ──
      "p"  => "1f2328",
      "pi" => "1f2328",
      # ── Generic ──
      "gd" => "cf222e",
      "gh" => "0550ae",
      "gi" => "116329",
      "go" => "57606a",
      "gp" => "57606a",
      "gu" => "0550ae",
      "gt" => "cf222e",
      "gr" => "cf222e",
      # ── Error ──
      "err" => "cf222e",
      # ── Escape ──
      "esc" => "1f2328",
      # ── Whitespace ──
      "w" => "57606a",
    }

    DEFAULT_COLOR = "1f2328"

    # Tokenise une ligne de code pour un langage donné.
    # Retourne un tableau de CodeToken avec texte et couleur.
    def self.tokenize(line : String, language : String) : Array(CodeToken)
      lang = language.downcase
      lexer = Rouge::RegexLexer.find(lang)

      # Fallback : texte brut si le langage n'est pas reconnu
      unless lexer
        return [CodeToken.new(line, DEFAULT_COLOR)]
      end

      tokens = [] of CodeToken
      lexer.lex(line) do |token, text|
        next if text.empty?
        color = TOKEN_COLORS[token.shortname]? || DEFAULT_COLOR
        # Fusionner les tokens consécutifs de même couleur
        if (last = tokens.last?) && last.color == color
          tokens[-1] = CodeToken.new(last.text + text, color)
        else
          tokens << CodeToken.new(text, color)
        end
      end

      # Si le lexer ne produit rien, renvoyer la ligne brute
      tokens.empty? ? [CodeToken.new(line, DEFAULT_COLOR)] : tokens
    end
  end
end
