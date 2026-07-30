module AsciicrystalPDF
  # Utilitaires texte pour le pipeline asciicrystal-pdf : strip de
  # balises XML / HTML, résolution d'entités HTML, encodage XML.
  #
  # ATTENTION : ce module n'est *pas* un sanitizer de sécurité. Il ne
  # protège pas contre XSS, ni les injections HTML hostiles. C'est
  # un utilitaire de normalisation texte interne au converter PDF.
  # Pour la vraie sécurité, voir `aloli-crystal/sanitizer-html` (le
  # shard dédié documenté dans CRYSTAL-SANITIZER-HTML-SPECS.adoc).
  #
  # Portage 1:1 de `sanitizer.rb` (Ruby asciicrystal-pdf 2.3.24).
  module Sanitizer
    # Caractères XML spéciaux : entité → littéral.
    XML_SPECIAL_CHARS = {
      "&lt;"   => "<",
      "&gt;"   => ">",
      "&amp;"  => "&",
      "&quot;" => "\"",
      "&apos;" => "'",
    }
    XML_SPECIAL_CHARS_RX = /&(?:[lg]t|amp|quot|apos);/

    INVERSE_XML_SPECIAL_CHARS = {
      "<" => "&lt;",
      ">" => "&gt;",
      "&" => "&amp;",
    }
    INVERSE_XML_SPECIAL_CHARS_RX = /[<>&]/

    # Entités nommées HTML les plus fréquentes. Compatible avec ce que
    # asciicrystal produit en sortie. La valeur de fallback (`?`)
    # est utilisée pour les entités inconnues afin de signaler la perte
    # plutôt que de la cacher silencieusement.
    BUILT_IN_NAMED_ENTITIES = {
      "amp"    => "&",
      "apos"   => "'",
      "gt"     => ">",
      "lt"     => "<",
      "nbsp"   => " ",
      "quot"   => "\"",
      "hellip" => "…",
      "mdash"  => "—",
      "ndash"  => "–",
      "laquo"  => "«",
      "raquo"  => "»",
    }

    # Reconnaît un tag XML / HTML (forme simple). Le `\0?` final
    # dévore un éventuel null byte (vecteur d'évasion connu, repris
    # tel quel d'asciicrystal-pdf Ruby).
    SANITIZE_XML_RX = /<[^>]+>\0?/

    # Reconnaît une référence de caractère :
    #   * &amp;name; (entité nommée précédée d'un &amp; échappé)
    #   * &name;     (entité nommée standard)
    #   * &#NNN;     (référence numérique décimale)
    #   * &#xHHH;    (référence numérique hexadécimale)
    CHAR_REF_RX = /&(?:amp;)?(?:([a-z][a-z]+\d{0,2})|#(?:(\d\d\d{0,4})|x(\h\h\h{0,3})));/i

    # `&` non suivi d'une entité valide → à échapper en `&amp;`.
    UNESCAPED_AMPERSAND_RX = /&(?!(?:[a-z][a-z]+\d{0,2}|#(?:\d\d\d{0,4}|x\h\h\h{0,3}));)/i

    # Strip les balises (avec leur éventuel null byte attaché) et résout
    # les entités. Si `compact: true`, strip + collapse les espaces
    # multiples.
    #
    # Usage type dans le converter PDF : « ce que je vais dessiner
    # est-ce du texte plat ? — passe-le à `sanitize`. ».
    def self.sanitize(string : String, compact : Bool = true) : String
      result = string
      result = result.gsub(SANITIZE_XML_RX, "") if result.includes?('<')
      if result.includes?('&')
        result = result.gsub(CHAR_REF_RX) do |_match, m|
          if (name = m[1]?)
            BUILT_IN_NAMED_ENTITIES[name.downcase]? || "?"
          elsif (dec = m[2]?)
            (dec.to_i? || 0).chr.to_s
          elsif (hex = m[3]?)
            (hex.to_i?(16) || 0).chr.to_s
          else
            "?"
          end
        end
      end
      compact ? result.strip.gsub(/[ \t]+/, " ") : result
    end

    # Échappe les caractères XML spéciaux (`< > &`). Utilisé pour
    # injecter du texte de l'utilisateur dans un attribut ou un nœud
    # XML sans casser le markup.
    def self.escape_xml(string : String) : String
      string.gsub(INVERSE_XML_SPECIAL_CHARS_RX, INVERSE_XML_SPECIAL_CHARS)
    end

    # Inverse de `escape_xml`. Décode les entités XML standard.
    def self.unescape_xml(string : String) : String
      string.gsub(XML_SPECIAL_CHARS_RX, XML_SPECIAL_CHARS)
    end

    # Échappe les `&` qui ne font pas déjà partie d'une entité.
    # Utile pour normaliser un texte où certaines entités sont déjà
    # encodées et d'autres pas.
    def self.escape_amp(string : String) : String
      string.gsub(UNESCAPED_AMPERSAND_RX, "&amp;")
    end

    # Encode `"` en `&quot;` quand on a besoin d'injecter dans un
    # attribut HTML `attr="..."`.
    def self.encode_quotes(string : String) : String
      string.includes?('"') ? string.gsub('"', "&quot;") : string
    end
  end
end
