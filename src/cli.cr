require "./asciidoctor_pdf"
require "./asciidoctor_pdf/hyph_cli"
require "option_parser"

# Sous-commande `hyph` : gestion des patterns de césure Liang.
# Court-circuite le parsing OptionParser principal (lui-même
# dédié à la génération PDF).
if ARGV.first? == "hyph"
  AsciidoctorPDF::HyphCli.run(ARGV.size > 1 ? ARGV[1..] : [] of String)
  exit 0
end

input_file = ""
output_file = ""
theme_file = ""
sample_mode = false
no_user_config = false
attributes = {} of String => String

OptionParser.parse do |parser|
  parser.banner = "Usage : crystal-asciidoctor-pdf [options] fichier.adoc"
  parser.on("-o FILE", "--out-file FILE", "Fichier de sortie PDF (par défaut : fichier.adoc.pdf)") { |f| output_file = f }
  parser.on("-T NAME", "--theme NAME", "Thème : nom embarqué (#{AsciidoctorPDF::ThemeLoader.builtin_names.join(", ")}) ou chemin YAML") { |f| theme_file = f }
  parser.on("-a ATTR", "--attribute ATTR", "Attribut nom=valeur") do |a|
    parts = a.split("=", 2)
    attributes[parts[0]] = parts.size > 1 ? parts[1] : ""
  end
  parser.on("-N", "--no-user-config", "Ignorer la configuration utilisateur (#{AsciidoctorPDF::UserConfig.expected_dir}/config.yml)") { no_user_config = true }
  parser.on("--sample", "Générer le document de référence (reference.adoc + PDF)") { sample_mode = true }
  parser.on("-h", "--help", "Afficher l'aide") { puts parser; exit 0 }
  parser.on("-v", "--version", "Afficher la version") { puts "crystal-asciidoctor-pdf #{AsciidoctorPDF::VERSION}"; exit 0 }
  parser.unknown_args { |args| input_file = args.first? || "" }
end

# Chargement de la configuration utilisateur (XDG).
# Court-circuité par `--no-user-config`.
user_config = no_user_config ? AsciidoctorPDF::UserConfig.empty : AsciidoctorPDF::UserConfig.load

if sample_mode
  # Le fichier de référence est dans crystal-asciidoctor (le shard cœur)
  sample_src = File.join(__DIR__, "..", "lib", "crystal-asciidoctor", "data", "samples", "reference.adoc")
  # Fallback : chercher dans le shard local
  unless File.exists?(sample_src)
    sample_src = File.join(__DIR__, "..", "data", "samples", "reference.adoc")
  end
  sample_dest = File.join(Dir.current, "reference.adoc")
  sample_pdf = File.join(Dir.current, "reference.adoc.pdf")
  File.write(sample_dest, File.read(sample_src))
  theme = AsciidoctorPDF::Theme.new
  options = {"docfile" => sample_dest, "outfile" => sample_pdf} of String => String
  doc = Asciidoctor.load_file(sample_dest, options)
  converter = AsciidoctorPDF::Converter.new("pdf", theme)
  converter.convert(doc)
  puts "Document de référence généré : reference.adoc et reference.adoc.pdf"
  exit 0
end

if input_file.empty?
  STDERR.puts "Erreur : aucun fichier d'entrée spécifié."
  STDERR.puts "Usage : crystal-asciidoctor-pdf [options] fichier.adoc"
  exit 1
end

unless File.exists?(input_file)
  STDERR.puts "Erreur : le fichier '#{input_file}' n'existe pas."
  exit 1
end

# Convention de nommage : mon_document.adoc => mon_document.adoc.pdf
# (permet de distinguer facilement les fichiers source et PDF,
#  et d'éviter toute confusion avec la version Ruby asciidoctor-pdf)
if output_file.empty?
  output_file = File.join(
    File.dirname(input_file),
    File.basename(input_file) + ".pdf"
  )
end

options = {"docfile" => input_file, "outfile" => output_file} of String => String

# Fusion des attributs CLI puis user config dans `options`.
# Ordre important : les attributs CLI ont la priorité sur le user
# config ; le document AsciiDoc lui-même peut encore écraser tout ça
# via `:attribut: valeur` (gestion par Asciidoctor.load).
attributes.each { |k, v| options[k] = v }
user_config.merge_into(options)

doc = Asciidoctor.load_file(input_file, options)

# Résolution du thème, par ordre de priorité décroissante :
#   1. argument CLI `--theme` (nom embarqué OU chemin YAML)
#   2. attribut document `:pdf-theme:` dans le source AsciiDoc
#   3. user config `theme:` (XDG)
#   4. thème par défaut intégré
theme =
  if !theme_file.empty?
    AsciidoctorPDF::ThemeLoader.resolve(theme_file)
  elsif (pdf_theme = doc.attr("pdf-theme")) && !pdf_theme.to_s.empty?
    AsciidoctorPDF::ThemeLoader.resolve(pdf_theme.to_s)
  elsif (user_theme = user_config.resolve_theme)
    user_theme
  else
    AsciidoctorPDF::Theme.new
  end

converter = AsciidoctorPDF::Converter.new("pdf", theme)
converter.convert(doc)

puts "PDF généré : #{output_file}"
