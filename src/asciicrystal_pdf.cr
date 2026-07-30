require "asciicrystal"
require "pdf"

require "./asciicrystal_pdf/theme"
require "./asciicrystal_pdf/theme_loader"
require "./asciicrystal_pdf/user_config"
require "./asciicrystal_pdf/form_builder"
require "./asciicrystal_pdf/form_renderer"
require "./asciicrystal_pdf/roman_numeral"
require "./asciicrystal_pdf/win_ansi"
require "./asciicrystal_pdf/sanitizer"
require "./asciicrystal_pdf/text_transformer"
require "./asciicrystal_pdf/inline_renderer"
require "./asciicrystal_pdf/hyphenation"
require "./asciicrystal_pdf/paragraph_composer"
require "./asciicrystal_pdf/syntax_highlighter"
require "./asciicrystal_pdf/converter"

module AsciicrystalPDF
  # Lue au compile-time depuis `shard.yml` via le macro `read_file`.
  # Cf. note mémoire `feedback_shard_version_macro.md` (mémoire ALOLI).
  VERSION = {{
              (read_file("#{__DIR__}/../shard.yml")
                .lines
                .find(&.starts_with?("version:")) || "version: 0.0.0")
                .gsub(/^version:\s*/, "")
                .chomp
            }}

  # Version de la gem Ruby asciicrystal-pdf utilisée comme base du portage.
  UPSTREAM_VERSION = "2.3.24"

  # Version de la gem Ruby asciidoctor (parser) sur laquelle ce shard est aligné
  # via sa dépendance asciicrystal.
  # Doit rester synchronisée avec Asciicrystal::UPSTREAM_VERSION dans asciicrystal.
  UPSTREAM_ASCIIDOCTOR_VERSION = "2.0.26"
end
