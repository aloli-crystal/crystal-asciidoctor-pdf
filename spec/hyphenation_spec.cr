require "./spec_helper"

include AsciidoctorPDF

describe AsciidoctorPDF::Hyphenation::Trie do
  it "extrait correctement chars et values d'un pattern" do
    trie = Hyphenation::Trie.new
    trie.insert("1ba")
    # Le pattern "1ba" : chars=['b','a'], values=[1, 0, 0]
    node_b = trie.root.children['b']?
    node_b.should_not be_nil
    node_ba = node_b.not_nil!.children['a']?
    node_ba.should_not be_nil
    node_ba.not_nil!.values.should eq [1, 0, 0]
  end

  it "supporte les patterns avec caractères accentués (UTF-8)" do
    trie = Hyphenation::Trie.new
    trie.insert("âm5e")
    # chars=['â','m','e'], values=[0, 0, 5, 0]
    node = trie.root.children['â']?.try &.children['m']?.try &.children['e']?
    node.should_not be_nil
    node.not_nil!.values.should eq [0, 0, 5, 0]
  end

  it "calcule les scores pour un mot via le trie" do
    trie = Hyphenation::Trie.new
    trie.insert("1ba") # frontière avant 'b' a score 1
    # Pour le mot "abba", encadré ".abba." :
    # Patterns matchant : "1ba" → substring "ba" trouvée à position 3 (.ab|ba.)
    # → score 1 à la frontière entre 'b' et 'b' du mot original
    scores = trie.scores_for("abba")
    # framed = ".abba.", scores size = 7
    scores.size.should eq 7
    # Le pattern "1ba" matche à position 3 (juste avant 'ba')
    # → scores[3] = 1
    scores[3].should eq 1
  end
end

describe AsciidoctorPDF::Hyphenation::Hyphenator do
  it "retourne les exceptions sans passer par le trie" do
    trie = Hyphenation::Trie.new
    excepts = {"syllabus" => [3, 5]}
    hyph = Hyphenation::Hyphenator.new(trie, excepts)
    hyph.hyphenate("syllabus").should eq [3, 5]
    # Insensible à la casse
    hyph.hyphenate("SYLLABUS").should eq [3, 5]
  end

  it "respecte LEFT_MIN et RIGHT_MIN" do
    trie = Hyphenation::Trie.new
    # Patterns qui donneraient des coupures à positions 1, 3, 5 d'un mot 6-char
    trie.insert("1abc") # score 1 avant 'a' → position 1 dans le mot (si abc est en pos 1-3)
    hyph = Hyphenation::Hyphenator.new(trie, {} of String => Array(Int32))
    # Position 1 < LEFT_MIN (2) → filtrée
    # Position 5 > 6 - RIGHT_MIN (3) = 3 → filtrée
    # Pour le mot "abcdef" (size 6), seules les positions 2..3 sont autorisées.
    result = hyph.hyphenate("abcdef")
    result.each do |pos|
      pos.should be >= Hyphenation::LEFT_MIN
      pos.should be <= 6 - Hyphenation::RIGHT_MIN
    end
  end
end

describe AsciidoctorPDF::Hyphenation::Loader do
  it "charge l'hyphenator français depuis les patterns embarqués" do
    hyph = Hyphenation::Loader.for("fr")
    hyph.should_not be_nil
    # « typographique » devrait être césurable : ty-po-gra-phique ou similaire
    positions = hyph.not_nil!.hyphenate("typographique")
    positions.should_not be_empty
    # Sanity check : au moins une césure dans la fenêtre [2, size-3] = [2, 10]
    positions.each do |p|
      p.should be >= 2
      p.should be <= 10
    end
  end

  it "charge l'hyphenator anglais via l'alias 'en' → 'en-us'" do
    hyph = Hyphenation::Loader.for("en")
    hyph.should_not be_nil
    # « hyphenation » : césure attendue à hy-phen-ation ou similaire
    positions = hyph.not_nil!.hyphenate("hyphenation")
    positions.should_not be_empty
  end

  it "retourne nil pour une langue non disponible" do
    Hyphenation::Loader.for("xx-unknown").should be_nil
  end

  it "cache le résultat (Loader.for retourne le même objet à 2 appels)" do
    h1 = Hyphenation::Loader.for("fr")
    h2 = Hyphenation::Loader.for("fr")
    h1.should be h2
  end

  it "parse les blocs \\hyphenation comme exceptions" do
    content = <<-TEX
      \\patterns{
      1ba
      }
      \\hyphenation{
      as-so-ciate
      ex-cep-tion
      }
      TEX
    hyph = Hyphenation::Loader.parse(content)
    hyph.exceptions["associate"].should eq [2, 4]
    hyph.exceptions["exception"].should eq [2, 5]
  end

  it "parse les patterns multi-lignes" do
    content = <<-TEX
      \\patterns{
      1ba
      ab2c
      }
      TEX
    hyph = Hyphenation::Loader.parse(content)
    hyph.trie.root.children['b'].try &.children['a'].try &.values.should eq [1, 0, 0]
    hyph.trie.root.children['a'].try &.children['b'].try &.children['c'].try &.values.should eq [0, 0, 2, 0]
  end

  it "ignore les commentaires LaTeX" do
    content = <<-TEX
      % This is a comment
      \\patterns{
      1ba % inline comment
      }
      TEX
    hyph = Hyphenation::Loader.parse(content)
    hyph.trie.root.children['b'].try &.children['a'].try &.values.should eq [1, 0, 0]
  end
end
