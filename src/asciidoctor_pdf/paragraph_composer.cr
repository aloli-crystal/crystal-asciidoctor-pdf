require "./inline_renderer"

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
    # Compatible bug-pour-bug avec l'ancien `wrap_segments` :
    # entre deux segments contigus dont le dernier émis est une
    # Box, un Glue artificiel est inséré (cas
    # `<strong>foo</strong>bar` → `foo bar` avec espace).
    def self.tokenize(
      segments : Array(InlineSegment),
      font_size : Float64,
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

        # Mesure space_w dans la police du segment courant.
        # On capture un seul yield pour éviter des appels répétés.
        space_w = yield seg, " "
        glue_stretch = space_w * DEFAULT_STRETCH_RATIO
        glue_shrink = space_w * DEFAULT_SHRINK_RATIO

        # Split sur ESPACE ASCII strict : la NBSP (U+00A0) reste
        # incluse dans le morceau précédent ou suivant, ce qui la
        # rend de facto insécable côté composition.
        words = seg.text.split(' ')
        words.each_with_index do |word, idx|
          # Mots vides (double-espace, trailing space) : on les
          # ignore. Le pipeline en amont (inline_renderer ligne
          # 70) normalise les runs de whitespace, ce cas est donc
          # rare en pratique.
          next if word.empty?

          # Glue à insérer si : (a) on est pas le 1er mot du
          # segment, OU (b) on est le 1er mot mais le dernier
          # token émis est une Box (frontière inter-segments sans
          # espace : cas `<strong>foo</strong>bar`).
          last = tokens.last?
          needs_glue = idx > 0 || last.is_a?(Box)
          if needs_glue
            tokens << Glue.new(space_w, glue_stretch, glue_shrink)
          end

          word_w = yield seg, word
          word_seg = InlineSegment.new(
            text: word,
            bold: seg.bold,
            italic: seg.italic,
            mono: seg.mono,
            sup: seg.sup,
            sub: seg.sub,
            mark: seg.mark,
            kbd: seg.kbd,
            button: seg.button,
            menu: seg.menu,
            color: seg.color,
            link: seg.link,
            image_path: seg.image_path,
            image_width: seg.image_width,
            image_height: seg.image_height,
            line_break: false,
          )
          tokens << Box.new(word_w, word_seg)
        end
      end

      tokens
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
