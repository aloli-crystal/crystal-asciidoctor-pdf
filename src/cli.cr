require "./asciidoctor_pdf"
require "option_parser"

input_file = ""
output_file = ""
theme_file = ""
sample_mode = false
attributes = {} of String => String

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal-asciidoctor-pdf [options] fichier.adoc"
  parser.on("-o FILE", "--out-file FILE", "Fichier de sortie PDF (defaut : fichier.adoc.pdf)") { |f| output_file = f }
  parser.on("-T FILE", "--theme FILE", "Fichier de theme YAML") { |f| theme_file = f }
  parser.on("-a ATTR", "--attribute ATTR", "Attribut nom=valeur") do |a|
    parts = a.split("=", 2)
    attributes[parts[0]] = parts.size > 1 ? parts[1] : ""
  end
  parser.on("--sample", "Generer le document de reference (reference.adoc + PDF)") { sample_mode = true }
  parser.on("-h", "--help", "Afficher l aide") { puts parser; exit 0 }
  parser.on("-v", "--version", "Afficher la version") { puts "crystal-asciidoctor-pdf #{AsciidoctorPDF::VERSION}"; exit 0 }
  parser.unknown_args { |args| input_file = args.first? || "" }
end

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
  puts "Sample document generated: reference.adoc and reference.adoc.pdf"
  exit 0
end

if input_file.empty?
  STDERR.puts "Erreur : aucun fichier d entree specifie."
  STDERR.puts "Usage : crystal-asciidoctor-pdf [options] fichier.adoc"
  exit 1
end

unless File.exists?(input_file)
  STDERR.puts "Erreur : le fichier '" + input_file + "' n existe pas."
  exit 1
end

# Convention de nommage : mon_document.adoc => mon_document.adoc.pdf
# (permet de distinguer facilement les fichiers source et PDF,
#  et d eviter toute confusion avec la version Ruby asciidoctor-pdf)
if output_file.empty?
  output_file = File.join(
    File.dirname(input_file),
    File.basename(input_file) + ".pdf"
  )
end

theme = theme_file.empty? ? AsciidoctorPDF::Theme.new : AsciidoctorPDF::ThemeLoader.load(theme_file)

options = {"docfile" => input_file, "outfile" => output_file} of String => String
attributes.each { |k, v| options[k] = v }

doc = Asciidoctor.load_file(input_file, options)
converter = AsciidoctorPDF::Converter.new("pdf", theme)
converter.convert(doc)

puts "PDF genere : " + output_file
