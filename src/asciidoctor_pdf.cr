require "crystal-asciidoctor"
require "pdf"

require "./asciidoctor_pdf/theme"
require "./asciidoctor_pdf/theme_loader"
require "./asciidoctor_pdf/roman_numeral"
require "./asciidoctor_pdf/win_ansi"
require "./asciidoctor_pdf/sanitizer"
require "./asciidoctor_pdf/text_transformer"
require "./asciidoctor_pdf/inline_renderer"
require "./asciidoctor_pdf/syntax_highlighter"
require "./asciidoctor_pdf/converter"

module AsciidoctorPDF
  VERSION = "2.3.24.53"

  # Version de la gem Ruby asciidoctor-pdf utilisée comme base du portage.
  UPSTREAM_VERSION = "2.3.24"

  # Version de la gem Ruby asciidoctor (parser) sur laquelle ce shard est aligné
  # via sa dépendance crystal-asciidoctor.
  # Doit rester synchronisée avec Asciidoctor::UPSTREAM_VERSION dans crystal-asciidoctor.
  UPSTREAM_ASCIIDOCTOR_VERSION = "2.0.26"
end
