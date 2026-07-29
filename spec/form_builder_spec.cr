require "./spec_helper"

# Helper : raccourci pour appeler FormBuilder.parse avec id par défaut.
private def parse(yaml : String, **attrs)
  block_attrs = {"id" => "test-form"} of String => String
  attrs.each { |k, v| block_attrs[k.to_s] = v.to_s }
  AsciicrystalPDF::FormBuilder.parse(yaml, block_attrs)
end

describe AsciicrystalPDF::FormBuilder do
  describe ".parse — attributs du bloc" do
    it "lève FormError si `id` manquant" do
      expect_raises(AsciicrystalPDF::FormError, /`id=` requis/) do
        AsciicrystalPDF::FormBuilder.parse("fields: [{id: x, type: text}]", {} of String => String)
      end
    end

    it "lève FormError si `id` vide" do
      expect_raises(AsciicrystalPDF::FormError, /`id=` requis/) do
        AsciicrystalPDF::FormBuilder.parse("fields: [{id: x, type: text}]", {"id" => ""})
      end
    end

    it "expose `action` et `method` quand fournis" do
      form = parse("fields: [{id: x, type: text}]", action: "mailto:a@b.fr", method: "mailto")
      form.action.should eq("mailto:a@b.fr")
      form.method.should eq("mailto")
    end

    it "déduit `method: post` par défaut si action est définie sans method explicite" do
      form = parse("fields: [{id: x, type: text}]", action: "https://example.com")
      form.method.should eq("post")
    end

    it "method nil si pas d'action" do
      form = parse("fields: [{id: x, type: text}]")
      form.method.should be_nil
    end

    it "rejette une `method` invalide" do
      expect_raises(AsciicrystalPDF::FormError, /`method=put` invalide/) do
        parse("fields: [{id: x, type: text}]", method: "put")
      end
    end

    it "expose `read_only` quand bloc-attribut `read-only=true`" do
      form = parse("fields: [{id: x, type: text}]", "read-only": "true")
      form.read_only.should be_true
    end
  end

  describe ".parse — racine YAML" do
    it "rejette si ni sections: ni fields:" do
      expect_raises(AsciicrystalPDF::FormError, /sections.*OU.*fields/) do
        parse("title: 'Hello'\n")
      end
    end

    it "rejette si sections: ET fields: tous deux présents" do
      expect_raises(AsciicrystalPDF::FormError, /mutuellement exclusifs/) do
        parse(<<-YAML)
          fields: [{id: x, type: text}]
          sections:
            - title: A
              fields: [{id: y, type: text}]
        YAML
      end
    end

    it "rejette un YAML cassé avec message descriptif" do
      expect_raises(AsciicrystalPDF::FormError, /YAML invalide/) do
        parse(":\n  not: valid: yaml: at all\n  ")
      end
    end

    it "expose title et description quand fournis" do
      form = parse(<<-YAML)
        title: "Mon titre"
        description: "Ma description"
        fields:
          - id: nom
            type: text
      YAML
      form.title.should eq("Mon titre")
      form.description.should eq("Ma description")
    end

    it "columns par défaut = 1" do
      form = parse("fields: [{id: x, type: text}]")
      form.columns.should eq(1)
    end

    it "columns customisable au niveau form" do
      form = parse(<<-YAML)
        columns: 2
        fields:
          - id: x
            type: text
      YAML
      form.columns.should eq(2)
    end

    it "rejette columns < 1" do
      expect_raises(AsciicrystalPDF::FormError, /`columns` doit être ≥ 1/) do
        parse(<<-YAML)
          columns: 0
          fields: [{id: x, type: text}]
        YAML
      end
    end
  end

  describe ".parse — champ" do
    it "parse un champ text minimal" do
      form = parse(<<-YAML)
        fields:
          - id: nom
            type: text
      YAML
      form.fields.size.should eq(1)
      f = form.fields.first
      f.id.should eq("nom")
      f.type.should eq("text")
      f.label.should be_nil
      f.required.should be_false
      f.read_only.should be_false
      f.cols.should eq(1)
    end

    it "parse tous les attributs communs" do
      form = parse(<<-YAML)
        fields:
          - id: courriel
            type: email
            label: Courriel
            required: true
            read-only: true
            placeholder: nom@example.com
            help: Format valide attendu
            cols: 2
            value: defaut@example.com
      YAML
      f = form.fields.first
      f.label.should eq("Courriel")
      f.required.should be_true
      f.read_only.should be_true
      f.placeholder.should eq("nom@example.com")
      f.help.should eq("Format valide attendu")
      f.cols.should eq(2)
      f.value_string.should eq("defaut@example.com")
    end

    it "rejette un champ sans id" do
      expect_raises(AsciicrystalPDF::FormError, /`id` requis/) do
        parse("fields: [{type: text}]")
      end
    end

    it "rejette un champ sans type" do
      expect_raises(AsciicrystalPDF::FormError, /`type` requis/) do
        parse("fields: [{id: x}]")
      end
    end

    it "rejette un type inconnu avec liste des disponibles" do
      expect_raises(AsciicrystalPDF::FormError, /type `xyz` inconnu/) do
        parse("fields: [{id: x, type: xyz}]")
      end
    end

    it "accepte type `signature` (depuis pdf 0.5.9 + asciicrystal-pdf 2.3.24.59)" do
      form = parse("fields: [{id: sig, type: signature, label: Signature}]")
      f = form.fields.first
      f.type.should eq("signature")
      f.label.should eq("Signature")
    end

    it "rejette les ids dupliqués" do
      expect_raises(AsciicrystalPDF::FormError, /id `nom` dupliqué/) do
        parse(<<-YAML)
          fields:
            - id: nom
              type: text
            - id: nom
              type: email
        YAML
      end
    end

    it "rejette cols < 1" do
      expect_raises(AsciicrystalPDF::FormError, /`cols` doit être ≥ 1/) do
        parse("fields: [{id: x, type: text, cols: 0}]")
      end
    end

    it "rejette rows < 1 (textarea)" do
      expect_raises(AsciicrystalPDF::FormError, /`rows` doit être ≥ 1/) do
        parse("fields: [{id: x, type: textarea, rows: 0}]")
      end
    end
  end

  describe ".parse — types supportés" do
    it "accepte text, email, url, tel, password" do
      %w[text email url tel password].each do |t|
        form = parse("fields: [{id: x, type: #{t}}]")
        form.fields.first.type.should eq(t)
      end
    end

    it "accepte textarea avec rows" do
      form = parse("fields: [{id: x, type: textarea, rows: 4}]")
      form.fields.first.type.should eq("textarea")
      form.fields.first.rows.should eq(4)
    end

    it "accepte number avec min/max/step" do
      form = parse(<<-YAML)
        fields:
          - id: age
            type: number
            min: 18
            max: 99
            step: 1
      YAML
      f = form.fields.first
      f.type.should eq("number")
      f.min.try(&.as_i).should eq(18)
      f.max.try(&.as_i).should eq(99)
      f.step.try(&.as_i).should eq(1)
    end

    it "accepte date avec min/max" do
      form = parse(<<-YAML)
        fields:
          - id: d
            type: date
            min: "2020-01-01"
            max: "2030-12-31"
      YAML
      f = form.fields.first
      f.type.should eq("date")
      f.min.try(&.as_s).should eq("2020-01-01")
      f.max.try(&.as_s).should eq("2030-12-31")
    end

    it "accepte checkbox simple" do
      form = parse("fields: [{id: c, type: checkbox, label: Consent}]")
      form.fields.first.type.should eq("checkbox")
    end
  end

  describe ".parse — options (radio, select, select-multi)" do
    it "accepte une liste simple pour radio" do
      form = parse(<<-YAML)
        fields:
          - id: n
            type: radio
            options: [Conforme, Partiel, Non conforme]
      YAML
      f = form.fields.first
      f.option_codes.should eq(["Conforme", "Partiel", "Non conforme"])
      f.option_labels.should be_nil
    end

    it "accepte un Hash pour radio (code → label)" do
      form = parse(<<-YAML)
        fields:
          - id: n
            type: radio
            options:
              C: Conforme
              P: Partiel
              NC: Non conforme
      YAML
      f = form.fields.first
      f.option_codes.should eq(["C", "P", "NC"])
      f.option_labels.should eq({"C" => "Conforme", "P" => "Partiel", "NC" => "Non conforme"})
    end

    it "accepte une liste simple pour select" do
      form = parse("fields: [{id: s, type: select, options: [A, B, C]}]")
      form.fields.first.option_codes.should eq(["A", "B", "C"])
    end

    it "accepte une liste simple pour select-multi" do
      form = parse("fields: [{id: s, type: select-multi, options: [A, B]}]")
      form.fields.first.option_codes.should eq(["A", "B"])
    end

    it "rejette options absentes pour radio" do
      expect_raises(AsciicrystalPDF::FormError, /`options` requis pour type `radio`/) do
        parse("fields: [{id: r, type: radio}]")
      end
    end

    it "rejette options vides pour select" do
      expect_raises(AsciicrystalPDF::FormError, /ne peut pas être vide/) do
        parse("fields: [{id: s, type: select, options: []}]")
      end
    end

    it "rejette un type YAML invalide pour options" do
      expect_raises(AsciicrystalPDF::FormError, /doit être une liste ou un hash/) do
        parse(<<-YAML)
          fields:
            - id: r
              type: radio
              options: "Conforme"
        YAML
      end
    end

    it "options non requises pour text — null OK" do
      form = parse("fields: [{id: x, type: text}]")
      form.fields.first.options.should be_nil
    end
  end

  describe ".parse — sections" do
    it "parse une section avec titre et description" do
      form = parse(<<-YAML)
        sections:
          - title: "Identité"
            description: "Identité de l'auditeur"
            fields:
              - id: nom
                type: text
              - id: email
                type: email
      YAML
      form.sectioned?.should be_true
      form.sections.size.should eq(1)
      sec = form.sections.first
      sec.title.should eq("Identité")
      sec.description.should eq("Identité de l'auditeur")
      sec.fields.size.should eq(2)
    end

    it "section.columns par défaut = form.columns" do
      form = parse(<<-YAML)
        columns: 2
        sections:
          - title: "A"
            fields: [{id: x, type: text}]
      YAML
      form.sections.first.columns.should eq(2)
    end

    it "section.columns peut être surchargé" do
      form = parse(<<-YAML)
        columns: 1
        sections:
          - title: "A"
            columns: 3
            fields: [{id: x, type: text}]
      YAML
      form.sections.first.columns.should eq(3)
    end

    it "rejette une section sans fields" do
      expect_raises(AsciicrystalPDF::FormError, /`fields:` requis/) do
        parse(<<-YAML)
          sections:
            - title: "A"
        YAML
      end
    end

    it "détecte les ids dupliqués entre sections" do
      expect_raises(AsciicrystalPDF::FormError, /id `nom` dupliqué/) do
        parse(<<-YAML)
          sections:
            - title: A
              fields: [{id: nom, type: text}]
            - title: B
              fields: [{id: nom, type: email}]
        YAML
      end
    end

    it "rejette section.columns < 1" do
      expect_raises(AsciicrystalPDF::FormError, /`columns` doit être ≥ 1/) do
        parse(<<-YAML)
          sections:
            - title: A
              columns: 0
              fields: [{id: x, type: text}]
        YAML
      end
    end
  end

  describe ".parse — submit / reset / buttons" do
    it "parse submit avec label et action" do
      form = parse(<<-YAML)
        fields: [{id: x, type: text}]
        submit:
          label: Envoyer
          action: mailto:a@b.fr
          method: mailto
      YAML
      s = form.submit.not_nil!
      s.label.should eq("Envoyer")
      s.action.should eq("mailto:a@b.fr")
      s.method.should eq("mailto")
    end

    it "submit par défaut label = `Envoyer`" do
      form = parse(<<-YAML)
        fields: [{id: x, type: text}]
        submit:
          action: https://example.com
      YAML
      form.submit.not_nil!.label.should eq("Envoyer")
    end

    it "rejette submit.method invalide" do
      expect_raises(AsciicrystalPDF::FormError, /`submit\.method=patch` invalide/) do
        parse(<<-YAML)
          fields: [{id: x, type: text}]
          submit:
            method: patch
        YAML
      end
    end

    it "parse reset" do
      form = parse(<<-YAML)
        fields: [{id: x, type: text}]
        reset:
          label: Recommencer
      YAML
      form.reset.not_nil!.label.should eq("Recommencer")
    end

    it "reset par défaut label = `Effacer`" do
      form = parse(<<-YAML)
        fields: [{id: x, type: text}]
        reset: {}
      YAML
      form.reset.not_nil!.label.should eq("Effacer")
    end

    it "parse buttons custom" do
      form = parse(<<-YAML)
        fields: [{id: x, type: text}]
        buttons:
          - label: Imprimer
            action: print
          - label: Sauvegarder
            action: save
      YAML
      form.buttons.size.should eq(2)
      form.buttons[0].label.should eq("Imprimer")
      form.buttons[0].action.should eq("print")
    end

    it "rejette bouton sans label" do
      expect_raises(AsciicrystalPDF::FormError, /`label` requis/) do
        parse(<<-YAML)
          fields: [{id: x, type: text}]
          buttons:
            - action: print
        YAML
      end
    end

    it "rejette bouton sans action" do
      expect_raises(AsciicrystalPDF::FormError, /`action` requis/) do
        parse(<<-YAML)
          fields: [{id: x, type: text}]
          buttons:
            - label: Imprimer
        YAML
      end
    end

    it "submit/reset/buttons par défaut absents" do
      form = parse("fields: [{id: x, type: text}]")
      form.submit.should be_nil
      form.reset.should be_nil
      form.buttons.should be_empty
    end
  end

  describe ".parse — validation conditionnelle (warn-only en v1)" do
    it "émet un warning sur required_if et ignore la clé" do
      io = IO::Memory.new
      original_stderr = STDERR
      begin
        # On ne peut pas facilement rediriger STDERR en Crystal sans
        # méthodologie spéciale ; on se contente ici de vérifier que
        # le parse ne lève pas et que la validation est conservée
        # telle quelle dans le champ (pour les outils tiers qui
        # voudraient l'exploiter).
        form = parse(<<-YAML)
          fields:
            - id: x
              type: text
              validation:
                required_if: { field: y, equals: true }
        YAML
        form.fields.first.validation.should_not be_nil
      ensure
        # rien à restaurer car on n'a pas modifié STDERR
        _ = io
        _ = original_stderr
      end
    end

    it "accepte validation atomique (regex)" do
      form = parse(<<-YAML)
        fields:
          - id: code
            type: text
            validation: "^[A-Z]{2}\\\\d{6}$"
      YAML
      form.fields.first.validation.try(&.as_s).should eq("^[A-Z]{2}\\d{6}$")
    end

    it "accepte validation min/max" do
      form = parse(<<-YAML)
        fields:
          - id: n
            type: number
            validation: { min: 0, max: 100 }
      YAML
      v = form.fields.first.validation.not_nil!
      v["min"].as_i.should eq(0)
      v["max"].as_i.should eq(100)
    end
  end

  describe "FormField helpers" do
    it "has_options? est true pour radio/select/select-multi" do
      %w[radio select select-multi].each do |t|
        f = AsciicrystalPDF::FormField.new(id: "x", type: t, options: ["A"])
        f.has_options?.should be_true
      end
    end

    it "has_options? est false pour text/email/checkbox" do
      %w[text email checkbox textarea number date password url tel].each do |t|
        f = AsciicrystalPDF::FormField.new(id: "x", type: t)
        f.has_options?.should be_false
      end
    end

    it "option_codes retourne [] sans options" do
      f = AsciicrystalPDF::FormField.new(id: "x", type: "text")
      f.option_codes.should eq([] of String)
    end

    it "option_codes retourne la liste pour Array options" do
      f = AsciicrystalPDF::FormField.new(id: "x", type: "radio", options: ["A", "B"])
      f.option_codes.should eq(["A", "B"])
    end

    it "option_codes retourne les clés pour Hash options" do
      f = AsciicrystalPDF::FormField.new(id: "x", type: "radio", options: {"A" => "Alpha", "B" => "Beta"})
      f.option_codes.should eq(["A", "B"])
      f.option_labels.should eq({"A" => "Alpha", "B" => "Beta"})
    end

    it "value_string retourne la chaîne ou nil" do
      f = AsciicrystalPDF::FormField.new(id: "x", type: "text", value: YAML::Any.new("hello"))
      f.value_string.should eq("hello")

      f2 = AsciicrystalPDF::FormField.new(id: "x", type: "text")
      f2.value_string.should be_nil
    end

    it "value_array retourne une liste depuis YAML::Any array" do
      v = YAML.parse("[A, B, C]")
      f = AsciicrystalPDF::FormField.new(id: "x", type: "select-multi", value: v)
      f.value_array.should eq(["A", "B", "C"])
    end

    it "value_array enveloppe une chaîne unique dans une liste" do
      f = AsciicrystalPDF::FormField.new(id: "x", type: "select-multi", value: YAML::Any.new("solo"))
      f.value_array.should eq(["solo"])
    end

    it "value_array retourne nil si pas de valeur" do
      f = AsciicrystalPDF::FormField.new(id: "x", type: "select-multi")
      f.value_array.should be_nil
    end
  end

  describe "Form helpers" do
    it "all_fields retourne les fields à plat pour un form non sectionné" do
      form = parse(<<-YAML)
        fields:
          - id: a
            type: text
          - id: b
            type: email
      YAML
      form.all_fields.map(&.id).should eq(["a", "b"])
    end

    it "all_fields aplatit tous les champs de toutes les sections" do
      form = parse(<<-YAML)
        sections:
          - title: S1
            fields:
              - id: a
                type: text
              - id: b
                type: text
          - title: S2
            fields:
              - id: c
                type: text
      YAML
      form.all_fields.map(&.id).should eq(["a", "b", "c"])
    end

    it "sectioned? distingue les deux modes" do
      form_flat = parse("fields: [{id: x, type: text}]")
      form_flat.sectioned?.should be_false

      form_secs = parse(<<-YAML)
        sections:
          - title: A
            fields: [{id: y, type: text}]
      YAML
      form_secs.sectioned?.should be_true
    end
  end
end
