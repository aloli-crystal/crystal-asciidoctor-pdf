require "./spec_helper"

private DOC_HEADER = "= X-Form Integration Test\n:pdf-page-size: A4\n\n"

private def convert_and_read(form_yaml : String, *, block_attrs : String = "id=audit, action=mailto:a@b.fr") : String
  adoc = String.build do |io|
    io << DOC_HEADER
    io << "[x-form, " << block_attrs << "]\n"
    io << "----\n"
    io << form_yaml
    io << "\n----\n"
  end
  IntegrationHelper.convert(adoc)
end

describe "Integration · [x-form]" do
  describe "détection et rendu PDF de base" do
    it "produit un PDF non vide pour un formulaire minimal" do
      adoc = String.build do |io|
        io << DOC_HEADER
        io << "[x-form, id=t]\n----\nfields:\n  - id: nom\n    type: text\n----\n"
      end
      IntegrationHelper.produces_pdf?(adoc).should be_true
    end

    it "ne casse pas pour un YAML cassé (rend message d'erreur dans le PDF)" do
      adoc = String.build do |io|
        io << DOC_HEADER
        io << "[x-form, id=t]\n----\nthis is: : not yaml\n----\n"
      end
      # Le converter doit produire un PDF même si le YAML est cassé.
      # Le message d'erreur est rendu dans le PDF + STDERR.
      IntegrationHelper.produces_pdf?(adoc).should be_true
    end
  end

  describe "structure AcroForm" do
    it "inclut /AcroForm dans le PDF pour un formulaire valide" do
      pdf = convert_and_read(<<-YAML)
        fields:
          - id: nom
            type: text
            label: Nom
      YAML
      IntegrationHelper.count_byte_pattern(pdf, "/AcroForm").should be > 0
      File.delete(pdf) if File.exists?(pdf)
    end

    it "génère un widget /Tx par champ text" do
      pdf = convert_and_read(<<-YAML)
        fields:
          - id: a
            type: text
          - id: b
            type: email
          - id: c
            type: tel
      YAML
      # 3 widgets text → 3 fois /FT/Tx ou /FT /Tx
      n = IntegrationHelper.count_byte_pattern(pdf, "/FT /Tx") +
          IntegrationHelper.count_byte_pattern(pdf, "/FT/Tx")
      n.should eq(3)
      File.delete(pdf) if File.exists?(pdf)
    end

    it "génère un widget /Btn pour checkbox" do
      pdf = convert_and_read(<<-YAML)
        fields:
          - id: rgpd
            type: checkbox
            label: J'accepte
      YAML
      n = IntegrationHelper.count_byte_pattern(pdf, "/FT /Btn") +
          IntegrationHelper.count_byte_pattern(pdf, "/FT/Btn")
      n.should be > 0
      File.delete(pdf) if File.exists?(pdf)
    end

    it "génère un /Ch pour select (Combo flag)" do
      pdf = convert_and_read(<<-YAML)
        fields:
          - id: pays
            type: select
            options: [FR, BE, CH]
      YAML
      n = IntegrationHelper.count_byte_pattern(pdf, "/FT /Ch") +
          IntegrationHelper.count_byte_pattern(pdf, "/FT/Ch")
      n.should be > 0
      File.delete(pdf) if File.exists?(pdf)
    end

    it "génère un /Ch pour select-multi (MultiSelect flag)" do
      pdf = convert_and_read(<<-YAML)
        fields:
          - id: lang
            type: select-multi
            options: [FR, EN]
      YAML
      n = IntegrationHelper.count_byte_pattern(pdf, "/FT /Ch") +
          IntegrationHelper.count_byte_pattern(pdf, "/FT/Ch")
      n.should be > 0
      File.delete(pdf) if File.exists?(pdf)
    end

    it "génère un widget /Sig pour signature (pdf 0.5.9+)" do
      pdf = convert_and_read(<<-YAML)
        fields:
          - id: sig
            type: signature
            label: Signature de l'auditeur
      YAML
      n = IntegrationHelper.count_byte_pattern(pdf, "/FT /Sig") +
          IntegrationHelper.count_byte_pattern(pdf, "/FT/Sig")
      n.should be > 0
      # /SigFlags doit être présent dans le /AcroForm dict (pdf 0.5.9
      # le pose à 3 dès qu'un signature_field est ajouté).
      IntegrationHelper.count_byte_pattern(pdf, "/SigFlags").should be > 0
      File.delete(pdf) if File.exists?(pdf)
    end
  end

  describe "labels visibles dans le PDF" do
    it "rend le label d'un champ" do
      pdf = convert_and_read(<<-YAML)
        fields:
          - id: nom
            type: text
            label: Nom complet
      YAML
      text = IntegrationHelper.text(pdf)
      text.should contain("Nom complet")
      File.delete(pdf) if File.exists?(pdf)
    end

    it "ajoute une étoile aux champs required" do
      pdf = convert_and_read(<<-YAML)
        fields:
          - id: email
            type: email
            label: Courriel
            required: true
      YAML
      text = IntegrationHelper.text(pdf)
      text.should contain("Courriel")
      text.should contain("*")
      File.delete(pdf) if File.exists?(pdf)
    end

    it "rend le titre et la description du formulaire" do
      pdf = convert_and_read(<<-YAML)
        title: Audit ISO 27001
        description: Évaluation des contrôles
        fields:
          - id: nom
            type: text
      YAML
      text = IntegrationHelper.text(pdf)
      text.should contain("Audit ISO 27001")
      text.should contain("valuation")
      File.delete(pdf) if File.exists?(pdf)
    end

    it "rend le titre d'une section" do
      pdf = convert_and_read(<<-YAML)
        sections:
          - title: "A.5 Politiques"
            fields:
              - id: q1
                type: text
                label: Politique formelle ?
      YAML
      text = IntegrationHelper.text(pdf)
      text.should contain("A.5")
      text.should contain("Politiques")
      File.delete(pdf) if File.exists?(pdf)
    end
  end

  describe "comportement multi-colonnes" do
    it "rend tous les champs sans erreur avec columns: 2" do
      pdf = convert_and_read(<<-YAML)
        columns: 2
        fields:
          - id: nom
            type: text
            label: Nom
          - id: prenom
            type: text
            label: Prénom
          - id: email
            type: email
            label: Courriel
            cols: 2
          - id: tel
            type: tel
            label: Téléphone
      YAML
      n_widgets = IntegrationHelper.count_byte_pattern(pdf, "/FT /Tx") +
                  IntegrationHelper.count_byte_pattern(pdf, "/FT/Tx")
      n_widgets.should eq(4)
      File.delete(pdf) if File.exists?(pdf)
    end
  end

  describe "exemple complet" do
    it "génère un audit ISO 27001 simplifié sans crash" do
      pdf = convert_and_read(<<-YAML, block_attrs: "id=audit-iso, action=mailto:audit@aloli.fr")
        title: Audit ISO 27001
        sections:
          - title: "A.5 Politiques"
            fields:
              - id: a51
                type: radio
                label: "A.5.1 Politique définie ?"
                options: [Conforme, Partiel, Non conforme]
                required: true
              - id: a51_just
                type: textarea
                label: Justification
                rows: 3
          - title: "A.6 Organisation"
            fields:
              - id: a611
                type: radio
                label: "A.6.1.1 Rôles définis ?"
                options:
                  C: Conforme
                  P: Partiel
                  NC: Non conforme
      YAML
      File.exists?(pdf).should be_true
      File.size(pdf).should be > 1000
      # Le PDF contient bien un AcroForm
      IntegrationHelper.count_byte_pattern(pdf, "/AcroForm").should be > 0
      File.delete(pdf) if File.exists?(pdf)
    end
  end
end
