module Asciidoctor
  # Represents the types of substitutions that can be applied to AsciiDoc content.
  @[Flags]
  enum Substitution
    SpecialCharacters
    Quotes
    Attributes
    Replacements
    Macros
    PostReplacements
    Callouts
  end

  # Pre-defined substitution groups
  BASIC_SUBS      = Substitution::SpecialCharacters
  HEADER_SUBS     = Substitution::SpecialCharacters | Substitution::Attributes
  NORMAL_SUBS     = Substitution::SpecialCharacters | Substitution::Quotes | Substitution::Attributes | Substitution::Replacements | Substitution::Macros | Substitution::PostReplacements
  VERBATIM_SUBS   = Substitution::SpecialCharacters | Substitution::Callouts
  REFTEXT_SUBS    = Substitution::SpecialCharacters | Substitution::Quotes | Substitution::Replacements
  NO_SUBS         = Substitution::None
end
