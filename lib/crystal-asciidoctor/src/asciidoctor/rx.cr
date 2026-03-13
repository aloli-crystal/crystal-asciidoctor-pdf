module Asciidoctor
  # Character class constants for regex patterns.
  # Crystal uses PCRE (libpcre) with Unicode support.
  # Ruby's \p{Word} maps to PCRE's \p{Xwd}, \p{Alpha} to \p{L},
  # \p{Alnum} to \p{Xan}, \p{Blank} to [\p{Zs}\t].

  # --------------------------------------------------------------------------
  # Document header
  # --------------------------------------------------------------------------

  # Matches the author info line immediately following the document title.
  AuthorInfoLineRx = /^(\p{Xwd}[\p{Xwd}\-'.]*)(?: +(\p{Xwd}[\p{Xwd}\-'.]*))?(?: +(\p{Xwd}[\p{Xwd}\-'.]*))?(?: +<([^>]+)>)?$/

  # Matches the delimiter that separates multiple authors.
  AuthorDelimiterRx = /;(?: |$)/

  # Matches the revision info line.
  RevisionInfoLineRx = /^(?:[^\d{]*(.*?),)? *(?!:)(.*?)(?: *(?!^),?: *(.*))?$/

  # Matches the title and volnum in the manpage doctype.
  ManpageTitleVolnumRx = /^(.+?) *\( *(.+?) *\)$/

  # Matches the name and purpose in the manpage doctype.
  ManpageNamePurposeRx = /^(.+?) +- +(.+)$/

  # --------------------------------------------------------------------------
  # Preprocessor directives
  # --------------------------------------------------------------------------

  # Matches a conditional preprocessor directive (ifdef, ifndef, ifeval, endif).
  ConditionalDirectiveRx = /^(\\)?(ifdef|ifndef|ifeval|endif)::(\S*?(?:([,+])\S*?)?)\[(.+)?\]$/

  # Matches a restricted eval expression.
  EvalExpressionRx = /^(.+?) *([=!><]=|[><]) *(.+)$/

  # Matches an include preprocessor directive.
  IncludeDirectiveRx = /^(\\)?include::([^\s\[](?:[^\[]*[^\s\[])?)\[(.+)?\]$/

  # Matches a trailing tag directive in an include file.
  TagDirectiveRx = /\b(?:tag|(e)nd)::(\S+?)\[\](?=$|[ \r])/m

  # --------------------------------------------------------------------------
  # Attribute entries and references
  # --------------------------------------------------------------------------

  # Matches a document attribute entry.
  AttributeEntryRx = /^:(!?\p{Xwd}[^:]*):(?:[ \t]+(.*))?$/

  # Matches invalid characters in an attribute name.
  InvalidAttributeNameCharsRx = /[^\p{Xwd}-]/

  # Matches a pass inline macro surrounding an attribute entry value.
  AttributeEntryPassMacroRx = /\Apass:([a-z]+(?:,[a-z-]+)*)?\[(.*)\]\z/m

  # Matches an inline attribute reference.
  AttributeReferenceRx = /(\\)?\{(\p{Xwd}[\p{Xwd}-]*|(set|counter2?):.+?)(\\)?\}/

  # --------------------------------------------------------------------------
  # Paragraphs and delimited blocks
  # --------------------------------------------------------------------------

  # Matches an anchor on a line above a block.
  BlockAnchorRx = /^\[\[(\p{L}[\p{Xwd}\-:.]*)(?:, *(.+))?\]\]$/

  # Matches an attribute list above a block element.
  BlockAttributeListRx = /^\[(|[\p{Xwd}.#%{,"'].*)?\]$/

  # Combined pattern that matches either a block anchor or a block attribute list.
  BlockAttributeLineRx = /^\[(?:|[\p{Xwd}.#%{,"'].*|\[(?:|\p{L}[\p{Xwd}\-:.]*(?:, *.+)?)\])\]$/

  # Matches a title above a block.
  BlockTitleRx = /^\.(\.?[^ \t.].*)$/

  # Matches an admonition label at the start of a paragraph.
  AdmonitionParagraphRx = /^(NOTE|TIP|IMPORTANT|WARNING|CAUTION):[ \t]+/

  # Matches a literal paragraph (preceded by at least one space).
  LiteralParagraphRx = /^([ \t]+.*)$/

  # --------------------------------------------------------------------------
  # Section titles
  # --------------------------------------------------------------------------

  # Matches an Atx (single-line) section title.
  AtxSectionTitleRx = /^(=={0,5})[ \t]+(.+?)(?:[ \t]+\1)?$/

  # Matches an extended Atx section title (includes Markdown variant).
  ExtAtxSectionTitleRx = /^(=={0,5}|#\#{0,5})[ \t]+(.+?)(?:[ \t]+\1)?$/

  # Matches the title only (first line) of a Setext (two-line) section title.
  SetextSectionTitleRx = /^((?!\.).*?\p{Xan}.*?)$/

  # Matches an anchor inside a section title.
  InlineSectionAnchorRx = / (\\)?\[\[(\p{L}[\p{Xwd}\-:.]*)(?:, *(.+))?\]\]$/

  # Matches invalid ID characters in a section title.
  InvalidSectionIdCharsRx = /<[^>]+>|&(?:[a-z][a-z]+\d{0,2}|#\d\d\d{0,4}|#x[\da-f][\da-f][\da-f]{0,3});|[^ \p{Xwd}\-.]+?/

  # Matches an explicit section level style like sect1.
  SectionLevelStyleRx = /^sect\d$/

  # --------------------------------------------------------------------------
  # Lists
  # --------------------------------------------------------------------------

  # Detects the start of any list item.
 AnyListRx = /^(?:[ \t]*(?:-|\*\**|\.\..*|\x{2022}|\d+\.|[a-zA-Z]\.|[IVXivx]+\))[ \t]|(?!\/\/[^\/])[ \t]*[^ \t].*?(?::::{0,2}|;;)(?:$|[ \t])|<(?:\d+|\.)>[ \t])/

  # Matches an unordered list item.
  UnorderedListRx = /^[ \t]*(-|\*\**|\x{2022})[ \t]+(.*)$/

  # Matches an ordered list item.
  OrderedListRx = /^[ \t]*(\.\.*|\d+\.|[a-zA-Z]\.|[IVXivx]+\))[ \t]+(.*)$/

  # Matches a description list entry.
  DescriptionListRx = /^(?!\/\/[^\/])[ \t]*([^ \t].*?[^:]|[^ \t:])(:::{0,2}|;;)(?:$|[ \t]+(.*)$)/

  # Matches a sibling description list item (keyed by delimiter).
  DESCRIPTION_LIST_SIBLING_RX = {
    "::"   => /^(?!\/\/[^\/])[ \t]*([^ \t].*?[^:]|[^ \t:])(::)(?:$|[ \t]+(.*)$)/,
    ":::"  => /^(?!\/\/[^\/])[ \t]*([^ \t].*?[^:]|[^ \t:])(:::)(?:$|[ \t]+(.*)$)/,
    "::::" => /^(?!\/\/[^\/])[ \t]*([^ \t].*?[^:]|[^ \t:])(::::)(?:$|[ \t]+(.*)$)/,
    ";;"   => /^(?!\/\/[^\/])[ \t]*([^ \t].*?)(;;)(?:$|[ \t]+(.*)$)/,
  }

  # Matches a callout list item.
  CalloutListRx = /^<(\d+|\.)>[ \t]+(.*)$/

  # Matches a callout reference inside literal text.
  CalloutExtractRx = /((?:\/\/|#|--|;;) ?)?(\\)?<!?(|--)(\d+|\.)(\3)>(?=(?: ?\\?<!?\3(?:\d+|\.)\3>)*$)/
  CalloutScanRx    = /\\?<!?(|--)(\d+|\.)\1>(?=(?: ?\\?<!?\1(?:\d+|\.)\1>)*$)/

  # A Hash of regexps for lists used for dynamic access (string keys).
  LIST_RX_MAP = {
    "ulist"  => UnorderedListRx,
    "olist"  => OrderedListRx,
    "dlist"  => DescriptionListRx,
    "colist" => CalloutListRx,
  }

  # A Hash of regexps for lists used for dynamic access (symbol keys).
  ListRxMap = {
    :ulist  => UnorderedListRx,
    :olist  => OrderedListRx,
    :dlist  => DescriptionListRx,
    :colist => CalloutListRx,
  }

  # A Hash mapping ordered list styles to their marker patterns.
  OrderedListMarkerRxMap = {
    :arabic     => /^\d+\.$/,
    :loweralpha => /^[a-z]\.$/,
    :lowerroman => /^[ivx]+\)$/,
    :upperalpha => /^[A-Z]\.$/,
    :upperroman => /^[IVX]+\)$/,
  }

  # Matches a sibling description list item (excluding the delimiter specified by the key).
  DescriptionListSiblingRx = {
    "::"   => /^(?!\/\/[^\/])[ \t]*([^ \t].*?[^:]|[^ \t:])(::)(?:$|[ \t]+(.*)$)/,
    ":::"  => /^(?!\/\/[^\/])[ \t]*([^ \t].*?[^:]|[^ \t:])(:::)(?:$|[ \t]+(.*)$)/,
    "::::" => /^(?!\/\/[^\/])[ \t]*([^ \t].*?[^:]|[^ \t:])(::::)(?:$|[ \t]+(.*)$)/,
    ";;"   => /^(?!\/\/[^\/])[ \t]*([^ \t].*?)(;;)(?:$|[ \t]+(.*)$)/,
  }

  # --------------------------------------------------------------------------
  # Tables
  # --------------------------------------------------------------------------

  # Parses the column spec (colspec) for a table.
  ColumnSpecRx = /^(?:(\d+)\*)?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?(\d+%?|~)?([a-z])?$/

  # Parses the start and end of a cell spec (cellspec) for a table.
  CellSpecStartRx = /^[ \t]*(?:(\d+(?:\.\d*)?|(?:\d*\.)?\d+)([*+]))?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?([a-z])?$/
  CellSpecEndRx   = /[ \t]+(?:(\d+(?:\.\d*)?|(?:\d*\.)?\d+)([*+]))?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?([a-z])?$/

  # --------------------------------------------------------------------------
  # Block macros
  # --------------------------------------------------------------------------

  # Matches a custom block macro.
  CustomBlockMacroRx = /^(\p{Xwd}[\p{Xwd}-]*)::(|\S|\S.*?\S)\[(.+)?\]$/

  # Matches an image, video or audio block macro.
  BlockMediaMacroRx = /^(image|video|audio)::(\S|\S.*?\S)\[(.+)?\]$/

  # Matches the TOC block macro.
  BlockTocMacroRx = /^toc::\[(.+)?\]$/

  # --------------------------------------------------------------------------
  # Inline macros
  # --------------------------------------------------------------------------

  # Matches an anchor in the flow of text.
  InlineAnchorRx = /(\\)?(?:\[\[(\p{L}[\p{Xwd}\-:.]*)(?:, *(.+?))? ?\]\]|anchor:(\p{L}[\p{Xwd}\-:.]*)\[(?:\]|(.+?[^\\])\]))/

  # Scans for a non-escaped anchor in the flow of text.
  InlineAnchorScanRx = /(?:^|[^\\\[])\[\[(\p{L}[\p{Xwd}\-:.]*)(?:, *(.+?))? ?\]\]|(?:^|[^\\])anchor:(\p{L}[\p{Xwd}\-:.]*)\[(?:\]|(.+?[^\\])\])/

  # Scans for a leading, non-escaped anchor.
  LeadingInlineAnchorRx = /^\[\[(\p{L}[\p{Xwd}\-:.]*)(?:, *(.+?))?\]\]/

  # Matches a bibliography anchor at the start of list item text.
  InlineBiblioAnchorRx = /^\[\[\[(\p{L}[\p{Xwd}\-:.]*)(?:, *(.+?))?\]\]\]/

  # Matches an inline e-mail address.
  InlineEmailRx = /([\\>:\/])?\p{Xwd}(?:&amp;|[\p{Xwd}\-.%+])*@\p{Xan}[\p{Xan}_\-.]*\.[a-zA-Z]{2,5}\b/

  # Matches an inline footnote macro.
  InlineFootnoteMacroRx = /\\?footnote(?:(ref):|:([\p{Xwd}-]+)?)\[(?:|(.*?[^\\]))\]/m

  # Matches an image or icon inline macro.
  InlineImageMacroRx = /\\?i(?:mage|con):([^:\s\[](?:[^\n\[]*[^\s\[])?)\[(|.*?[^\\])\]/m

  # Matches an indexterm inline macro.
  InlineIndextermMacroRx = /\\?(?:(indexterm2?):\[(.*?[^\\])\]|\(\((.+?)\)\)(?!\)))/m

  # Matches a kbd or btn inline macro.
  InlineKbdBtnMacroRx = /(\\)?(kbd|btn):\[(.*?[^\\])\]/m

  # Matches a kbd inline macro.
  InlineKbdMacroRx = /\\?kbd:\[(.*?[^\\])\]/m

  # Matches a btn inline macro.
  InlineBtnMacroRx = /\\?btn:\[(.*?[^\\])\]/m

  # Matches an implicit link and some of the link inline macro.
  InlineLinkRx = /(^|link:|[\p{Zs}\t]|\\?&lt;()|[>\(\)\[\];"'])(\\?(?:https?|file|ftp|irc):\/\/)(?:([^\s\[\]]+)\[(|.*?[^\\])\]|\2([^\s]+?)&gt;|([^\s\[\]<]*([^\s,.?!\[\]<\)])))/m

  # Matches a link or e-mail inline macro.
  InlineLinkMacroRx = /\\?(?:link|(mailto)):(|[^:\s\[][^\s\[]*)\[(|.*?[^\\])\]/m

  # Matches the name of a macro.
  MacroNameRx = /^\p{Xwd}[\p{Xwd}-]*$/

  # Matches a stem inline macro.
  InlineStemMacroRx = /\\?(stem|(?:latex|ascii)math):([a-z]+(?:,[a-z-]+)*)?\[(.*?[^\\])\]/m

  # Matches a menu inline macro.
  InlineMenuMacroRx = /\\?menu:(\p{Xwd}|[\p{Xwd}&][^\n\[]*[^\s\[])\[ *(?:|(.*?[^\\]))\]/m

  # Matches an implicit menu inline macro.
  InlineMenuRx = /\\?"([\p{Xwd}&][^"]*?[ \n]+&gt;[ \n]+[^"]*)"/

  # Matches several variants of the passthrough inline macro.
  InlinePassMacroRx = /(?:(?:(\\?)\[([^\[\]]+)\])?(\\{0,2})(\+\+\+?|\$\$)(.*?)\4|(\\?)pass:([a-z]+(?:,[a-z-]+)*)?\[(|.*?[^\\])\])/m

  # Matches an xref (cross-reference) inline macro.
  InlineXrefMacroRx = /\\?(?:&lt;&lt;([\p{Xwd}#\/.:{].*?)&gt;&gt;|xref:([\p{Xwd}#\/.:{].*?)\[(?:\]|(.*?[^\\])\]))/m

  # --------------------------------------------------------------------------
  # Layout
  # --------------------------------------------------------------------------

  # Matches a trailing + preceded by at least one space (hard line break).
  HardLineBreakRx = /^(.*) \+$/m

  # Matches a Markdown horizontal rule.
  MarkdownThematicBreakRx = /^ {0,3}([-*_])( *)\1\2\1$/

  # Matches an AsciiDoc or Markdown horizontal rule or page break.
  ExtLayoutBreakRx = /^(?:'{3,}|<{3,}|([-*_])( *)\1\2\1)$/

  # --------------------------------------------------------------------------
  # General
  # --------------------------------------------------------------------------

  # Matches consecutive blank lines.
  BlankLineRx = /\n{2,}/

  # Matches whitespace escaped by a backslash.
  EscapedSpaceRx = /\\([ \t\n])/

  # Detects if text is a possible candidate for the replacements substitution.
  ReplaceableTextRx = /[&']|--|\.\.\.|\([CRT]M?\)/

  # Matches a whitespace delimiter.
  SpaceDelimiterRx = /([^\\])[ \t\n]+/

  # Matches a + or - modifier in a subs list.
  SubModifierSniffRx = /[+-]/

  # Matches one or more consecutive digits at the end of a line.
  TrailingDigitsRx = /\d+$/

  # Matches callout source markers.
  CalloutSourceRx = /((?:\/\/|#|--|;;) ?)?(\\)?&lt;!?(|--)([\d]+|\.)\3&gt;(?=(?: ?\\?&lt;!?\3(?:\d+|\.)\3&gt;)*$)/m

  # Detects strings that resemble URIs.
  UriSniffRx = /\A\p{L}[\p{Xan}.+-]+:\/{0,2}/

  # Detects XML tags.
  XmlSanitizeRx = /<[^>]+>/

  # Sentinel values for list continuation tracking.
  # In Ruby, ListContinuationMarker is a Module mixed into String instances.
  # In Crystal, we use unique sentinel strings to distinguish continuation lines.
  LIST_CONTINUATION_STRING      = "\x19"
  LIST_CONTINUATION_PLACEHOLDER = "\x1a"
end
