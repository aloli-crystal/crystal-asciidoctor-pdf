require "./abstract_block"

module Asciidoctor
  # Methods for managing AsciiDoc lists (ordered, unordered and description lists).
  class List < AbstractBlock
    # The parent block.
    getter parent_block : AbstractBlock

    # The document this list belongs to.
    @document : Document

    def initialize(@parent_block : AbstractBlock, @context : Symbol,
                   attributes : Hash(String, String) = {} of String => String)
      super(@context, attributes)
      @document = @parent_block.document
      @level = @parent_block.level
      @parent = @parent_block
    end

    # Delegate to the converter to convert this list.
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

    # Alias for blocks.
    def items : Array(AbstractBlock)
      @blocks
    end

    # Check if this list has items.
    def items? : Bool
      blocks?
    end

    # Check whether this list is an outline list (unordered or ordered).
    def outline? : Bool
      @context == :ulist || @context == :olist
    end

    def to_s(io : IO) : Nil
      io << "#<" << self.class.name << " {context: " << @context << ", style: " << @style.inspect << ", items: " << @blocks.size << "}>"
    end
  end

  # Methods for managing items for AsciiDoc olists, ulists, and dlists.
  class ListItem < AbstractBlock
    # The String used to mark this list item.
    property marker : String?

    # The text of this list item.
    @text : String?

    # The parent list.
    getter parent_list : List

    # The document this list item belongs to.
    @document : Document

    def initialize(@parent_list : List, text : String? = nil)
      super(:list_item, {} of String => String)
      @document = @parent_list.document
      @level = @parent_list.level
      @marker = nil
      @parent = @parent_list
      @subs = NORMAL_SUBS
      @text = text
    end

    # Check whether this list item has compound content.
    def compound? : Bool
      !simple?
    end

    def document : Document
      @document
    end

    # Fold the adjacent paragraph block into the list item text.
    def fold_first : Nil
      if first_block = @blocks.first?
        if first_block.is_a?(Block)
          if @text.nil? || @text.try(&.empty?)
            @text = first_block.source
          else
            @text = "#{@text}\n#{first_block.source}"
          end
          @blocks.shift
        end
      end
    end

    # Alias for parent list.
    def list : List
      @parent_list
    end

    # Check whether this list item has simple content.
    def simple? : Bool
      @blocks.empty? || (@blocks.size == 1 && @blocks[0].is_a?(List) && @blocks[0].as(List).outline?)
    end

    # Get the String text of this ListItem with substitutions applied.
    def text : String?
      if (t = @text)
        subs_to_apply = subs_list
        if subs_to_apply.empty?
          subs_to_apply = [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements] of Symbol
        end
        apply_subs(t, subs_to_apply)
      else
        nil
      end
    end

    # Set the String text assigned to this ListItem.
    def text=(val : String?)
      @text = val
    end

    # A convenience method that checks whether the text of this list item
    # is not blank (i.e., not nil or empty string).
    def text? : Bool
      !(@text.nil? || @text.try(&.empty?))
    end

    def to_s(io : IO) : Nil
      io << "#<" << self.class.name << " {list_context: " << @parent_list.context << ", text: " << @text.inspect << ", blocks: " << @blocks.size << "}>"
    end
  end
end
