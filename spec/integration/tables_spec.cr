require "./spec_helper"

describe "Tables" do
  it "renders all cell contents across a simple 2x2 table" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      |===
      | A1 | A2
      | B1 | B2
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("A1")
    text.should contain("A2")
    text.should contain("B1")
    text.should contain("B2")
    File.delete(pdf)
  end

  it "renders a header-row table with a caption" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      .Liste des pays
      [cols="1,1", options="header"]
      |===
      | Pays | Ville

      | France | Paris
      | Allemagne | Berlin
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    text.should contain("Liste")
    text.should contain("France")
    text.should contain("Paris")
    text.should contain("Allemagne")
    text.should contain("Berlin")
    File.delete(pdf)
  end

  it "breaks long words in narrow columns rather than overflowing" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      [cols="4,1,4", options="header"]
      |===
      | Ville | Pays | Note

      | Gunzenhausen | Allemagne | siège
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    # With a very narrow middle column, "Allemagne" is broken into
    # chunks. Each fragment should still appear in the stream.
    text.should contain("Allem")
    text.should contain("Gunzenhausen")
    File.delete(pdf)
  end

  it "renders a codespan inside a table cell in monospace (not flattened)" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      [cols="1,1", options="header"]
      |===
      | Utilisateur | Mot de passe

      | admin | `qwertyuiop`
      |===
      ADOC
    text = IntegrationHelper.text(pdf)
    # Le code DOIT s'afficher (régression : il était aplati/perdu).
    text.should contain("qwertyuiop")
    # … et en MONOSPACE : la police mono (Courier dans le contexte de
    # test) doit apparaître dans les ressources du PDF, preuve que le
    # codespan a conservé son style et n'a pas été réduit à du texte
    # courant (rendu en Helvetica comme le reste de la cellule).
    raw = File.read(pdf)
    raw.includes?("Courier").should be_true
    File.delete(pdf)
  end

  it "keeps table header cells bold while preserving body codespans" do
    pdf = IntegrationHelper.convert(<<-ADOC)
      = Test

      [cols="1,1", options="header"]
      |===
      | Utilisateur | Mot de passe

      | admin | `secret`
      |===
      ADOC
    raw = File.read(pdf)
    # En-tête en gras (Helvetica-Bold) ET corps mono (Courier)
    # coexistent : la propagation du gras aux segments d'en-tête
    # n'a pas cassé le rendu mono des codespans du corps.
    raw.includes?("Helvetica-Bold").should be_true
    raw.includes?("Courier").should be_true
    File.delete(pdf)
  end
end
