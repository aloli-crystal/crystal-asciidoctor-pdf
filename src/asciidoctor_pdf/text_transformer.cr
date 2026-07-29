module AsciicrystalPDF
  # Transformations typographiques du texte : majuscules, capitales,
  # petites capitales. Portage du `text_transformer.rb` upstream Ruby
  # asciidoctor-pdf 2.3.24.
  #
  # Usage : appliquer juste avant le rendu PDF, sur du texte déjà
  # nettoyé (post-Sanitizer). Pas de gestion du HTML inline ici —
  # le caller doit avoir fait son strip de balises s'il le faut.
  module TextTransformer
    # Caractères small-caps Unicode : alphabet latin majuscule où
    # chaque lettre prend l'apparence d'une petite capitale. NOTE :
    # `f` → `ғ` (latin majuscule) et `q` → `ǫ` au lieu de `ꜰ` / `ꞯ`
    # parce que les premières sont plus largement supportées par les
    # polices courantes (Helvetica, DejaVu, …).
    SMALL_CAPS_MAP = {
      'a' => 'ᴀ', 'b' => 'ʙ', 'c' => 'ᴄ', 'd' => 'ᴅ', 'e' => 'ᴇ',
      'f' => 'ғ', 'g' => 'ɢ', 'h' => 'ʜ', 'i' => 'ɪ', 'j' => 'ᴊ',
      'k' => 'ᴋ', 'l' => 'ʟ', 'm' => 'ᴍ', 'n' => 'ɴ', 'o' => 'o',
      'p' => 'ᴘ', 'q' => 'ǫ', 'r' => 'ʀ', 's' => 's', 't' => 'ᴛ',
      'u' => 'ᴜ', 'v' => 'ᴠ', 'w' => 'ᴡ', 'x' => 'x', 'y' => 'ʏ',
      'z' => 'ᴢ',
    }

    # Met chaque mot en capitalize : « hello world » → « Hello World ».
    # Définition d'un mot : suite de caractères graphiques contigus
    # (la regex `\S+` est suffisante pour la plupart des cas FR/EN
    # et plus simple que la version `\p{Graph}+` Ruby).
    def self.capitalize_words(string : String) : String
      string.gsub(/\S+/) do |word|
        first = word[0]?
        first ? "#{first.to_s.upcase}#{word[1..]}" : word
      end
    end

    # Convertit en majuscules. Wrapper trivial — exposé pour parité
    # API et lisibilité côté caller.
    def self.uppercase(string : String) : String
      string.upcase
    end

    # Petites capitales : remplace les lettres minuscules par leurs
    # équivalents Unicode small-caps. Les majuscules, chiffres et
    # ponctuation restent inchangés.
    def self.smallcaps(string : String) : String
      String.build do |io|
        string.each_char do |c|
          io << (SMALL_CAPS_MAP[c.to_s.downcase[0]]? || c)
        end
      end
    end

    # Applique une transformation nommée. Valeurs reconnues :
    # `"uppercase"`, `"smallcaps"`, `"capitalize"`. Tout autre valeur
    # (incluant nil, "none", "") laisse le texte intact.
    def self.apply(string : String, transform : String?) : String
      case transform
      when "uppercase"  then uppercase(string)
      when "smallcaps"  then smallcaps(string)
      when "capitalize" then capitalize_words(string)
      else                   string
      end
    end
  end
end
