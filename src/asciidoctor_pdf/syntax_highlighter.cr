# Coloration syntaxique basique pour les blocs de code AsciiDoc.
# Implémente une tokenisation légère sans dépendance externe,
# inspirée du style "monokai" utilisé par asciidoctor-pdf Ruby.

module AsciidoctorPDF
  # Un token de code coloré
  record CodeToken, text : String, color : String

  # Coloration syntaxique basique pour les langages courants.
  # Retourne une liste de tokens avec leur couleur hexadécimale.
  module SyntaxHighlighter
    # Couleurs du thème "monokai-inspired"
    KEYWORD_COLOR   = "f92672"  # rose/rouge
    STRING_COLOR    = "e6db74"  # jaune
    COMMENT_COLOR   = "75715e"  # gris
    NUMBER_COLOR    = "ae81ff"  # violet
    BUILTIN_COLOR   = "66d9ef"  # cyan
    OPERATOR_COLOR  = "f8f8f2"  # blanc cassé
    DEFAULT_COLOR   = "f8f8f2"  # blanc cassé

    # Mots-clés par langage
    KEYWORDS = {
      "crystal" => %w[
        abstract alias annotation as as? asm begin break case class
        def do else elsif end ensure enum extend false for fun if in
        include instance_sizeof is_a? lib macro module next nil nil?
        of offsetof out pointerof private protected require rescue
        responds_to? return select self sizeof struct super then true
        type typeof uninitialized union unless until verbatim when while with yield
      ],
      "ruby" => %w[
        __ENCODING__ __LINE__ __FILE__ BEGIN END alias and begin break
        case class def defined? do else elsif end ensure false for if
        in module next nil not or redo rescue retry return self super
        then true undef unless until when while yield
      ],
      "python" => %w[
        False None True and as assert async await break class continue
        def del elif else except finally for from global if import in
        is lambda nonlocal not or pass raise return try while with yield
      ],
      "javascript" => %w[
        async await break case catch class const continue debugger default
        delete do else export extends false finally for from function if
        import in instanceof let new null of return static super switch
        this throw true try typeof undefined var void while with yield
      ],
      "typescript" => %w[
        abstract any as async await boolean break case catch class const
        constructor continue declare default delete do else enum export
        extends false finally for from function if implements import in
        instanceof interface is keyof let module namespace never new null
        number object of readonly return static string super switch symbol
        this throw true try type typeof undefined unique unknown var void
        while with yield
      ],
      "go" => %w[
        break case chan const continue default defer else fallthrough for
        func go goto if import interface map package range return select
        struct switch type var
      ],
      "java" => %w[
        abstract assert boolean break byte case catch char class const
        continue default do double else enum extends false final finally
        float for goto if implements import instanceof int interface long
        native new null package private protected public return short
        static strictfp super switch synchronized this throw throws
        transient true try void volatile while
      ],
      "c" => %w[
        auto break case char const continue default do double else enum
        extern float for goto if inline int long register restrict return
        short signed sizeof static struct switch typedef union unsigned
        void volatile while
      ],
      "cpp" => %w[
        alignas alignof and and_eq asm auto bitand bitor bool break case
        catch char char8_t char16_t char32_t class compl concept const
        consteval constexpr constinit const_cast continue co_await
        co_return co_yield decltype default delete do double dynamic_cast
        else enum explicit export extern false float for friend goto if
        inline int long mutable namespace new noexcept not not_eq nullptr
        operator or or_eq private protected public register reinterpret_cast
        requires return short signed sizeof static static_assert
        static_cast struct switch template this thread_local throw true
        try typedef typeid typename union unsigned using virtual void
        volatile wchar_t while xor xor_eq
      ],
      "sh" => %w[
        if then else elif fi for while do done case esac function in
        return break continue exit local declare export readonly
      ],
      "bash" => %w[
        if then else elif fi for while do done case esac function in
        return break continue exit local declare export readonly
      ],
      "sql" => %w[
        SELECT FROM WHERE AND OR NOT INSERT INTO UPDATE DELETE CREATE
        DROP TABLE INDEX VIEW DATABASE ALTER ADD COLUMN PRIMARY KEY
        FOREIGN REFERENCES JOIN LEFT RIGHT INNER OUTER ON GROUP BY
        ORDER HAVING LIMIT OFFSET UNION ALL DISTINCT AS CASE WHEN
        THEN ELSE END NULL IS TRUE FALSE BEGIN COMMIT ROLLBACK
        select from where and or not insert into update delete create
        drop table index view database alter add column primary key
        foreign references join left right inner outer on group by
        order having limit offset union all distinct as case when
        then else end null is true false begin commit rollback
      ],
    }

    # Tokenise une ligne de code pour un langage donné.
    # Retourne un tableau de CodeToken avec texte et couleur.
    def self.tokenize(line : String, language : String) : Array(CodeToken)
      tokens = [] of CodeToken
      lang = language.downcase
      keywords = KEYWORDS[lang]? || [] of String

      # Regex pour les différents types de tokens
      # Ordre important : commentaires > strings > nombres > mots-clés > reste
      pos = 0
      while pos < line.size
        remaining = line[pos..]

        # Commentaire de fin de ligne
        if (m = match_comment(remaining, lang))
          tokens << CodeToken.new(m, COMMENT_COLOR)
          break
        end

        # String entre guillemets doubles ou simples
        if (m = remaining.match(/\A("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/))
          tokens << CodeToken.new(m[1], STRING_COLOR)
          pos += m[1].size
          next
        end

        # Nombre (entier ou flottant)
        if (m = remaining.match(/\A(\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)/))
          tokens << CodeToken.new(m[1], NUMBER_COLOR)
          pos += m[1].size
          next
        end

        # Mot (potentiellement un mot-clé ou builtin)
        if (m = remaining.match(/\A([a-zA-Z_][a-zA-Z0-9_?!]*)/))
          word = m[1]
          color = keywords.includes?(word) ? KEYWORD_COLOR : DEFAULT_COLOR
          tokens << CodeToken.new(word, color)
          pos += word.size
          next
        end

        # Opérateur ou caractère spécial
        tokens << CodeToken.new(remaining[0].to_s, DEFAULT_COLOR)
        pos += 1
      end

      tokens
    end

    # Détecte un commentaire de fin de ligne selon le langage.
    private def self.match_comment(text : String, lang : String) : String?
      case lang
      when "ruby", "python", "crystal", "sh", "bash"
        if (m = text.match(/\A(#.*)/))
          return m[1]
        end
      when "javascript", "typescript", "go", "java", "c", "cpp"
        if (m = text.match(/\A(\/\/.*)/))
          return m[1]
        end
      when "sql"
        if (m = text.match(/\A(--.*)/))
          return m[1]
        end
      end
      nil
    end
  end
end
