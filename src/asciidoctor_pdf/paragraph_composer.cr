require "./inline_renderer"
require "./hyphenation"

module AsciidoctorPDF
  # Moteur de composition de paragraphes inspiré de TeX.
  # Référence : Knuth & Plass, *Breaking Paragraphs into Lines*,
  # Software Practice & Experience, vol. 11, p. 1119-1184, 1981.
  #
  # Le moteur transforme une liste de segments inline en un flux
  # typé de tokens (Box, Glue, Penalty), puis assemble ce flux en
  # lignes via un algorithme de composition.
  #
  # J1 (courant) : `compose_first_fit` reproduit fidèlement
  # l'algorithme greedy historique de TeX, identique au
  # comportement de Prawn et des navigateurs web. La structure
  # Box/Glue/Penalty est introduite *en amont* pour préparer
  # `compose_knuth_plass` (J3) et l'intégration des points de
  # césure Liang (J2). Bénéfice secondaire dès J1 : les espaces
  # insécables (NBSP, U+00A0) sont absorbés dans la Box voisine
  # et ne peuvent plus être des break-points — la règle
  # typographique française (« deploy : il » insécable) est
  # garantie par construction.
  module ParagraphComposer
    # Coût « infini » au sens TeX : un Penalty avec cost = INFINITY
    # interdit la coupure, un Penalty avec cost = NEG_INFINITY la force.
    INFINITY     =  1.0e18
    NEG_INFINITY = -1.0e18

    # Élasticité d'un espace ordinaire (TeXbook, ch. 12).
    # stretch = 1/2 de la largeur d'espace, shrink = 1/3.
    DEFAULT_STRETCH_RATIO = 0.5
    DEFAULT_SHRINK_RATIO  = 1.0 / 3.0

    # Largeur fixe non-cassable : un mot, un groupe de mots reliés
    # par NBSP, ou une image inline. `segment` est l'`InlineSegment`
    # à dessiner (les attributs de style sont préservés).
    record Box,
      width : Float64,
      segment : InlineSegment

    # Espace élastique : break-point légal entre deux Box.
    # En `compose_first_fit`, seul `width` est utilisé. `stretch`
    # et `shrink` seront consommés par `compose_knuth_plass` (J3)
    # pour calculer l'`adjustment_ratio` optimal du paragraphe.
    record Glue,
      width : Float64,
      stretch : Float64,
      shrink : Float64

    # Point de coupure avec coût.
    # `cost <= NEG_INFINITY` : coupure forcée (`<br>` HTML).
    # `cost >= INFINITY`     : coupure interdite (réservé J3).
    # `cost` intermédiaire   : coupure conditionnelle (césure, J2).
    # `width` : largeur insérée *si* la coupure est prise (typique :
    # largeur du tiret de césure).
    # `flagged` : true pour césure (TeX évite deux flagged
    # consécutives via `double_hyphen_demerits`).
    record Penalty,
      width : Float64,
      cost : Float64,
      flagged : Bool = false

    # Union typée : un Token est forcément l'un des trois.
    alias Token = Box | Glue | Penalty

    # Une ligne composée, prête à dessiner.
    # `adjustment_ratio` est calculé pour cette ligne :
    #   = (target_w - natural_width) / total_stretch  si étirement
    #   = (target_w - natural_width) / total_shrink   si compression
    # En J1 le renderer recalcule lui-même `extra_per_space` pour
    # préserver son garde-fou `max_extra_factor` (cf. converter.cr).
    # À partir de J3 c'est `adjustment_ratio` qui pilotera
    # directement l'opérateur PDF `Tw` (ISO 32000-1 § 9.3.3).
    record Line,
      segments : Array(InlineSegment),
      natural_width : Float64,
      adjustment_ratio : Float64,
      n_spaces : Int32

    # Transforme une liste de segments inline en flux de tokens.
    #
    # Règles :
    #
    # - `line_break: true` → `Penalty(0, NEG_INFINITY)`
    # - `image_path` présent → `Box(image_width + 2.0, seg)`
    #   (le +2.0 reproduit le padding inter-élément de
    #   `wrap_segments`)
    # - texte normal → split sur ESPACE ASCII strict. Chaque
    #   morceau (qui peut contenir des NBSP U+00A0) devient une
    #   Box. Entre deux Box du même segment, on émet un Glue.
    #   Les NBSP ne sont JAMAIS un break-point — elles restent
    #   dans la Box voisine, garantissant l'insécabilité.
    #
    # Le bloc reçoit `(segment, text)` et doit retourner la
    # largeur de ce texte dans la police de ce segment, en
    # points PDF.
    #
    # Le paramètre optionnel `hyphenator` active la césure
    # Liang (J2) : chaque mot dont le cœur alphabétique fait
    # au moins `LEFT_MIN + RIGHT_MIN` lettres est fragmenté en
    # sous-Box reliées par `Penalty` (cost = 50, flagged = true,
    # width = largeur du tiret). En `compose_first_fit` (J1) ces
    # Penalty sont ignorées (rendu identique au mot monolithique) ;
    # elles seront consommées par `compose_knuth_plass` (J3).
    def self.tokenize(
      segments : Array(InlineSegment),
      font_size : Float64,
      hyphenator : Hyphenation::Hyphenator? = nil,
      & : InlineSegment, String -> Float64
    ) : Array(Token)
      tokens = [] of Token

      segments.each do |seg|
        if seg.line_break
          tokens << Penalty.new(0.0, NEG_INFINITY, false)
          next
        end

        if seg.image_path
          img_w = (seg.image_width || (font_size * 1.2)) + 2.0
          tokens << Box.new(img_w, seg)
          next
        end

        # Mesure space_w (et hyphen_w si césure activée) dans la
        # police du segment courant. On capture un yield par
        # caractère pour éviter des appels répétés.
        space_w = yield seg, " "
        hyphen_w = hyphenator ? (yield seg, "-") : 0.0
        glue_stretch = space_w * DEFAULT_STRETCH_RATIO
        glue_shrink = space_w * DEFAULT_SHRINK_RATIO

        # Split sur ESPACE ASCII strict : la NBSP (U+00A0) reste
        # incluse dans le morceau précédent ou suivant, ce qui la
        # rend de facto insécable côté composition.
        words = seg.text.split(' ')
        words.each_with_index do |word, idx|
          # `idx > 0` = un espace ASCII séparait ce mot du
          # précédent dans le texte de ce segment. On émet une
          # Glue, avec déduplication contre une Glue déjà émise
          # (cas multi-espaces ou segments whitespace-only
          # consécutifs — rare en pratique post-normalisation).
          #
          # IMPORTANT : on n'émet JAMAIS de Glue artificielle
          # entre deux segments contigus sans espace dans leur
          # texte. Si l'auteur a écrit `<strong>foo</strong>bar`,
          # le rendu doit être `foobar`. Idem pour `code` suivi
          # de `)` sans espace : on ne doit pas séparer la
          # parenthèse fermante du code (le `(ex : ` `code` `)`
          # devient `(ex : code)`, pas `(ex : code )`).
          if idx > 0 && !tokens.last?.is_a?(Glue)
            tokens << Glue.new(space_w, glue_stretch, glue_shrink)
          end

          # Mot vide (trailing space `foo ` ou segment
          # whitespace-only ` `) : la Glue éventuelle est déjà
          # émise ci-dessus, pas de Box à produire.
          next if word.empty?

          # Tentative de césure (J2 : structure typée seulement —
          # les Penalty intermédiaires sont ignorées par
          # `compose_first_fit` ; elles seront consommées par
          # `compose_knuth_plass` à J3 pour distribuer
          # globalement les coupures de paragraphe).
          positions = if hyphenator
                        try_hyphenate(word, hyphenator)
                      else
                        [] of Int32
                      end

          if positions.empty?
            word_w = yield seg, word
            tokens << Box.new(word_w, clone_segment(seg, word))
          else
            # Fragmenter le mot. La ponctuation de tête / queue
            # reste collée à la 1re / dernière syllabe (calculée
            # par `try_hyphenate` qui retourne des positions
            # dans le mot complet, ponctuation incluse).
            fragments = [] of String
            prev = 0
            positions.each do |p|
              fragments << word[prev...p]
              prev = p
            end
            fragments << word[prev..]

            fragments.each_with_index do |frag, i|
              frag_w = yield seg, frag
              tokens << Box.new(frag_w, clone_segment(seg, frag))
              # Penalty de césure entre deux syllabes : si la
              # coupure est prise, on ajoute un tiret (largeur
              # `hyphen_w`). Le coût `50` est la valeur TeX par
              # défaut (`\hyphenpenalty`). `flagged: true` signale
              # une césure pour les `double_hyphen_demerits` de
              # Knuth-Plass (J3).
              if i < fragments.size - 1
                tokens << Penalty.new(hyphen_w, 50.0, true)
              end
            end
          end
        end
      end

      tokens
    end

    # Détecte le cœur alphabétique du mot (en enlevant la
    # ponctuation de tête et de queue, ex. `(typo).` → cœur
    # `typo` aux indices 1..4), appelle l'hyphenator dessus, et
    # remappe les positions retournées vers les indices dans le
    # mot complet (préfixe ponctuation inclus).
    private def self.try_hyphenate(
      word : String,
      hyphenator : Hyphenation::Hyphenator,
    ) : Array(Int32)
      chars = word.chars
      start = 0
      while start < chars.size && !chars[start].letter?
        start += 1
      end
      finish = chars.size
      while finish > start && !chars[finish - 1].letter?
        finish -= 1
      end
      core_size = finish - start
      return [] of Int32 if core_size < Hyphenation::LEFT_MIN + Hyphenation::RIGHT_MIN

      # Le cœur doit être purement alphabétique (apostrophes,
      # tirets internes : pas de césure pour rester simple).
      (start...finish).each do |i|
        return [] of Int32 unless chars[i].letter?
      end

      core = chars[start...finish].join
      positions = hyphenator.hyphenate(core)
      # Remap vers les indices du mot complet : préfixe `start`
      # caractères avant le cœur.
      positions.map { |p| p + start }
    end

    private def self.clone_segment(source : InlineSegment, text : String) : InlineSegment
      InlineSegment.new(
        text: text,
        bold: source.bold,
        italic: source.italic,
        mono: source.mono,
        sup: source.sup,
        sub: source.sub,
        mark: source.mark,
        kbd: source.kbd,
        button: source.button,
        menu: source.menu,
        color: source.color,
        link: source.link,
        image_path: source.image_path,
        image_width: source.image_width,
        image_height: source.image_height,
        line_break: false,
      )
    end

    # First-fit greedy : place chaque Box dans la ligne courante
    # tant que sa largeur cumulée ne dépasse pas `target_w`.
    # À la 1ère Box qui ferait dépasser, on casse la ligne en
    # consommant le Glue trailing s'il est présent (= comportement
    # standard du wrap historique).
    #
    # `Penalty` avec `cost <= NEG_INFINITY` force la coupure.
    # `Penalty` intermédiaire (césure conditionnelle) est ignoré
    # en J1 ; `compose_knuth_plass` (J3) les exploitera.
    def self.compose_first_fit(
      tokens : Array(Token),
      target_w : Float64,
    ) : Array(Line)
      lines = [] of Line
      current = [] of Token
      current_width = 0.0

      tokens.each do |tok|
        case tok
        when Penalty
          if tok.cost <= NEG_INFINITY
            lines << finalize_line(current, target_w)
            current = [] of Token
            current_width = 0.0
          end
          # Penalty intermédiaire : ignoré en J1.
        when Box
          # Si la Box ferait dépasser et qu'on a déjà du contenu :
          # casser la ligne, en consommant le Glue trailing.
          if current_width + tok.width > target_w && !current.empty?
            if (last = current.last?) && last.is_a?(Glue)
              current_width -= last.width
              current.pop
            end
            lines << finalize_line(current, target_w)
            current = [] of Token
            current_width = 0.0
          end
          current << tok
          current_width += tok.width
        when Glue
          # Glue en tête de ligne ignoré (= `lstrip` de l'ancien
          # `wrap_segments` qui supprimait le `\n` après `<br>`).
          next unless current.any?(Box)
          current << tok
          current_width += tok.width
        end
      end

      lines << finalize_line(current, target_w) unless current.empty?
      lines
    end

    private def self.finalize_line(tokens : Array(Token), target_w : Float64) : Line
      segments = [] of InlineSegment
      natural_width = 0.0
      total_stretch = 0.0
      n_spaces = 0
      preceded_by_glue = false

      tokens.each do |tok|
        case tok
        when Glue
          natural_width += tok.width
          total_stretch += tok.stretch
          n_spaces += 1
          preceded_by_glue = true
        when Box
          orig = tok.segment
          text = preceded_by_glue ? " " + orig.text : orig.text
          segments << InlineSegment.new(
            text: text,
            bold: orig.bold,
            italic: orig.italic,
            mono: orig.mono,
            sup: orig.sup,
            sub: orig.sub,
            mark: orig.mark,
            kbd: orig.kbd,
            button: orig.button,
            menu: orig.menu,
            color: orig.color,
            link: orig.link,
            image_path: orig.image_path,
            image_width: orig.image_width,
            image_height: orig.image_height,
            line_break: false,
          )
          natural_width += tok.width
          preceded_by_glue = false
        when Penalty
          # Pas attendu dans une ligne finalisée en J1 — skip.
        end
      end

      adj = if n_spaces > 0 && total_stretch > 0 && target_w > natural_width
              (target_w - natural_width) / total_stretch
            else
              0.0
            end

      Line.new(
        segments: segments,
        natural_width: natural_width,
        adjustment_ratio: adj,
        n_spaces: n_spaces,
      )
    end
  end
end
