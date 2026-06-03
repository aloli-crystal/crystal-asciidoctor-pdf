require "./spec_helper"

include AsciidoctorPDF

# Mesure simpliste pour les tests : 1 point PDF par caractère.
# Permet de calculer à la main les largeurs attendues sans dépendre
# d'une police TTF chargée.
WIDTH_OF_CHAR = ->(_seg : InlineSegment, text : String) { text.size.to_f }

private def seg(text : String, bold : Bool = false) : InlineSegment
  InlineSegment.new(text: text, bold: bold)
end

describe AsciidoctorPDF::ParagraphComposer do
  describe ".tokenize" do
    it "émet une seule Box pour un mot isolé" do
      tokens = ParagraphComposer.tokenize([seg("hello")], 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 1
      tokens[0].should be_a ParagraphComposer::Box
      tokens[0].as(ParagraphComposer::Box).segment.text.should eq "hello"
      tokens[0].as(ParagraphComposer::Box).width.should eq 5.0
    end

    it "émet Box Glue Box pour deux mots séparés par espace ASCII" do
      tokens = ParagraphComposer.tokenize([seg("foo bar")], 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 3
      tokens[0].should be_a ParagraphComposer::Box
      tokens[1].should be_a ParagraphComposer::Glue
      tokens[2].should be_a ParagraphComposer::Box
      tokens[0].as(ParagraphComposer::Box).segment.text.should eq "foo"
      tokens[2].as(ParagraphComposer::Box).segment.text.should eq "bar"
      tokens[1].as(ParagraphComposer::Glue).width.should eq 1.0
    end

    it "absorbe la NBSP dans la Box voisine (insécable)" do
      # « deploy : il » — la NBSP française entre `deploy` et `:`
      # doit lier le groupe en un seul atome insécable.
      tokens = ParagraphComposer.tokenize([seg("deploy : il")], 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 3
      tokens[0].should be_a ParagraphComposer::Box
      tokens[1].should be_a ParagraphComposer::Glue
      tokens[2].should be_a ParagraphComposer::Box
      tokens[0].as(ParagraphComposer::Box).segment.text.should eq "deploy :"
      tokens[2].as(ParagraphComposer::Box).segment.text.should eq "il"
    end

    it "préserve plusieurs groupes NBSP sans introduire de Glue" do
      # « deploy : il » — chaîne entièrement liée par NBSP.
      tokens = ParagraphComposer.tokenize([seg("deploy : il")], 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 1
      tokens[0].should be_a ParagraphComposer::Box
      tokens[0].as(ParagraphComposer::Box).segment.text.should eq "deploy : il"
    end

    it "alterne correctement Box et Glue avec mix NBSP / espace ASCII" do
      # « a b c d » → Box("a b") Glue Box("c") Glue Box("d")
      tokens = ParagraphComposer.tokenize([seg("a b c d")], 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 5
      tokens.map(&.class).should eq [
        ParagraphComposer::Box,
        ParagraphComposer::Glue,
        ParagraphComposer::Box,
        ParagraphComposer::Glue,
        ParagraphComposer::Box,
      ]
      tokens[0].as(ParagraphComposer::Box).segment.text.should eq "a b"
      tokens[2].as(ParagraphComposer::Box).segment.text.should eq "c"
      tokens[4].as(ParagraphComposer::Box).segment.text.should eq "d"
    end

    it "émet un Penalty forcé pour line_break" do
      segments = [
        seg("foo"),
        InlineSegment.new(text: "", line_break: true),
        seg("bar"),
      ]
      tokens = ParagraphComposer.tokenize(segments, 10.0, &WIDTH_OF_CHAR)
      # Box(foo) Penalty Glue(inter-seg) Box(bar)
      tokens[0].should be_a ParagraphComposer::Box
      tokens[1].should be_a ParagraphComposer::Penalty
      pen = tokens[1].as(ParagraphComposer::Penalty)
      pen.cost.should eq ParagraphComposer::NEG_INFINITY
      pen.width.should eq 0.0
    end

    it "émet une Box atomique pour une image inline" do
      img = InlineSegment.new(text: "alt", image_path: "/tmp/x.png", image_width: 24.0)
      tokens = ParagraphComposer.tokenize([img], 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 1
      tokens[0].should be_a ParagraphComposer::Box
      # 24.0 (image_width) + 2.0 (padding inter-élément historique)
      tokens[0].as(ParagraphComposer::Box).width.should eq 26.0
    end

    it "NE colle PAS deux segments contigus avec une Glue artificielle" do
      # Cas `<strong>foo</strong>bar` : segments [Bold("foo"), Plain("bar")]
      # sans espace explicite. Le rendu attendu est `foobar` (pas
      # `foo bar`). Régression : la version J1 originale injectait
      # un Glue ici, ce qui ajoutait un espace après chaque codespan
      # avant la ponctuation suivante (« `code` ) » au lieu de
      # « `code`) »).
      segments = [seg("foo", bold: true), seg("bar")]
      tokens = ParagraphComposer.tokenize(segments, 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 2
      tokens[0].should be_a ParagraphComposer::Box
      tokens[1].should be_a ParagraphComposer::Box
    end

    it "préserve le `)` collé après un codespan" do
      # Cas typique : `(ex : ` `code` `)` en AsciiDoc → 3 segments
      # [Plain("(ex : "), Mono("code"), Plain(")")]. Le rendu
      # final doit être `(ex : code)` sans espace fantôme avant `)`.
      segments = [
        seg("(ex : "),
        InlineSegment.new(text: "code", mono: true),
        seg(")"),
      ]
      tokens = ParagraphComposer.tokenize(segments, 10.0, &WIDTH_OF_CHAR)
      # Attendu : Box("(ex : "), Glue (trailing space seg1), Box("code"), Box(")")
      # PAS de Glue entre Box("code") et Box(")").
      tokens.size.should eq 4
      tokens[0].should be_a ParagraphComposer::Box
      tokens[1].should be_a ParagraphComposer::Glue
      tokens[2].should be_a ParagraphComposer::Box
      tokens[3].should be_a ParagraphComposer::Box
      tokens[0].as(ParagraphComposer::Box).segment.text.should eq "(ex :"
      tokens[2].as(ParagraphComposer::Box).segment.text.should eq "code"
      tokens[3].as(ParagraphComposer::Box).segment.text.should eq ")"
    end

    it "émet une Glue (sans Box) pour un segment whitespace-only" do
      # Cas où le HTML parser produit [Bold("foo"), Plain(" "), Italic("bar")]
      # avec l'espace dans un segment séparé. Doit produire un seul
      # Glue (pas zéro, pas plus).
      segments = [seg("foo", bold: true), seg(" "), seg("bar")]
      tokens = ParagraphComposer.tokenize(segments, 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 3
      tokens[0].should be_a ParagraphComposer::Box
      tokens[1].should be_a ParagraphComposer::Glue
      tokens[2].should be_a ParagraphComposer::Box
    end

    it "déduplique les Glues consécutives (trailing space + leading space)" do
      # Cas pathologique mais possible : seg1=`foo ` (trailing) +
      # seg2=` bar` (leading) — l'espace est compté dans les deux
      # segments. Le rendu attendu reste `foo bar` (un seul espace).
      segments = [seg("foo "), seg(" bar")]
      tokens = ParagraphComposer.tokenize(segments, 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 3
      tokens.map(&.class).should eq [
        ParagraphComposer::Box,
        ParagraphComposer::Glue,
        ParagraphComposer::Box,
      ]
    end

    it "ignore les mots vides mais conserve la Glue (double espace)" do
      # Pathologique post-normalisation, mais doit rester robuste.
      # « foo  bar » → split=["foo", "", "bar"]. La Glue est émise
      # à idx=1 (idx>0), le mot vide n'émet pas de Box. La Glue à
      # idx=2 est dédupliquée. Résultat : Box Glue Box.
      tokens = ParagraphComposer.tokenize([seg("foo  bar")], 10.0, &WIDTH_OF_CHAR)
      tokens.size.should eq 3
      tokens.map(&.class).should eq [
        ParagraphComposer::Box,
        ParagraphComposer::Glue,
        ParagraphComposer::Box,
      ]
    end
  end

  describe ".compose_first_fit" do
    it "place tous les tokens sur une seule ligne s'ils tiennent" do
      tokens = ParagraphComposer.tokenize([seg("foo bar")], 10.0, &WIDTH_OF_CHAR)
      lines = ParagraphComposer.compose_first_fit(tokens, 100.0)
      lines.size.should eq 1
      lines[0].segments.size.should eq 2
    end

    it "casse la ligne quand la largeur cible est dépassée" do
      # « aa bb cc » avec target_w=5 : « aa » sur ligne 1, « bb » sur 2, « cc » sur 3.
      tokens = ParagraphComposer.tokenize([seg("aa bb cc")], 10.0, &WIDTH_OF_CHAR)
      lines = ParagraphComposer.compose_first_fit(tokens, 4.0)
      lines.size.should eq 3
    end

    it "ne casse JAMAIS sur une NBSP — l'insécabilité est garantie" do
      # « deploy : il » sur une largeur juste insuffisante pour
      # contenir l'atome entier : la coupure doit tomber AVANT
      # « deploy » (rien), ou avant « il » — jamais entre `deploy`
      # et `:`.
      tokens = ParagraphComposer.tokenize([seg("deploy : il")], 10.0, &WIDTH_OF_CHAR)
      lines = ParagraphComposer.compose_first_fit(tokens, 9.0)
      # « deploy : » fait 9 chars, donc tient sur une ligne ; « il » sur la suivante.
      lines.size.should eq 2
      lines[0].segments.first.text.should eq "deploy :"
      lines[1].segments.first.text.should eq "il"
    end

    it "force une coupure sur Penalty NEG_INFINITY (line_break)" do
      segments = [
        seg("foo"),
        InlineSegment.new(text: "", line_break: true),
        seg("bar"),
      ]
      tokens = ParagraphComposer.tokenize(segments, 10.0, &WIDTH_OF_CHAR)
      lines = ParagraphComposer.compose_first_fit(tokens, 1000.0)
      lines.size.should eq 2
      lines[0].segments.first.text.should eq "foo"
      lines[1].segments.first.text.should eq "bar"
    end

    it "calcule l'adjustment_ratio pour la justification" do
      # « aa bb » sur target_w=10 : natural = 2+1+2 = 5, restant = 5,
      # stretch = 0.5 → adjustment_ratio = 5 / 0.5 = 10.0.
      tokens = ParagraphComposer.tokenize([seg("aa bb")], 10.0, &WIDTH_OF_CHAR)
      lines = ParagraphComposer.compose_first_fit(tokens, 10.0)
      lines.size.should eq 1
      lines[0].adjustment_ratio.should eq 10.0
      lines[0].natural_width.should eq 5.0
      lines[0].n_spaces.should eq 1
    end

    it "préfixe d'un espace les Box précédées d'un Glue" do
      # Pour rester compatible avec render_segment_line qui consomme
      # les InlineSegment-mots avec préfix " " explicite.
      tokens = ParagraphComposer.tokenize([seg("foo bar")], 10.0, &WIDTH_OF_CHAR)
      lines = ParagraphComposer.compose_first_fit(tokens, 100.0)
      lines[0].segments[0].text.should eq "foo"
      lines[0].segments[1].text.should eq " bar"
    end
  end
end
