require "http/client"
require "digest/sha256"
require "json"
require "./hyphenation"
require "./hyphenation/manifest"

module AsciidoctorPDF
  # Sous-commande CLI `hyph` : gestion utilisateur des patterns
  # de césure Liang. Modèle d'inspiration : `tlmgr` (TeX Live
  # Manager) — pas de téléchargement automatique au runtime,
  # action toujours explicite, vérification SHA-256 obligatoire
  # contre le manifest embarqué.
  #
  # Spécification complète : `doc/CLI_HYPH_SPEC.adoc`.
  module HyphCli
    # Dossier XDG où sont stockés les patterns installés par
    # l'utilisateur. Suit la convention ALOLI `feedback_xdg_config_convention`.
    XDG_DIR = File.join(
      ENV["XDG_CONFIG_HOME"]? || (ENV["HOME"]? ? "#{ENV["HOME"]}/.config" : "/tmp"),
      "asciidoctor-pdf",
      "hyphenation",
    )

    # Refuse silencieusement d'installer un fichier > 1 Mo (anti-DoS).
    MAX_FILE_SIZE = 1_048_576

    # Codes de sortie (cf. spec CLI_HYPH_SPEC.adoc).
    EXIT_OK                 =  0
    EXIT_USAGE              =  2
    EXIT_NOT_FOUND          =  3
    EXIT_NETWORK            =  4
    EXIT_SHA_MISMATCH       =  5
    EXIT_TOO_LARGE          =  6
    EXIT_INVALID_CONTENT    =  7
    EXIT_EMBEDDED_PROTECTED =  8
    EXIT_XDG_READONLY       =  9
    EXIT_MANIFEST_MISSING   = 10

    def self.run(args : Array(String)) : Nil
      sub = args.first?
      rest = args.size > 1 ? args[1..] : [] of String

      case sub
      when nil, "help", "-h", "--help"
        print_help(rest.first?)
      when "list", "ls"
        cmd_list(rest)
      when "available", "av"
        cmd_available(rest)
      when "install", "in"
        cmd_install(rest)
      when "remove", "rm"
        cmd_remove(rest)
      when "update", "up"
        cmd_update(rest)
      when "show", "sh"
        cmd_show(rest)
      else
        STDERR.puts "Erreur : sous-commande `hyph #{sub}` inconnue."
        STDERR.puts "Sous-commandes valides : list, available, install, remove, update, show, help"
        STDERR.puts "Pour l'aide : crystal-asciidoctor-pdf hyph help"
        exit EXIT_USAGE
      end
    end

    private def self.print_help(focus : String? = nil) : Nil
      case focus
      when "list", "ls"
        puts <<-HELP
          NAME
              hyph list — liste les patterns de césure disponibles

          SYNOPSIS
              crystal-asciidoctor-pdf hyph list [-j|--json]

          OPTIONS
              -j, --json    Sortie JSON parseable
          HELP
      when "install", "in"
        puts <<-HELP
          NAME
              hyph install — installe un pattern depuis CTAN

          SYNOPSIS
              crystal-asciidoctor-pdf hyph install <lang> [-s|--sha256 <hash>] [-u|--from <url>] [-f|--force]

          OPTIONS
              -s, --sha256 <hash>  SHA-256 attendu (obligatoire si langue hors manifest)
              -u, --from <url>     URL alternative (défaut : CTAN officiel)
              -f, --force          Écrase un pattern déjà installé

          EXEMPLES
              crystal-asciidoctor-pdf hyph install ja
              crystal-asciidoctor-pdf hyph install xx --sha256 abc123... --from https://...
          HELP
      else
        puts <<-HELP
          NAME
              hyph — gestion des patterns de césure Liang

          SOUS-COMMANDES
              list       Liste les patterns disponibles (embarqués + installés)
              available  Interroge CTAN pour les patterns téléchargeables
              install    Télécharge et installe un pattern depuis CTAN
              remove     Supprime un pattern installé
              update     Re-télécharge un pattern installé
              show       Affiche les métadonnées d'un pattern
              help       Affiche cette aide (ou détails d'une sous-commande)

          EXEMPLES
              crystal-asciidoctor-pdf hyph list
              crystal-asciidoctor-pdf hyph install ja
              crystal-asciidoctor-pdf hyph remove ja
              crystal-asciidoctor-pdf hyph help install
          HELP
      end
    end

    private def self.installed_langs : Array(String)
      return [] of String unless Dir.exists?(XDG_DIR)
      Dir.children(XDG_DIR).compact_map do |f|
        if f.starts_with?("hyph-") && f.ends_with?(".tex")
          f.lchop("hyph-").rchop(".tex")
        end
      end.sort
    end

    private def self.cmd_list(args : Array(String)) : Nil
      json = args.includes?("-j") || args.includes?("--json")
      embedded = Hyphenation::Loader::EMBEDDED.keys.to_a.sort
      installed = installed_langs
      all = (embedded + installed).uniq.sort

      if json
        rows = all.map do |lang|
          src = installed.includes?(lang) ? "user" : "embedded"
          {lang: lang, source: src}
        end
        puts rows.to_json
      else
        printf "%-12s  %-9s  %s\n", "Langue", "Source", "Taille"
        puts "-" * 40
        all.each do |lang|
          if installed.includes?(lang)
            path = File.join(XDG_DIR, "hyph-#{lang}.tex")
            size = File.size(path)
            printf "%-12s  %-9s  %d o\n", lang, "user", size
          elsif embedded.includes?(lang)
            content = Hyphenation::Loader::EMBEDDED[lang]
            printf "%-12s  %-9s  %d o\n", lang, "embarqué", content.bytesize
          end
        end
        puts ""
        puts "#{embedded.size} langues embarquées, #{installed.size} installées."
      end
    end

    private def self.cmd_show(args : Array(String)) : Nil
      lang = args.first?
      unless lang
        STDERR.puts "Erreur : `hyph show` nécessite un argument <lang>."
        exit EXIT_USAGE
      end

      entry = Hyphenation::MANIFEST[lang]?
      installed = installed_langs.includes?(lang)
      embedded = Hyphenation::Loader::EMBEDDED.has_key?(lang)

      if !entry && !installed && !embedded
        STDERR.puts "Erreur : la langue `#{lang}` n'est ni embarquée, ni installée, ni dans le manifest."
        exit EXIT_NOT_FOUND
      end

      puts "Langue       : #{lang}"
      if entry
        puts "URL canonique : #{entry.url}"
        puts "SHA-256       : #{entry.sha256}"
        puts "Taille (man.) : #{entry.size} o"
        puts "Licence       : #{entry.license}"
        puts "Embarquée     : #{entry.embedded ? "oui" : "non"}"
      else
        puts "(pas d'entrée manifest)"
      end
      if installed
        path = File.join(XDG_DIR, "hyph-#{lang}.tex")
        puts "Installée     : #{path} (#{File.size(path)} o)"
      end
      if embedded
        puts "Embarquée     : oui (au build)"
      end
    end

    private def self.cmd_available(_args : Array(String)) : Nil
      # MVP : on liste juste les entries du manifest local.
      # L'interrogation CTAN à la volée est prévue dans
      # CLI_HYPH_SPEC.adoc (`--refresh-cache`) — laissée pour
      # une itération ultérieure.
      puts "Manifest local (#{Hyphenation::MANIFEST.size} entrées) :"
      puts ""
      printf "%-12s  %-9s  %-12s  %s\n", "Langue", "Status", "Taille", "Licence"
      puts "-" * 60
      installed = installed_langs
      Hyphenation::MANIFEST.each do |lang, entry|
        status = if entry.embedded
                   "embarqué"
                 elsif installed.includes?(lang)
                   "installé"
                 else
                   "disponible"
                 end
        printf "%-12s  %-9s  %-12s  %s\n", lang, status, "#{entry.size} o", entry.license
      end
    end

    private def self.cmd_install(args : Array(String)) : Nil
      lang = nil.as(String?)
      sha256_arg = nil.as(String?)
      from_url = nil.as(String?)
      force = false

      i = 0
      while i < args.size
        case args[i]
        when "-s", "--sha256"
          sha256_arg = args[i + 1]?
          i += 2
        when "-u", "--from"
          from_url = args[i + 1]?
          i += 2
        when "-f", "--force"
          force = true
          i += 1
        else
          lang = args[i] if lang.nil?
          i += 1
        end
      end

      unless lang
        STDERR.puts "Erreur : `hyph install` nécessite un argument <lang>."
        exit EXIT_USAGE
      end

      entry = Hyphenation::MANIFEST[lang]?
      expected_sha = sha256_arg || entry.try &.sha256

      unless expected_sha
        STDERR.puts "Erreur : la langue `#{lang}` n'est pas dans le manifest."
        STDERR.puts "Pour installer une langue non manifestée, fournissez `--sha256 <hash>` explicitement."
        exit EXIT_MANIFEST_MISSING
      end

      url = from_url || entry.try &.url
      unless url
        STDERR.puts "Erreur : pas d'URL pour `#{lang}` (manifest absent et `--from` non fourni)."
        exit EXIT_USAGE
      end

      target = File.join(XDG_DIR, "hyph-#{lang}.tex")
      if File.exists?(target) && !force
        STDERR.puts "Le pattern `#{lang}` est déjà installé : #{target}"
        STDERR.puts "Utilisez `--force` pour écraser."
        exit EXIT_OK
      end

      puts "Téléchargement de hyph-#{lang}.tex depuis #{url}..."
      content = begin
        HTTP::Client.get(url) do |response|
          unless response.success?
            STDERR.puts "Erreur HTTP : #{response.status_code} #{response.status_message}"
            exit EXIT_NETWORK
          end
          response.body_io.gets_to_end
        end
      rescue ex
        STDERR.puts "Erreur réseau : #{ex.message}"
        exit EXIT_NETWORK
      end

      if content.bytesize > MAX_FILE_SIZE
        STDERR.puts "Erreur : fichier trop volumineux (#{content.bytesize} o > #{MAX_FILE_SIZE} o). Possible corruption."
        exit EXIT_TOO_LARGE
      end

      actual_sha = Digest::SHA256.hexdigest(content)
      if actual_sha != expected_sha
        STDERR.puts "Erreur : SHA-256 mismatch."
        STDERR.puts "  attendu : #{expected_sha}"
        STDERR.puts "  obtenu  : #{actual_sha}"
        exit EXIT_SHA_MISMATCH
      end

      unless content.includes?("\\patterns{") || content.includes?("\\hyphenation{")
        STDERR.puts "Erreur : fichier invalide (pas de bloc \\patterns ou \\hyphenation)."
        exit EXIT_INVALID_CONTENT
      end

      Dir.mkdir_p(XDG_DIR)
      File.write(target, content)
      puts "✓ Installé : #{target} (#{content.bytesize} o)"
    end

    private def self.cmd_remove(args : Array(String)) : Nil
      lang = args.first?
      unless lang
        STDERR.puts "Erreur : `hyph remove` nécessite un argument <lang>."
        exit EXIT_USAGE
      end

      if Hyphenation::Loader::EMBEDDED.has_key?(lang) && !installed_langs.includes?(lang)
        STDERR.puts "Erreur : la langue `#{lang}` est embarquée au build et ne peut pas être supprimée."
        exit EXIT_EMBEDDED_PROTECTED
      end

      path = File.join(XDG_DIR, "hyph-#{lang}.tex")
      unless File.exists?(path)
        STDERR.puts "Erreur : la langue `#{lang}` n'est pas installée."
        exit EXIT_NOT_FOUND
      end

      File.delete(path)
      puts "✓ Supprimé : #{path}"
    end

    private def self.cmd_update(args : Array(String)) : Nil
      installed = installed_langs
      target_langs = args.empty? ? installed : args
      target_langs.each do |lang|
        unless installed.includes?(lang)
          STDERR.puts "Skip `#{lang}` : non installé."
          next
        end
        cmd_install([lang, "--force"])
      end
    end
  end
end
