require "./spec_helper"
require "file_utils"

# Helper : exécute un bloc avec un répertoire XDG temporaire
# pointé par la variable d'environnement `XDG_CONFIG_HOME`.
# Restaure la valeur d'origine en sortie.
private def with_xdg_dir(&)
  tmp = File.tempname("xdg-config")
  Dir.mkdir_p(tmp)
  previous = ENV["XDG_CONFIG_HOME"]?
  ENV["XDG_CONFIG_HOME"] = tmp
  begin
    yield tmp
  ensure
    if previous
      ENV["XDG_CONFIG_HOME"] = previous
    else
      ENV.delete("XDG_CONFIG_HOME")
    end
    FileUtils.rm_rf(tmp)
  end
end

private def write_config(xdg_dir : String, content : String) : String
  shard_dir = File.join(xdg_dir, AsciicrystalPDF::UserConfig::SHARD_NAME)
  Dir.mkdir_p(shard_dir)
  config_path = File.join(shard_dir, AsciicrystalPDF::UserConfig::CONFIG_FILENAME)
  File.write(config_path, content)
  shard_dir
end

describe AsciicrystalPDF::UserConfig do
  describe ".expected_dir" do
    it "respecte XDG_CONFIG_HOME quand la variable est définie" do
      with_xdg_dir do |tmp|
        AsciicrystalPDF::UserConfig.expected_dir.should eq(File.join(tmp, "asciicrystal-pdf"))
      end
    end

    it "tombe sur ~/.config/asciicrystal-pdf si XDG_CONFIG_HOME est vide" do
      previous = ENV["XDG_CONFIG_HOME"]?
      ENV["XDG_CONFIG_HOME"] = ""
      begin
        expected = File.join(AsciicrystalPDF::UserConfig.home_dir, ".config", "asciicrystal-pdf")
        AsciicrystalPDF::UserConfig.expected_dir.should eq(expected)
      ensure
        if previous
          ENV["XDG_CONFIG_HOME"] = previous
        else
          ENV.delete("XDG_CONFIG_HOME")
        end
      end
    end
  end

  describe ".load" do
    it "retourne une config vide si le répertoire n'existe pas" do
      with_xdg_dir do
        cfg = AsciicrystalPDF::UserConfig.load
        cfg.empty?.should be_true
      end
    end

    it "lit theme + attributes + identité depuis config.yml" do
      with_xdg_dir do |tmp|
        write_config(tmp, <<-YAML)
          theme: fr
          attributes:
            title-page-toc: "true"
            toc: macro
            pdf-page-size: A4
          author: Philippe Nénert
          email: philippe@aloli.fr
          organization: ALOLI sas
        YAML

        cfg = AsciicrystalPDF::UserConfig.load
        cfg.theme.should eq("fr")
        cfg.attributes["title-page-toc"].should eq("true")
        cfg.attributes["toc"].should eq("macro")
        cfg.attributes["pdf-page-size"].should eq("A4")
        cfg.author.should eq("Philippe Nénert")
        cfg.email.should eq("philippe@aloli.fr")
        cfg.organization.should eq("ALOLI sas")
        cfg.empty?.should be_false
      end
    end

    it "lit `open:` (true / false) pour piloter l'ouverture auto" do
      AsciicrystalPDF::UserConfig.from_yaml("open: true").open.should be_true
      AsciicrystalPDF::UserConfig.from_yaml("open: false").open.should be_false
    end

    it "`open` vaut nil quand la clé est absente (⇒ ouverture par défaut)" do
      AsciicrystalPDF::UserConfig.empty.open.should be_nil
      AsciicrystalPDF::UserConfig.from_yaml("theme: fr").open.should be_nil
    end

    it "tolère un YAML cassé en retournant une config vide" do
      with_xdg_dir do |tmp|
        write_config(tmp, ":\n  not valid: yaml: at all\n  ")
        cfg = AsciicrystalPDF::UserConfig.load
        cfg.empty?.should be_true
      end
    end
  end

  describe "#merge_into" do
    it "n'écrase PAS les attributs déjà présents (priorité au document/CLI)" do
      cfg = AsciicrystalPDF::UserConfig.from_yaml(<<-YAML)
        attributes:
          toc: macro
          pdf-page-size: A4
      YAML

      target = {"toc" => "left", "docfile" => "test.adoc"} of String => String
      cfg.merge_into(target)

      target["toc"].should eq("left") # déjà présent, intact
      # Ajouté par la config en SOFT-SET (suffixe `@`) : c'est un
      # défaut que l'en-tête du document pourra surcharger.
      target["pdf-page-size"].should eq("A4@")
      target["docfile"].should eq("test.adoc") # intact
    end

    it "ajoute auteur/email/organization (en soft-set) si absents" do
      cfg = AsciicrystalPDF::UserConfig.from_yaml(<<-YAML)
        author: Philippe
        email: p@aloli.fr
        organization: ALOLI
      YAML

      target = {} of String => String
      cfg.merge_into(target)
      # Soft-set (`@` final) : le document garde la priorité s'il
      # définit ses propres méta. L'@ interne de l'email est intact,
      # seul le marqueur final est ajouté.
      target["author"].should eq("Philippe@")
      target["email"].should eq("p@aloli.fr@")
      target["organization"].should eq("ALOLI@")
    end

    it "respecte un author déjà présent" do
      cfg = AsciicrystalPDF::UserConfig.from_yaml("author: Philippe")
      target = {"author" => "Marie"} of String => String
      cfg.merge_into(target)
      target["author"].should eq("Marie")
    end
  end

  describe "#resolve_theme" do
    it "retourne nil si aucun theme n'est déclaré" do
      cfg = AsciicrystalPDF::UserConfig.empty
      cfg.resolve_theme.should be_nil
    end

    it "résout un nom embarqué (fr)" do
      cfg = AsciicrystalPDF::UserConfig.from_yaml("theme: fr")
      theme = cfg.resolve_theme
      theme.should_not be_nil
      # Le thème fr a au moins une langue/locale ; on vérifie juste qu'on en a un
      theme.is_a?(AsciicrystalPDF::Theme).should be_true
    end

    it "résout un thème utilisateur dans <base_dir>/themes/<name>.yml" do
      with_xdg_dir do |tmp|
        shard_dir = File.join(tmp, AsciicrystalPDF::UserConfig::SHARD_NAME)
        themes_dir = File.join(shard_dir, "themes")
        Dir.mkdir_p(themes_dir)
        File.write(File.join(themes_dir, "aloli.yml"), <<-YAML)
          base_font_size: 11.5
          page_size: A4
        YAML
        File.write(File.join(shard_dir, "config.yml"), "theme: aloli\n")

        cfg = AsciicrystalPDF::UserConfig.load
        theme = cfg.resolve_theme
        theme.should_not be_nil
        theme.not_nil!.base_font_size.should eq(11.5)
      end
    end

    it "résout un chemin absolu" do
      tmp_theme = File.tempname("theme", ".yml")
      File.write(tmp_theme, "base_font_size: 13.0\n")
      begin
        cfg = AsciicrystalPDF::UserConfig.from_yaml("theme: #{tmp_theme}")
        theme = cfg.resolve_theme
        theme.should_not be_nil
        theme.not_nil!.base_font_size.should eq(13.0)
      ensure
        File.delete?(tmp_theme)
      end
    end
  end

  describe "#empty?" do
    it "vrai pour une config sans rien" do
      AsciicrystalPDF::UserConfig.empty.empty?.should be_true
    end

    it "faux dès qu'un seul champ est rempli" do
      AsciicrystalPDF::UserConfig.from_yaml("theme: fr").empty?.should be_false
      AsciicrystalPDF::UserConfig.from_yaml("author: X").empty?.should be_false
      AsciicrystalPDF::UserConfig.from_yaml("attributes:\n  toc: macro").empty?.should be_false
    end
  end
end
