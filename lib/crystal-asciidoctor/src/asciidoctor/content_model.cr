module Asciidoctor
  # Describes the type of content a block accepts and how it should be converted.
  enum ContentModel
    # This block contains other blocks
    Compound

    # This block holds a paragraph of prose that receives normal substitutions
    Simple

    # This block holds verbatim text (displayed "as is") that receives verbatim substitutions
    Verbatim

    # This block holds unprocessed content passed directly to the output with no substitutions applied
    Raw

    # This block has no content
    Empty

    # This block should be skipped (e.g., comment blocks)
    Skip
  end
end
