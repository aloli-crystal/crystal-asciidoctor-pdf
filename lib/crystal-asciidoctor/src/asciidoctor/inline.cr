require "./abstract_node"

module Asciidoctor
  # Methods for managing inline elements in AsciiDoc block.
  class Inline < AbstractNode
    # The parent block.
    getter parent_block : AbstractBlock

    # The target (e.g., uri) of this inline element.
    property target : String?

    # The text of this inline element.
    property text : String?

    # The type (qualifier) of this inline element.
    getter type : Symbol?

    # The document this inline belongs to.
    @document : Document

    def initialize(@parent_block : AbstractBlock, @context : Symbol, @text : String? = nil,
                   id : String? = nil, type : Symbol? = nil, target : String? = nil,
                   attributes : Hash(String, String) = {} of String => String)
      super(@context, attributes)
      @document = @parent_block.document
      @node_name = "inline_#{@context}"
      @id = id
      @parent = @parent_block
      @type = type
      @target = target
    end

    # Returns the converted alt text for this inline image.
    def alt : String
      attr("alt") || ""
    end

    def block? : Bool
      false
    end

    # Get the converted result of this node's primary content (aka text).
    def content : String?
      @text
    end

    # Delegate to the converter to convert this inline node.
    def convert : String
      if c = document.converter
        c.convert(self)
      else
        ""
      end
    end

    def document : Document
      @document
    end

    def inline? : Bool
      true
    end

    # For a reference node, the text is the reftext.
    def reftext : String?
      @text
    end

    # For a reference node (:ref or :bibref), the text is the reftext.
    def reftext? : Bool
      !@text.nil? && (@type == :ref || @type == :bibref)
    end

    # Generate cross reference text (xreftext) that can be used to refer
    # to this inline node.
    def xreftext(xrefstyle : String? = nil) : String?
      reftext
    end
  end
end
