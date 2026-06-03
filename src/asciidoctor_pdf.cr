require "crystal-asciidoctor"
require "pdf"

require "./asciidoctor_pdf/theme"
require "./asciidoctor_pdf/theme_loader"
require "./asciidoctor_pdf/user_config"
require "./asciidoctor_pdf/form_builder"
require "./asciidoctor_pdf/form_renderer"
require "./asciidoctor_pdf/roman_numeral"
require "./asciidoctor_pdf/win_ansi"
require "./asciidoctor_pdf/sanitizer"
require "./asciidoctor_pdf/text_transformer"
require "./asciidoctor_pdf/inline_renderer"
require "./asciidoctor_pdf/paragraph_composer"
require "./asciidoctor_pdf/syntax_highlighter"
require "./asciidoctor_pdf/converter"

module AsciidoctorPDF
  # Lue au compile-time depuis `shard.yml` via le macro `read_file`.
  # Cf. note mémoire `feedback_shard_version_macro.md` (mémoire ALOLI).
  VERSION = {{
              (read_file("#{__DIR__}/../shard.yml")
                .lines
                .find(&.starts_with?("version:")) || "version: 0.0.0")
                .gsub(/^version:\s*/, "")
                .chomp
            }}

  # Version de la gem Ruby asciidoctor-pdf utilisée comme base du portage.
  UPSTREAM_VERSION = "2.3.24"

  # Version de la gem Ruby asciidoctor (parser) sur laquelle ce shard est aligné
  # via sa dépendance crystal-asciidoctor.
  # Doit rester synchronisée avec Asciidoctor::UPSTREAM_VERSION dans crystal-asciidoctor.
  UPSTREAM_ASCIIDOCTOR_VERSION = "2.0.26"
end
