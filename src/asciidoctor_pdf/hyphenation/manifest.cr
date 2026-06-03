module AsciidoctorPDF
  module Hyphenation
    # Manifest des patterns Liang officiellement supportés.
    # Les 7 langues marquées `embedded: true` sont incluses dans
    # le binaire via la macro `read_file`. Les autres sont
    # installables via `asciidoctor-pdf hyph install <lang>` qui
    # télécharge depuis CTAN et vérifie le SHA-256 contre cette
    # table.
    #
    # Source : https://ctan.org/pkg/hyph-utf8
    # Licences : LPPL 1.3 ou MIT selon le fichier (chaque fichier
    # déclare sa licence en en-tête).
    record ManifestEntry,
      lang : String,
      url : String,
      sha256 : String,
      size : Int32,
      license : String,
      embedded : Bool

    CTAN_PREFIX = "https://mirrors.ctan.org/language/hyph-utf8/tex/generic/hyph-utf8/patterns/tex/"

    MANIFEST = {
      "fr" => ManifestEntry.new(
        lang: "fr",
        url: "#{CTAN_PREFIX}hyph-fr.tex",
        sha256: "526cad6fe8f52fcd3caa3fcaf667cb1740cfc14bca198680e00dc343a84594de",
        size: 30353,
        license: "MIT",
        embedded: true,
      ),
      "en-us" => ManifestEntry.new(
        lang: "en-us",
        url: "#{CTAN_PREFIX}hyph-en-us.tex",
        sha256: "f4ffcd96c5cbc886bdad23f95dcae8edc3cd3620eae62f7946eceda97c4e68f8",
        size: 34128,
        license: "Knuth-permissive",
        embedded: true,
      ),
      "de-1996" => ManifestEntry.new(
        lang: "de-1996",
        url: "#{CTAN_PREFIX}hyph-de-1996.tex",
        sha256: "374ad1ce3263f8a2791ec070ef9b516c532dae64456f3fb656e617e8ae53a9d3",
        size: 274609,
        license: "MIT",
        embedded: true,
      ),
      "es" => ManifestEntry.new(
        lang: "es",
        url: "#{CTAN_PREFIX}hyph-es.tex",
        sha256: "6a2e5f39a991a23d1cd8a23dbd0f6fe96a9f07561a6695f4f3320f47030e236c",
        size: 42602,
        license: "MIT",
        embedded: true,
      ),
      "it" => ManifestEntry.new(
        lang: "it",
        url: "#{CTAN_PREFIX}hyph-it.tex",
        sha256: "6ce56ed6ed2ca7c0688838e366e6595e0429f984f4fc6e96ec045cebb1e76a47",
        size: 5011,
        license: "LPPL-1.3-or-MIT",
        embedded: true,
      ),
      "pt" => ManifestEntry.new(
        lang: "pt",
        url: "#{CTAN_PREFIX}hyph-pt.tex",
        sha256: "c110a39e501db372d1d755e1c64464321a2efa7d8e9617f66001000389b941f2",
        size: 5487,
        license: "BSD-3-Clause",
        embedded: true,
      ),
      "nl" => ManifestEntry.new(
        lang: "nl",
        url: "#{CTAN_PREFIX}hyph-nl.tex",
        sha256: "d21499bfbee53e4d50e867ef92a41fd28b65725d7c91c980e4f8f02889bf6b2a",
        size: 87511,
        license: "MIT",
        embedded: true,
      ),
    }
  end
end
