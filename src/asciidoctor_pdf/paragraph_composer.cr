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

    # Caractères qui « collent » au mot précédent et ne doivent
    # PAS être séparés par un Glue artificiel lors d'une frontière
    # inter-segments. Liste : ponctuation de fin (`.,;:!?)]}»`),
    # apostrophe française (`l'arborescence`), NBSP (U+00A0,
    # cf. typographie française `deploy<NBSP>:`). Pour TOUS les
    # autres premiers caractères (lettres, chiffres, ouvrants
    # `([{«`, etc.), un Glue est inséré entre 2 Box de segments
    # contigus — cas typique : `*avant*` suivi de `<a>deploy</a>`
    # en HTML où le parser asciidoctor ne préserve pas l'espace
    # inter-balises (constaté 2026-06-04 sur le README beryl).
    CLINGING_CHARS = ".,;:!?)]}»'  "

    # Caractères « charnières » des codespans inline (segments
    # `mono`) qui autorisent une coupure douce : `/`, `-`, `=`,
    # `,`. Sont insérées des Penalty non-flagged à coût élevé
    # (`CODESPAN_BREAK_COST`) après chaque occurrence — coût
    # élevé pour décourager la coupure si une autre est possible,
    # mais non infini pour permettre la coupure d'une longue
    # commande type `beryl scan aloli/9783... --provider=…`
    # plutôt que de la laisser déborder de la marge.
    CODESPAN_HINGE_CHARS = "/-=,"
    CODESPAN_BREAK_COST  = 200.0

    # Découpe un word de codespan APRÈS chaque caractère charnière.
    # Le caractère charnière reste collé au fragment qui le contient
    # (à gauche, donc le fragment qui le précédait dans le source).
    # Ex : `aloli/abc-def` → `["aloli/", "abc-", "def"]`.
    private def self.split_at_codespan_hinges(word : String) : Array(String)
      result = [] of String
      start = 0
      word.each_char_with_index do |c, idx|
        if CODESPAN_HINGE_CHARS.includes?(c)
          result << word[start..idx]
          start = idx + 1
        end
      end
      result << word[start..] if start < word.size
      result
    end

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
      &measure : InlineSegment, String -> Float64
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
        # police du segment courant. Le bloc est capturé en Proc
        # nommé `measure` (signature `&measure : ...`), ce qui
        # permet de le passer à `tokenize_segment_with_cjk` —
        # Crystal interdit `yield` dans un Proc literal ou un
        # bloc forwardé.
        space_w = measure.call(seg, " ")
        hyphen_w = hyphenator ? measure.call(seg, "-") : 0.0
        glue_stretch = space_w * DEFAULT_STRETCH_RATIO
        glue_shrink = space_w * DEFAULT_SHRINK_RATIO

        # Détection CJK : si le segment contient au moins un
        # caractère dans la plage CJK (≥ U+3000), on délègue à
        # un tokenizer dédié qui split CHAQUE char CJK en Box
        # autonome, avec une Glue mince (largeur 0 + stretch
        # positif) entre 2 chars CJK consécutifs. Ces Glues
        # mince servent à la fois de point de coupure légal
        # (les paragraphes CJK n'ont pas d'espace ASCII pour
        # servir de breakpoint naturel) et de support pour
        # l'étirement Knuth-Plass / Tc lors de la justification.
        if seg.text.each_char.any? { |c| c.ord >= 0x3000 }
          tokenize_segment_with_cjk(seg, tokens, space_w, glue_stretch, glue_shrink, &measure)
          next
        end

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
          # Insertion de Glue :
          # - Si `idx > 0` : on est entre 2 mots du même segment
          #   séparés par un espace ASCII → toujours Glue (avec
          #   dédup contre Glue déjà émise pour le cas trailing
          #   space + leading space d'un segment suivant).
          # - Si `idx == 0` et `word` non vide et le dernier token
          #   est une Box (frontière inter-segments) : on insère
          #   un Glue SAUF si le 1er caractère du mot est
          #   « collant » au mot précédent — la liste collante
          #   couvre la ponctuation de fin (`.,;:!?)]}»`),
          #   l'apostrophe française (`'`, dans `l'arborescence`),
          #   et la NBSP (U+00A0, pour `<strong>deploy</strong>` +
          #   `<NBSP>:` qui doit rester collé conformément à la
          #   convention typographique française). Sans NBSP dans
          #   la liste, on aurait un double-espace
          #   `deploy NBSP :` au lieu de `deploy<NBSP>:`.
          if idx > 0 && !tokens.last?.is_a?(Glue)
            tokens << Glue.new(space_w, glue_stretch, glue_shrink)
          elsif idx == 0 && !word.empty? && tokens.last?.is_a?(Box) && !CLINGING_CHARS.includes?(word[0])
            tokens << Glue.new(space_w, glue_stretch, glue_shrink)
          end

          # Mot vide (trailing space `foo ` ou segment
          # whitespace-only ` `) : la Glue éventuelle est déjà
          # émise ci-dessus, pas de Box à produire.
          next if word.empty?

          # Tentative de césure Liang. PAS pour les segments
          # mono (codespan) : un identifiant `beryl` ne doit
          # JAMAIS être césuré en `be-ryl` car le tiret
          # changerait son sens (`beryl` ≠ `be-ryl`). Pour les
          # codespans longs qui dépassent la marge, on utilise
          # la coupure douce sur les caractères charnières
          # (cf. `split_at_codespan_hinges` ci-dessus) qui ne
          # pose PAS de tiret.
          positions = if hyphenator && !seg.mono
                        try_hyphenate(word, hyphenator)
                      else
                        [] of Int32
                      end

          # Coupure douce pour les codespans inline : pour les
          # segments `mono`, on splitte le mot aux caractères
          # charnières (`/`, `-`, `=`, `,`) et on insère une
          # Penalty non-flagged à coût élevé entre chaque
          # fragment. La Penalty sert de breakpoint potentiel à
          # `compose_first_fit` quand une longue commande inline
          # type `beryl scan aloli/9783... --provider=…` ne tient
          # pas sur une ligne — sans cette coupure douce, le
          # codespan déborderait silencieusement dans la marge.
          if seg.mono && positions.empty?
            codespan_frags = split_at_codespan_hinges(word)
            if codespan_frags.size > 1
              codespan_frags.each_with_index do |frag, i|
                if i > 0
                  tokens << Penalty.new(0.0, CODESPAN_BREAK_COST, false)
                end
                frag_w = measure.call(seg, frag)
                tokens << Box.new(frag_w, clone_segment(seg, frag))
              end
              next
            end
          end

          if positions.empty?
            word_w = measure.call(seg, word)
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
              frag_w = measure.call(seg, frag)
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

    # Tokenize un segment dont le texte contient au moins un
    # caractère CJK (≥ U+3000). Stratégie :
    #
    # - Run latin courant accumulé dans un buffer ; à chaque char
    #   CJK rencontré, le buffer est flushé (= tokenisé comme du
    #   standard : split par espace ASCII, Box + Glue).
    # - Chaque char CJK devient une Box autonome (texte = char).
    #   Entre deux Box CJK consécutives, on émet une Glue mince :
    #   `width = 0`, `stretch = char_w × 0.5` (la convention typo
    #   CJK accepte des étirements jusqu'à ~75 %, donc 50 % de
    #   stretch nominal laisse de la marge confortable), `shrink
    #   = 0` (pas de compression entre glyphes CJK). Cette Glue
    #   sert deux usages :
    #
    #   . **Point de coupure légal** : `compose_knuth_plass` peut
    #     casser la ligne ici (avant J4 / chantier 1, les
    #     paragraphes CJK longs restaient sur une seule ligne car
    #     le composer ne trouvait aucun breakpoint).
    #   . **Support d'étirement** : Knuth-Plass étire ces Glues
    #     en proportion de l'`adjustment_ratio` global de la ligne ;
    #     `render_segment_line` retrouve la même valeur via le Tc
    #     calculé à partir de `natural_w` et `n_cjk`.
    #
    # PAS de Glue entre un char CJK et un char latin adjacent : la
    # convention sino-japonaise écrit `日本2026年` collé, et casser
    # entre `本` et `2` poserait des problèmes de lecture.
    private def self.tokenize_segment_with_cjk(
      seg : InlineSegment,
      tokens : Array(Token),
      space_w : Float64,
      glue_stretch : Float64,
      glue_shrink : Float64,
      &measure : InlineSegment, String -> Float64
    )
      # `Array(Char)` plutôt que `String::Builder` : ce dernier
      # interdit les `.to_s` répétés (« Can only invoke 'to_s'
      # once on String::Builder »), or `flush_latin` est appelé
      # plusieurs fois sur le même buffer dans un même paragraphe
      # (à chaque transition latin → CJK).
      latin_buf = [] of Char
      prev_was_cjk = false

      # `flush_latin` est une closure : elle capture
      # `latin_buf`, `tokens`, `prev_was_cjk` et `measure` (le
      # bloc Proc-ified). On ne peut PAS faire `yield` dans un
      # Proc en Crystal — d'où la signature `&measure : ...` qui
      # capture le bloc en Proc nommé et permet `measure.call`.
      flush_latin = -> {
        unless latin_buf.empty?
          str = latin_buf.join
          latin_buf.clear
          parts = str.split(' ')
          parts.each_with_index do |part, idx|
            if idx > 0 && !tokens.last?.is_a?(Glue)
              tokens << Glue.new(space_w, glue_stretch, glue_shrink)
            end
            next if part.empty?
            word_w = measure.call(seg, part)
            tokens << Box.new(word_w, clone_segment(seg, part))
          end
          prev_was_cjk = false
        end
        nil
      }

      seg.text.each_char do |c|
        if c.ord >= 0x3000
          flush_latin.call
          char_str = c.to_s
          char_w = measure.call(seg, char_str)
          # Glue mince ENTRE 2 chars CJK consécutifs (jamais avant
          # le premier, ni après un run latin — auquel cas on
          # joint sans espace, cf. `日本2026年`).
          if prev_was_cjk
            tokens << Glue.new(0.0, char_w * 0.5, 0.0)
          end
          tokens << Box.new(char_w, clone_segment(seg, char_str))
          prev_was_cjk = true
        else
          latin_buf << c
        end
      end
      flush_latin.call
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
            lines << finalize_line(current, target_w, false, 0.0)
            current = [] of Token
            current_width = 0.0
          else
            # Penalty intermédiaire (césure flagged ou hint
            # de coupure douce) : enregistrée dans `current`
            # pour servir de breakpoint potentiel si une Box
            # suivante fait dépasser `target_w`. Sa `width` ne
            # contribue PAS à `current_width` tant qu'on ne
            # casse pas dessus.
            current << tok
          end
        when Box
          # Si la Box ferait dépasser et qu'on a déjà du contenu :
          # casser la ligne au meilleur breakpoint disponible.
          # Priorité (du plus à droite vers le plus à gauche) :
          # une Penalty flagged dans le dernier mot (= césure
          # Liang) > la dernière Glue (= cassure inter-mots
          # standard).
          if current_width + tok.width > target_w && !current.empty?
            # Cherche le breakpoint le plus à droite. Trois types
            # acceptés (par ordre d'apparition dans le source) :
            # - Glue : cassure inter-mots standard
            # - Penalty flagged (cost = 50) : césure Liang. Pose
            #   un tiret au dernier segment de la ligne.
            # - Penalty non-flagged (cost = 200) : coupure douce
            #   codespan. Casse sans tiret. Coût élevé pour
            #   décourager les coupures inutiles, mais non infini
            #   pour permettre la coupure d'une longue commande.
            break_idx = -1
            is_hyphen = false
            j = current.size - 1
            while j >= 0
              ct = current[j]
              if ct.is_a?(Penalty)
                if ct.cost < INFINITY
                  break_idx = j
                  is_hyphen = ct.flagged
                  break
                end
                # Penalty interdite (cost = INFINITY) : skip.
              elsif ct.is_a?(Glue)
                break_idx = j
                is_hyphen = false
                break
              end
              j -= 1
            end

            if break_idx >= 0
              hyphen_w = is_hyphen ? current[break_idx].as(Penalty).width : 0.0
              line_tokens = current[0..break_idx - 1]
              rest_tokens = current[(break_idx + 1)..]
              lines << finalize_line(line_tokens, target_w, is_hyphen, hyphen_w)
              current = rest_tokens.to_a
            else
              # Pas de breakpoint trouvé : force-break à plat
              # (mot unique qui dépasse seul la largeur cible).
              lines << finalize_line(current, target_w, false, 0.0)
              current = [] of Token
            end

            current_width = 0.0
            current.each do |t|
              current_width += t.width unless t.is_a?(Penalty)
            end
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

      lines << finalize_line(current, target_w, false, 0.0) unless current.empty?
      lines
    end

    # Algorithme **Knuth-Plass** de composition de paragraphe.
    #
    # Référence : Donald E. Knuth et Michael F. Plass,
    # *Breaking Paragraphs into Lines*, Software Practice &
    # Experience, vol. 11, p. 1119-1184, 1981. (Reproduit en
    # annexe du TeXbook, chapitre 14.)
    #
    # Principe : modélise le paragraphe comme un graphe orienté
    # où les nœuds sont les breakpoints légaux (Glue après Box,
    # Penalty non-infinie, fin du paragraphe) et les arcs sont
    # les lignes possibles. Le coût d'un arc (= « demerits »)
    # est une fonction quadratique de la « badness » (étirement
    # ou compression nécessaire pour atteindre `target_w`) plus
    # les pénalités locales (césure, double césure consécutive).
    # Programmation dynamique : pour chaque breakpoint B, on
    # mémorise le `total_demerits` minimal accumulé depuis le
    # début, et le breakpoint A qui mène à ce minimum.
    # Backtrace final pour reconstruire la séquence optimale.
    #
    # Avantages par rapport à `compose_first_fit` :
    #
    # - Distribution **globale** des étirements (les lignes ont
    #   des `adjustment_ratio` similaires, plus de paragraphes
    #   « tasse-puis-vide »).
    # - Exploite les `Penalty` de césure quand elles évitent un
    #   étirement extrême (un mot long césure plutôt qu'étirer
    #   tous les espaces).
    # - Évite les *rivers* (alignements verticaux d'espaces
    #   gênants) grâce à l'harmonisation des lignes.
    #
    # Fallback : si aucun chemin admissible n'est trouvé (ex.
    # paragraphe pathologique sans aucun breakpoint), retombe
    # sur `compose_first_fit`.
    def self.compose_knuth_plass(
      tokens : Array(Token),
      target_w : Float64,
    ) : Array(Line)
      return [] of Line if tokens.empty?

      n = tokens.size

      # Précalcul des largeurs / stretch / shrink cumulés pour
      # interroger en O(1) la largeur d'une sous-séquence
      # `tokens[a...b]` : `widths[b] - widths[a]`.
      widths = Array.new(n + 1, 0.0)
      stretches = Array.new(n + 1, 0.0)
      shrinks = Array.new(n + 1, 0.0)
      tokens.each_with_index do |t, i|
        widths[i + 1] = widths[i]
        stretches[i + 1] = stretches[i]
        shrinks[i + 1] = shrinks[i]
        case t
        when Box
          widths[i + 1] += t.width
        when Glue
          widths[i + 1] += t.width
          stretches[i + 1] += t.stretch
          shrinks[i + 1] += t.shrink
        when Penalty
          # Pas de contribution naturelle — `width` n'est ajouté
          # qu'aux lignes qui se TERMINENT sur cette Penalty
          # (« si la coupure est prise »).
        end
      end

      # Liste ordonnée des breakpoints candidats :
      #   - `-1` : start virtuel (avant tout token)
      #   - chaque `Glue` qui suit une `Box` (break naturel
      #     entre deux mots)
      #   - chaque `Penalty` avec `cost < INFINITY` (forced si
      #     `cost <= NEG_INFINITY` ; conditionnel sinon)
      #   - `n` : fin virtuelle (forced)
      candidates = [-1]
      tokens.each_with_index do |t, i|
        case t
        when Glue
          candidates << i if i > 0 && tokens[i - 1].is_a?(Box)
        when Penalty
          candidates << i if t.cost < INFINITY
        end
      end
      candidates << n

      # `records[b]` mémorise la meilleure façon d'atteindre le
      # breakpoint `b` : total des demerits accumulés, indice
      # du breakpoint précédent, ratio d'ajustement de la ligne
      # entrante, et flag « cette ligne se termine sur une
      # césure » (pour la pénalité de double césure).
      records = {} of Int32 => NamedTuple(demerits: Float64, prev: Int32, ratio: Float64, flagged: Bool)
      records[-1] = {demerits: 0.0, prev: -2, ratio: 0.0, flagged: false}

      candidates[1..].each do |b|
        best_demerits = Float64::INFINITY
        best_prev = -1
        best_ratio = 0.0
        best_flagged = false

        candidates.each do |a|
          break if a >= b
          next unless (prev_rec = records[a]?)

          # La ligne va de `a + 1` à `b`. On consomme la Glue
          # ou Penalty en position `a` (point de coupure) ;
          # on saute aussi les Glues de tête (lstrip TeX).
          start_idx = a + 1
          while start_idx < b && tokens[start_idx].is_a?(Glue)
            start_idx += 1
          end
          next if start_idx >= b

          line_w = widths[b] - widths[start_idx]
          line_stretch = stretches[b] - stretches[start_idx]
          line_shrink = shrinks[b] - shrinks[start_idx]

          # Si on coupe sur une Penalty à `b`, sa `width` (le
          # tiret de césure si flagged) s'ajoute à la ligne.
          penalty_at_b = b < n && tokens[b].is_a?(Penalty) ? tokens[b].as(Penalty) : nil
          if penalty_at_b
            line_w += penalty_at_b.width
          end

          # Adjustment ratio : positif = étirement, négatif =
          # compression. `Float64::INFINITY` = ligne impossible
          # à étirer suffisamment, on n'avance pas.
          delta = target_w - line_w
          ratio = if delta > 0
                    line_stretch > 0 ? delta / line_stretch : Float64::INFINITY
                  elsif delta < 0
                    line_shrink > 0 ? delta / line_shrink : -Float64::INFINITY
                  else
                    0.0
                  end

          # Seuils TeX par défaut : tolerance = 10 en stretch,
          # -1 en shrink (au-delà = ligne pathologique, on
          # passe au breakpoint suivant).
          next if ratio > 10.0 || ratio < -1.0

          # Badness = 100 · |ratio|³ (formule TeX, TeXbook ch. 12).
          badness = 100.0 * (ratio.abs ** 3)

          # Demerits = (1 + badness)² + pénalité², plus
          # `double_hyphen_demerits = 10000` si césure
          # consécutive (TeX `\doublehyphendemerits`).
          base = 1.0 + badness
          demerits = base * base
          penalty_cost = penalty_at_b ? penalty_at_b.cost : 0.0
          if penalty_cost > 0
            demerits += penalty_cost * penalty_cost
          end
          flagged_b = penalty_at_b ? penalty_at_b.flagged : false
          if flagged_b && prev_rec[:flagged]
            demerits += 10_000.0
          end

          total = prev_rec[:demerits] + demerits
          if total < best_demerits
            best_demerits = total
            best_prev = a
            best_ratio = ratio
            best_flagged = flagged_b
          end
        end

        if best_demerits < Float64::INFINITY
          records[b] = {demerits: best_demerits, prev: best_prev, ratio: best_ratio, flagged: best_flagged}
        end
      end

      # Fallback gracieux si Knuth-Plass n'a pas trouvé de
      # chemin admissible (paragraphe pathologique, mot trop
      # long, target_w trop petit) : retombe sur first-fit qui
      # accepte tout.
      return compose_first_fit(tokens, target_w) unless records.has_key?(n)

      # Backtrace pour reconstruire la séquence de breakpoints.
      path = [] of Int32
      curr = n
      while curr != -1
        path.unshift(curr)
        curr = records[curr][:prev]
      end

      # Construction des Line à partir de la séquence.
      lines = [] of Line
      prev_bp = -1
      path.each do |bp|
        start_idx = prev_bp + 1
        end_idx = bp
        while start_idx < end_idx && tokens[start_idx].is_a?(Glue)
          start_idx += 1
        end

        next if start_idx >= end_idx

        line_tokens = tokens[start_idx...end_idx]
        rec = records[bp]
        ends_on_hyphen = bp < n && rec[:flagged]
        hyphen_w = ends_on_hyphen ? tokens[bp].as(Penalty).width : 0.0

        lines << finalize_kp_line(line_tokens, rec[:ratio], hyphen_w, ends_on_hyphen)

        prev_bp = bp
      end

      # Garde-fou emergency (v2.3.24.82, 2026-06-04) : si la
      # solution K-P optimale globale produit AU MOINS UNE ligne
      # avec un étirement excessif (|ratio| > `MAX_KP_RATIO`),
      # on retombe sur first-fit qui a son propre garde-fou
      # `max_extra_factor` côté renderer (basculement en `left`
      # pour la ligne pathologique). Sans cette protection, K-P
      # accepte des layouts où les mots sont éparpillés sur de
      # larges blancs (régression observée le 2026-06-04 sur le
      # README beryl : « FreeBSD 15 » cassé, lignes très étalées,
      # mots débordant la marge).
      #
      # Seuil empirique 3.0 = stretch de 300 % du nominal. Au
      # delà, on perd la qualité visuelle ; en dessous, K-P reste
      # supérieur à first-fit (lignes équilibrées, moins de
      # rivers, exploitation des Penalty de césure).
      if lines.any? { |l| l.adjustment_ratio.abs > MAX_KP_RATIO }
        return compose_first_fit(tokens, target_w)
      end

      lines
    end

    # Seuil au-delà duquel K-P retombe sur first-fit pour le
    # paragraphe entier (cf. `compose_knuth_plass`). 3.0 ≈ 300 %
    # du stretch nominal.
    MAX_KP_RATIO = 3.0

    # Construit une `Line` Knuth-Plass : comme `finalize_line`
    # (first-fit), plus l'injection du tiret de césure `-` à la
    # fin du dernier segment si la ligne se termine sur une
    # Penalty flagged.
    private def self.finalize_kp_line(
      tokens : Array(Token),
      ratio : Float64,
      hyphen_w : Float64,
      ends_on_hyphen : Bool,
    ) : Line
      segments = [] of InlineSegment
      natural_width = 0.0
      n_spaces = 0
      preceded_by_glue = false

      tokens.each do |tok|
        case tok
        when Glue
          natural_width += tok.width
          # `tok.width > 0` distingue une Glue « espace »
          # (largeur ≈ space_w, séparation entre mots latins)
          # d'une Glue « mince » (largeur 0, jointure entre
          # glyphes CJK). Seules les Glue espace contribuent au
          # comptage `n_spaces` (utilisé par le renderer pour
          # `extra_per_space`) et déclenchent le préfixe « ` ` »
          # sur la Box suivante. Pour les Glue mince CJK, on ne
          # veut PAS de caractère espace entre les glyphes —
          # l'étirement est appliqué via Tc côté renderer.
          if tok.width > 0
            n_spaces += 1
            preceded_by_glue = true
          end
        when Box
          orig = tok.segment
          text = preceded_by_glue ? " " + orig.text : orig.text
          segments << clone_segment(orig, text)
          natural_width += tok.width
          preceded_by_glue = false
        when Penalty
          # Penalties intermédiaires : skip (la ligne ne s'y
          # termine pas, sinon ce serait géré via `ends_on_hyphen`).
        end
      end

      if ends_on_hyphen && !segments.empty?
        last = segments.last
        segments[segments.size - 1] = clone_segment(last, last.text + "-")
        natural_width += hyphen_w
      end

      Line.new(
        segments: segments,
        natural_width: natural_width,
        adjustment_ratio: ratio,
        n_spaces: n_spaces,
      )
    end

    # Finalise une ligne. `ends_on_hyphen = true` indique que la
    # ligne a été cassée sur une Penalty.flagged (césure Liang),
    # auquel cas un tiret `-` est suffixé au texte du dernier
    # segment et `hyphen_w` est ajouté à `natural_width`.
    # Les Penalty intermédiaires non-terminales (issues du
    # tokenize avec hyphenator) sont silencieusement skippées
    # — elles servent juste de marqueurs de breakpoint pour
    # `compose_first_fit`/`compose_knuth_plass`.
    private def self.finalize_line(
      tokens : Array(Token),
      target_w : Float64,
      ends_on_hyphen : Bool,
      hyphen_w : Float64,
    ) : Line
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
          # Voir `finalize_kp_line` : Glue mince CJK
          # (`tok.width == 0`) ne compte ni dans `n_spaces` ni
          # comme déclencheur de préfixe espace devant la Box
          # suivante.
          if tok.width > 0
            n_spaces += 1
            preceded_by_glue = true
          end
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
          # Penalty intermédiaire (césure flagged ou coupure douce
          # codespan) embarquée dans `current` par
          # `compose_first_fit` pour servir de breakpoint
          # potentiel. Pas de contribution à `natural_width` ni
          # aux segments — seule la pose éventuelle du tiret de
          # césure se fait en aval via `ends_on_hyphen`.
        end
      end

      if ends_on_hyphen && !segments.empty?
        last = segments.last
        segments[segments.size - 1] = clone_segment(last, last.text + "-")
        natural_width += hyphen_w
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
