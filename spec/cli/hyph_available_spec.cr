require "../spec_helper"
require "../../src/asciidoctor_pdf/hyph_cli"
require "file_utils"
require "json"

# Spec d'intégration de `asciidoctor-pdf hyph available`.
#
# Le test ne touche jamais à `~/.cache` réel : on redirige
# `XDG_CACHE_HOME` vers un dossier temporaire dédié pour chaque
# example. Aucun de ces tests n'effectue de requête HTTP — le
# fetch réseau est testé par injection d'un cache pré-rempli
# (chemin code = lecture cache, pas de HTTP).
describe AsciicrystalPDF::HyphCli do
  tmp_cache = nil.as(String?)
  prev_xdg = nil.as(String?)
  prev_ctan = nil.as(String?)
  prev_hyph = nil.as(String?)

  before_each do
    tmp_cache = File.tempname("asciidoctor-pdf-hyph-cache")
    prev_xdg = ENV["XDG_CACHE_HOME"]?
    prev_ctan = ENV["CTAN_MIRROR"]?
    prev_hyph = ENV["HYPH_MIRROR"]?
    ENV["XDG_CACHE_HOME"] = tmp_cache.not_nil!
    ENV.delete("CTAN_MIRROR")
    ENV.delete("HYPH_MIRROR")
  end

  after_each do
    FileUtils.rm_rf(tmp_cache.not_nil!) if tmp_cache
    if (v = prev_xdg)
      ENV["XDG_CACHE_HOME"] = v
    else
      ENV.delete("XDG_CACHE_HOME")
    end
    ENV["CTAN_MIRROR"] = prev_ctan.not_nil! if prev_ctan
    ENV["HYPH_MIRROR"] = prev_hyph.not_nil! if prev_hyph
  end

  describe ".extract_lang_from_filename" do
    it "extrait la langue d'un nom de fichier hyph-*.tex" do
      AsciicrystalPDF::HyphCli.extract_lang_from_filename("hyph-fr.tex").should eq "fr"
      AsciicrystalPDF::HyphCli.extract_lang_from_filename("hyph-en-us.tex").should eq "en-us"
      AsciicrystalPDF::HyphCli.extract_lang_from_filename("hyph-zh-latn-pinyin.tex").should eq "zh-latn-pinyin"
    end

    it "retourne nil pour un nom de fichier qui ne suit pas le motif" do
      AsciicrystalPDF::HyphCli.extract_lang_from_filename("README.md").should be_nil
      AsciicrystalPDF::HyphCli.extract_lang_from_filename("hyph-fr.txt").should be_nil
      AsciicrystalPDF::HyphCli.extract_lang_from_filename("fr.tex").should be_nil
    end
  end

  describe ".parse_available_response" do
    it "parse une réponse JSON de l'API GitHub" do
      body = [
        {"name" => "hyph-fr.tex", "type" => "file"},
        {"name" => "hyph-en-us.tex", "type" => "file"},
        {"name" => "README.md", "type" => "file"},
        {"name" => "hyph-zh-latn-pinyin.tex", "type" => "file"},
      ].to_json
      url = "https://api.github.com/repos/hyphenation/tex-hyphen/contents/x"
      langs = AsciicrystalPDF::HyphCli.parse_available_response(body, url)
      langs.should eq ["en-us", "fr", "zh-latn-pinyin"]
    end

    it "parse une réponse HTML CTAN (fallback)" do
      body = <<-HTML
        <html><body>
        <a href="hyph-fr.tex">fr</a>
        <a href="hyph-en-us.tex">en-us</a>
        <a href="hyph-ja.tex">ja</a>
        <a href="../">parent</a>
        </body></html>
        HTML
      url = "https://mirror.ctan.org/language/hyph-utf8/..."
      langs = AsciicrystalPDF::HyphCli.parse_available_response(body, url)
      langs.should eq ["en-us", "fr", "ja"]
    end

    it "dédoublonne et trie les résultats" do
      body = [
        {"name" => "hyph-fr.tex"},
        {"name" => "hyph-ar.tex"},
        {"name" => "hyph-fr.tex"},
      ].to_json
      url = "https://api.github.com/x"
      langs = AsciicrystalPDF::HyphCli.parse_available_response(body, url)
      langs.should eq ["ar", "fr"]
    end
  end

  describe ".available_cache_valid?" do
    it "retourne false quand le cache n'existe pas" do
      AsciicrystalPDF::HyphCli.available_cache_valid?.should be_false
    end

    it "retourne true quand le cache est récent" do
      Dir.mkdir_p(AsciicrystalPDF::HyphCli.xdg_cache_dir)
      File.write(AsciicrystalPDF::HyphCli.available_cache_file, %({"langs":[]}))
      AsciicrystalPDF::HyphCli.available_cache_valid?.should be_true
    end

    it "retourne false quand le cache est plus vieux que la TTL" do
      Dir.mkdir_p(AsciicrystalPDF::HyphCli.xdg_cache_dir)
      path = AsciicrystalPDF::HyphCli.available_cache_file
      File.write(path, %({"langs":[]}))
      old = Time.utc - 10.days
      File.utime(old, old, path)
      AsciicrystalPDF::HyphCli.available_cache_valid?.should be_false
    end
  end

  describe ".read_cached_langs" do
    it "lit la liste de langues d'un cache bien formé" do
      Dir.mkdir_p(AsciicrystalPDF::HyphCli.xdg_cache_dir)
      File.write(
        AsciicrystalPDF::HyphCli.available_cache_file,
        {
          "source"     => "https://example.org/x",
          "fetched_at" => Time.utc.to_rfc3339,
          "langs"      => ["fr", "en-us", "ja"],
        }.to_json,
      )
      langs = AsciicrystalPDF::HyphCli.read_cached_langs
      langs.should eq ["fr", "en-us", "ja"]
    end

    it "retourne nil quand le cache est absent" do
      AsciicrystalPDF::HyphCli.read_cached_langs.should be_nil
    end

    it "retourne nil quand le cache est corrompu" do
      Dir.mkdir_p(AsciicrystalPDF::HyphCli.xdg_cache_dir)
      File.write(AsciicrystalPDF::HyphCli.available_cache_file, "{ not json")
      AsciicrystalPDF::HyphCli.read_cached_langs.should be_nil
    end
  end

  describe ".available_source_url" do
    it "préfère HYPH_MIRROR à CTAN_MIRROR à l'URL par défaut" do
      AsciicrystalPDF::HyphCli.available_source_url.should eq AsciicrystalPDF::HyphCli::DEFAULT_AVAILABLE_URL
      ENV["CTAN_MIRROR"] = "https://ctan.example.org/"
      AsciicrystalPDF::HyphCli.available_source_url.should eq "https://ctan.example.org/"
      ENV["HYPH_MIRROR"] = "https://hyph.example.org/"
      AsciicrystalPDF::HyphCli.available_source_url.should eq "https://hyph.example.org/"
    end
  end

  describe "cmd_available (intégration via binaire)" do
    binary = File.join(__DIR__, "..", "..", "bin", "asciicrystal-pdf")

    it "accepte le flag --json et émet du JSON valide (lecture cache)" do
      # On pré-remplit le cache pour qu'AUCUNE requête HTTP ne
      # parte (sinon CI sans réseau plante).
      pending! "binaire absent, build manquant : #{binary}" unless File::Info.executable?(binary)
      Dir.mkdir_p(AsciicrystalPDF::HyphCli.xdg_cache_dir)
      File.write(
        AsciicrystalPDF::HyphCli.available_cache_file,
        {
          "source"     => "https://test.invalid/",
          "fetched_at" => Time.utc.to_rfc3339,
          "langs"      => ["fr", "en-us", "ja", "zh"],
        }.to_json,
      )

      env = {
        "XDG_CACHE_HOME" => ENV["XDG_CACHE_HOME"],
      }
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(binary, ["hyph", "available", "--json"], env: env, output: stdout, error: stderr)
      status.exit_code.should eq 0
      payload = JSON.parse(stdout.to_s)
      payload["patterns"].as_a.size.should be > 0
      payload["total"].as_i.should be > 0
      # Champ "lang" présent sur chaque entrée.
      payload["patterns"].as_a.each do |row|
        row["lang"].as_s.should_not be_empty
        # Champ "ctan" booléen.
        [true, false].includes?(row["ctan"].as_bool).should be_true
      end
    end

    it "supporte -j comme alias court de --json" do
      pending! "binaire absent, build manquant : #{binary}" unless File::Info.executable?(binary)
      Dir.mkdir_p(AsciicrystalPDF::HyphCli.xdg_cache_dir)
      File.write(
        AsciicrystalPDF::HyphCli.available_cache_file,
        {"source" => "x", "fetched_at" => Time.utc.to_rfc3339, "langs" => ["fr"]}.to_json,
      )
      env = {"XDG_CACHE_HOME" => ENV["XDG_CACHE_HOME"]}
      stdout = IO::Memory.new
      status = Process.run(binary, ["hyph", "available", "-j"], env: env, output: stdout, error: Process::Redirect::Close)
      status.exit_code.should eq 0
      # Doit être du JSON parseable.
      JSON.parse(stdout.to_s).should_not be_nil
    end

    it "rejette un flag inconnu avec exit 2" do
      pending! "binaire absent, build manquant : #{binary}" unless File::Info.executable?(binary)
      env = {"XDG_CACHE_HOME" => ENV["XDG_CACHE_HOME"]}
      status = Process.run(binary, ["hyph", "available", "--foo"],
        env: env, output: Process::Redirect::Close, error: Process::Redirect::Close)
      status.exit_code.should eq AsciicrystalPDF::HyphCli::EXIT_USAGE
    end

    it "lit le cache sans HTTP quand il existe et qu'on n'a pas --refresh-cache" do
      pending! "binaire absent, build manquant : #{binary}" unless File::Info.executable?(binary)
      # On dirige HYPH_MIRROR sur une URL non routable : si une
      # requête partait, la commande échouerait. Comme le cache
      # est frais, aucun fetch ne doit se produire.
      Dir.mkdir_p(AsciicrystalPDF::HyphCli.xdg_cache_dir)
      File.write(
        AsciicrystalPDF::HyphCli.available_cache_file,
        {"source" => "x", "fetched_at" => Time.utc.to_rfc3339, "langs" => ["fr", "ja"]}.to_json,
      )
      env = {
        "XDG_CACHE_HOME" => ENV["XDG_CACHE_HOME"],
        "HYPH_MIRROR"    => "http://127.0.0.1:1/should-not-be-called",
      }
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(binary, ["hyph", "available", "--json"], env: env, output: stdout, error: stderr)
      status.exit_code.should eq 0
      # `ja` ne fait pas partie du manifest embarqué (ni installé)
      # mais doit apparaître via le cache.
      langs_in_output = JSON.parse(stdout.to_s)["patterns"].as_a.map(&.["lang"].as_s)
      langs_in_output.includes?("ja").should be_true
    end
  end
end
