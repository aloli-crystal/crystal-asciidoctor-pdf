module Asciidoctor
  ADMONITION_STYLE_HEADS = Set{'C', 'I', 'N', 'T', 'W'}

  ADMONITION_STYLES = Set{"CAUTION", "IMPORTANT", "NOTE", "TIP", "WARNING"}

  ASCIIDOC_EXTENSIONS = {
    ".ad"       => true,
    ".adoc"     => true,
    ".asc"      => true,
    ".asciidoc" => true,
    ".txt"      => true,
  }

  ATTR_REF_HEAD = '{'

  BACKEND_ALIASES = {
    "docbook" => "docbook5",
    "html"    => "html5",
  }

  BLOCK_MATH_DELIMITERS = {
    "asciimath" => {"\\$", "\\$"},
    "latexmath" => {"\\[", "\\]"},
  }

  CAPTION_ATTRIBUTE_NAMES = {
    "example" => "example-caption",
    "figure"  => "figure-caption",
    "listing" => "listing-caption",
    "table"   => "table-caption",
  }

  DEFAULT_ATTRIBUTES = {
    "sectids"           => "",
    "appendix-caption"  => "Appendix",
    "appendix-refsig"   => "Appendix",
    "caution-caption"   => "Caution",
    "chapter-refsig"    => "Chapter",
    "example-caption"   => "Example",
    "figure-caption"    => "Figure",
    "important-caption" => "Important",
    "last-update-label" => "Last updated",
    "note-caption"      => "Note",
    "part-refsig"       => "Part",
    "prewrap"           => "",
    "section-refsig"    => "Section",
    "table-caption"     => "Table",
    "tip-caption"       => "Tip",
    "toc-placement"     => "auto",
    "toc-title"         => "Table of Contents",
    "untitled-label"    => "Untitled",
    "version-label"     => "Version",
    "warning-caption"   => "Warning",
  }

  USER_HOME = ENV["HOME"]? || "."

  DEFAULT_BACKEND = "html5"

  DEFAULT_DOCTYPE = "article"

  DEFAULT_EXTENSIONS = {
    "asciidoc" => ".adoc",
    "docbook"  => ".xml",
    "epub"     => ".epub",
    "html"     => ".html",
    "manpage"  => ".man",
    "pdf"      => ".pdf",
  }

  DEFAULT_PAGE_WIDTHS = {
    "docbook" => 425,
  }

  DEFAULT_STYLESHEET_NAME = "asciidoctor.css"

  DELIMITED_BLOCKS = {
    "--"   => {:open, Set{"comment", "example", "literal", "listing", "pass", "quote", "sidebar", "source", "verse", "admonition", "abstract", "partintro"}},
    "----" => {:listing, Set{"literal", "source"}},
    "...." => {:literal, Set{"listing", "source"}},
    "====" => {:example, Set{"admonition"}},
    "****" => {:sidebar, Set(String).new},
    "____" => {:quote, Set{"verse"}},
    "++++" => {:pass, Set{"stem", "latexmath", "asciimath"}},
    "|===" => {:table, Set(String).new},
    ",===" => {:table, Set(String).new},
    ":===" => {:table, Set(String).new},
    "!===" => {:table, Set(String).new},
    "~~~~" => {:open, Set{"abstract", "partintro"}},
    "////" => {:comment, Set(String).new},
    "```"  => {:fenced_code, Set(String).new},
  }

  DELIMITED_BLOCK_HEADS = {
    "--" => true, "--" => true, ".." => true, "==" => true,
    "**" => true, "__" => true, "++" => true, "|=" => true,
    ",=" => true, ":=" => true, "!=" => true, "~~" => true,
    "//" => true, "``" => true,
  }

  DELIMITED_BLOCK_TAILS = {
    "----" => "-", "...." => ".", "====" => "=", "****" => "*",
    "____" => "_", "++++" => "+", "|===" => "=", ",===" => "=",
    ":===" => "=", "!===" => "=", "~~~~" => "~", "////" => "/",
  }

  FLEXIBLE_ATTRIBUTES = ["sectnums"]

  HARD_LINE_BREAK = " +"

  HYBRID_LAYOUT_BREAK_CHARS = {
    '\'' => :thematic_break,
    '<'  => :page_break,
    '-'  => :thematic_break,
    '*'  => :thematic_break,
    '_'  => :thematic_break,
  }

  INLINE_MATH_DELIMITERS = {
    "asciimath" => {"\\$", "\\$"},
    "latexmath" => {"\\(", "\\)"},
  }

  INTRINSIC_ATTRIBUTES = {
    "amp"            => "&",
    "apos"           => "&#39;",
    "asterisk"       => "*",
    "backslash"      => "\\",
    "backtick"       => "`",
    "blank"          => "",
    "brvbar"         => "&#166;",
    "caret"          => "^",
    "cpp"            => "C&#43;&#43;",
    "cxx"            => "C&#43;&#43;",
    "deg"            => "&#176;",
    "empty"          => "",
    "endsb"          => "]",
    "gt"             => ">",
    "ldquo"          => "&#8220;",
    "lsquo"          => "&#8216;",
    "lt"             => "<",
    "nbsp"           => "&#160;",
    "plus"           => "&#43;",
    "pp"             => "&#43;&#43;",
    "quot"           => "&#34;",
    "rdquo"          => "&#8221;",
    "rsquo"          => "&#8217;",
    "sp"             => " ",
    "startsb"        => "[",
    "tilde"          => "~",
    "two-colons"     => "::",
    "two-semicolons" => ";;",
    "vbar"           => "|",
    "wj"             => "&#8288;",
    "zwsp"           => "&#8203;",
  }

  LAYOUT_BREAK_CHARS = {
    "'" => :thematic_break,
    "<" => :page_break,
  }

  # The newline character used for output.
  LF = '\n'

  LINE_CONTINUATION        = " \\"
  LINE_CONTINUATION_LEGACY = " +"
  LIST_CONTINUATION        = "+"

  # Maximum integer value for "boundless" operations.
  MAX_INT = 9007199254740991_i64

  MARKDOWN_THEMATIC_BREAK_CHARS = {
    '-' => :thematic_break,
    '*' => :thematic_break,
    '_' => :thematic_break,
  }

  NESTABLE_LIST_CONTEXTS = [:dlist, :olist, :ulist]

  # The null character to use for splitting attribute values.
  NULL = '\0'

  ORDERED_LIST_KEYWORDS = {
    "loweralpha" => "a",
    "lowerroman" => "i",
    "upperalpha" => "A",
    "upperroman" => "I",
  }

  ORDERED_LIST_STYLES = [:arabic, :loweralpha, :lowerroman, :upperalpha, :upperroman]

  PARAGRAPH_STYLES = Set{
    "abstract", "comment", "example", "listing", "literal", "normal", "open",
    "partintro", "pass", "quote", "sidebar", "source", "verse",
  }

  SETEXT_SECTION_LEVELS = {
    '=' => 0,
    '-' => 1,
    '~' => 2,
    '^' => 3,
    '+' => 4,
  }

  STEM_TYPE_ALIASES = {
    "latex"     => "latexmath",
    "latexmath" => "latexmath",
    "tex"       => "latexmath",
  }
  STEM_TYPE_DEFAULT = "asciimath"

  # Tab character.
  TAB = '\t'

  VERBATIM_STYLES = Set{"listing", "literal", "source", "verse"}
end
