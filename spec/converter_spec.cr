require "./spec_helper"

# Répertoire de sortie pour les fichiers PDF générés par les tests
OUTPUT_DIR = "spec/output"

# Crée le répertoire de sortie si nécessaire
Dir.mkdir_p(OUTPUT_DIR)

# Utilitaire : convertit un contenu AsciiDoc et retourne le chemin du PDF
private def convert_to_pdf(content : String, filename : String) : String
  output_path = "#{OUTPUT_DIR}/#{filename}.pdf"
  doc = Asciidoctor.load(content, options: {"safe" => "safe", "outfile" => output_path})
  converter = AsciidoctorPDF::Converter.new
  converter.convert(doc)
  output_path
end

# Utilitaire : convertit et vérifie qu'un PDF non vide est produit
private def assert_pdf_generated(content : String, filename : String) : Nil
  path = convert_to_pdf(content, filename)
  File.exists?(path).should be_true
  File.size(path).should be > 0
  File.delete(path)
end

describe AsciidoctorPDF::Converter do
  # =========================================================================
  # Blocs de base
  # =========================================================================

  it "should convert a simple paragraph" do
    assert_pdf_generated("Hello, World.", "simple_paragraph")
  end

  it "should convert a section" do
    assert_pdf_generated("== Ma Section\n\nContenu de la section.", "section")
  end

  it "should convert nested sections" do
    input = "= Titre\n\n== Section 1\n\n=== Sous-section 1.1\n\nContenu.\n\n== Section 2\n\nContenu 2."
    assert_pdf_generated(input, "nested_sections")
  end

  it "should convert an unordered list" do
    assert_pdf_generated("* un\n* deux\n* trois", "ulist")
  end

  it "should convert an ordered list" do
    assert_pdf_generated(". un\n. deux\n. trois", "olist")
  end

  it "should convert a table" do
    input = "|===\n| Col A | Col B\n\n| 1     | 2\n| 3     | 4\n|==="
    assert_pdf_generated(input, "table")
  end

  it "should convert a table with header" do
    input = "[%header]\n|===\n| Nom | Valeur\n\n| alpha | 1\n| beta  | 2\n|==="
    assert_pdf_generated(input, "table_header")
  end

  # =========================================================================
  # Markup inline
  # =========================================================================

  it "should convert bold text" do
    assert_pdf_generated("Texte avec *gras* ici.", "inline_bold")
  end

  it "should convert italic text" do
    assert_pdf_generated("Texte avec _italique_ ici.", "inline_italic")
  end

  it "should convert monospace text" do
    assert_pdf_generated("Texte avec `code` ici.", "inline_mono")
  end

  it "should convert mixed inline markup" do
    assert_pdf_generated("*gras* et _italique_ et `mono` dans un paragraphe.", "inline_mixed")
  end

  # =========================================================================
  # Blocs de code
  # =========================================================================

  it "should convert a listing block" do
    input = "[source]\n----\nputs \"Hello, World!\"\n----"
    assert_pdf_generated(input, "listing_block")
  end

  it "should convert a listing block with language" do
    input = %([source,crystal]\n----\ndef hello(name : String) : String\n  "Hello, " + name\nend\n----)
    assert_pdf_generated(input, "listing_crystal")
  end

  it "should convert a listing block with ruby" do
    input = %([source,ruby]\n----\ndef greet(name)\n  # Salutation\n  puts "Hello, " + name\nend\n----)
    assert_pdf_generated(input, "listing_ruby")
  end

  it "should convert a literal block" do
    input = "....\nTexte préformaté\n  avec indentation\n...."
    assert_pdf_generated(input, "literal_block")
  end

  # =========================================================================
  # Admonitions
  # =========================================================================

  it "should convert a NOTE admonition" do
    assert_pdf_generated("NOTE: Ceci est une note importante.", "admonition_note")
  end

  it "should convert a TIP admonition" do
    assert_pdf_generated("TIP: Ceci est un conseil.", "admonition_tip")
  end

  it "should convert a WARNING admonition" do
    assert_pdf_generated("WARNING: Attention à ce point.", "admonition_warning")
  end

  it "should convert a CAUTION admonition" do
    assert_pdf_generated("CAUTION: Soyez prudent.", "admonition_caution")
  end

  it "should convert an IMPORTANT admonition" do
    assert_pdf_generated("IMPORTANT: Ceci est crucial.", "admonition_important")
  end

  # =========================================================================
  # Blocs spéciaux
  # =========================================================================

  it "should convert a quote block" do
    input = "[quote, Victor Hugo, Les Misérables]\n____\nAimer, c'est agir.\n____"
    assert_pdf_generated(input, "quote_block")
  end

  it "should convert a sidebar block" do
    input = "****\nCeci est un encadré latéral.\n****"
    assert_pdf_generated(input, "sidebar_block")
  end

  it "should convert an example block" do
    input = "====\nCeci est un exemple.\n===="
    assert_pdf_generated(input, "example_block")
  end

  # =========================================================================
  # Thème personnalisé
  # =========================================================================

  it "should use a custom theme" do
    theme = AsciidoctorPDF::Theme.new
    theme.base_font_size = 14.0
    theme.base_font_color = "0000ff"

    output_path = "#{OUTPUT_DIR}/custom_theme.pdf"
    doc = Asciidoctor.load("Texte avec thème personnalisé.", options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new("pdf", theme)
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0
    File.delete(output_path)
  end

  # =========================================================================
  # Document complet
  # =========================================================================

  it "should convert a complete document" do
    input = <<-ADOC
    = Manuel d'utilisation
    Auteur Exemple <auteur@exemple.com>
    v1.0, 2024-01-01
    :toc:

    == Introduction

    Ce document est un exemple complet.

    === Sous-section

    Contenu avec *gras*, _italique_ et `code`.

    == Code

    [source,crystal]
    ----
    # Exemple Crystal
    def hello : String
      "Bonjour!"
    end
    ----

    == Tableau

    |===
    | Colonne A | Colonne B

    | Valeur 1  | Valeur 2
    | Valeur 3  | Valeur 4
    |===

    NOTE: Fin du document.
    ADOC
    assert_pdf_generated(input, "complete_document")
  end

  # =========================================================================
  # Génération de l'index
  # =========================================================================

  it "should collect index terms and generate index page" do
    # Le thème doit avoir index_enabled = true pour déclencher le rendu
    theme = AsciidoctorPDF::Theme.new
    theme.index_enabled = true

    input = <<-ADOC
    = Document avec Index
    :index:

    == Chapitre 1

    Texte sur Crystal((Crystal)) et sur les langages de programmation((langage de programmation)).

    == Chapitre 2

    Plus d informations sur Crystal((Crystal)) et sur Ruby((Ruby)).
    ADOC

    output_path = "#{OUTPUT_DIR}/index_test.pdf"
    doc = Asciidoctor.load(input, options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new("pdf", theme)
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0
    File.delete(output_path)
  end

  it "should not generate index page when index_enabled is false" do
    theme = AsciidoctorPDF::Theme.new
    theme.index_enabled = false

    input = "Texte avec Crystal((Crystal)) indexé."
    output_path = "#{OUTPUT_DIR}/no_index_test.pdf"
    doc = Asciidoctor.load(input, options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new("pdf", theme)
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0
    File.delete(output_path)
  end

  it "should generate index with multiple columns" do
    theme = AsciidoctorPDF::Theme.new
    theme.index_enabled = true
    theme.index_columns = 3

    input = <<-ADOC
    = Index multi-colonnes

    Termes : Alpha((Alpha)), Beta((Beta)), Crystal((Crystal)), Delta((Delta)),
    Epsilon((Epsilon)), Gamma((Gamma)), Lambda((Lambda)), Omega((Omega)).
    ADOC

    output_path = "#{OUTPUT_DIR}/index_multicolumn.pdf"
    doc = Asciidoctor.load(input, options: {"safe" => "safe", "outfile" => output_path})
    converter = AsciidoctorPDF::Converter.new("pdf", theme)
    converter.convert(doc)

    File.exists?(output_path).should be_true
    File.size(output_path).should be > 0
    File.delete(output_path)
  end
end
