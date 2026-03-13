require "./abstract_node"
require "./content_model"
require "./source_location"

module Asciidoctor
  # An abstract base class that provides state and methods for managing a
  # block-level node of AsciiDoc content. Block-level nodes include Document,
  # Section, Block, List, ListItem, and Table.
  abstract class AbstractBlock < AbstractNode
    include Substitutors

    # The Array of child blocks for this block.
    getter blocks : Array(AbstractBlock)

    # The caption for this block.
    property caption : String?

    # Describes the type of content this block accepts.
    property content_model : ContentModel

    # The Integer level of this Section or the Section to which this block belongs.
    property level : Int32

    # The String numeral of this block (if section, relative to parent, otherwise absolute).
    property numeral : String?

    # The location in the AsciiDoc source where this block begins.
    property source_location : SourceLocation?

    # The String style (block type qualifier) for this block.
    property style : String?

    # Substitutions to be applied to content in this block.
    getter subs : Substitution

    # The raw title for this block.
    @title : String?

    # The converted title (memoized).
    @converted_title : String?

    # Section indexing.
    @next_section_index : Int32
    @next_section_ordinal : Int32
    @next_appendix_index : Int32

    # Default substitutions.
    @default_subs : Substitution?

    # Substitutions list (symbol-based, used by Substitutors module).
    property subs_list : Array(Symbol) = [] of Symbol

    def initialize(@context : Symbol, @attributes : Hash(String, String) = {} of String => String)
      super(@context, @attributes)
      @blocks = [] of AbstractBlock
      @caption = nil
      @content_model = ContentModel::Compound
      @converted_title = nil
      @default_subs = nil
      @id = nil
      @level = 0
      @next_section_index = 0
      @next_section_ordinal = 1
      @next_appendix_index = 0
      @numeral = nil
      @passthroughs = [] of PassthroughEntry
      @source_location = nil
      @style = nil
      @subs = Substitution::None
      @subs_list = [] of Symbol
      @title = nil
    end

    # Append a content block to this block's list of blocks.
    def <<(block : AbstractBlock) : self
      @blocks << block
      self
    end

    # Retrieve the alt text for this block image.
    def alt : String
      attr("alt") || ""
    end

    # Internal: Assign the next index and numeral to the section.
    def assign_numeral(section : Section) : Nil
      section.index = @next_section_index
      @next_section_index += 1
      if section.numbered
        if (sectname = section.sectname) == "appendix"
          appendix_idx = @next_appendix_index
          @next_appendix_index += 1
          section.numeral = (65 + appendix_idx).chr.to_s # A, B, C...
          # Assign caption for appendix sections (e.g., "Appendix A: ")
          appendix_caption = section.document.attributes["appendix-caption"]? || "Appendix"
          unless appendix_caption.empty?
            section.caption = "#{appendix_caption} #{section.numeral}: "
          end
        elsif sectname == "chapter"
          # NOTE chapters in a book doctype are sequential even for multi-part books (see #979)
          doc = section.document
          STDERR.puts "chapter #{section.title}: doc.object_id=#{doc.object_id} chapter-number attr=#{doc.attributes["chapter-number"]?.inspect}"
          section.numeral = doc.counter("chapter-number", 1).to_s
          STDERR.puts "  -> numeral=#{section.numeral}"
        else
          section.numeral = @next_section_ordinal.to_s
          @next_section_ordinal += 1
        end
      end
    end

    # Generate and assign caption to block if not already assigned.
    def assign_caption(value : String? = nil, caption_context : Symbol = @context) : Nil
      return if @caption || !@title
      if value
        @caption = value
        return
      end
      if (doc_caption = document.attributes["caption"]?)
        @caption = doc_caption
        return
      end
      ctx_str = caption_context.to_s
      if (attr_name = CAPTION_ATTRIBUTE_NAMES[ctx_str]?) && (prefix = document.attributes[attr_name]?)
        @numeral = document.increment_and_store_counter("#{caption_context}-number", self)
        @caption = "#{prefix} #{@numeral}. "
      end
    end

    def block? : Bool
      true
    end

    # Determine whether this Block contains block content.
    def blocks? : Bool
      !@blocks.empty?
    end

    # Convenience method that returns the interpreted title of the Block
    # with the caption prepended.
    def captioned_title : String
      "#{@caption}#{title}"
    end

    # Get the converted result of the child blocks by converting the
    # children appropriate to content model that this block supports.
    def content : String?
      case @content_model
      when ContentModel::Compound
        @blocks.map { |b| b.convert }.join('\n')
      else
        nil
      end
    end

    # Update the context of this block.
    def context=(context : Symbol)
      @context = context
      @node_name = context.to_s
    end

    # Delegate to the converter to convert this block.
    def convert : String
      document.playback_attributes(@attributes)
      if c = document.converter
        c.convert(self)
      else
        ""
      end
    end

    # Get the source file where this block started.
    def file : String?
      @source_location.try(&.file)
    end

    # Walk the document tree and find all block-level nodes that match the
    # specified selector.
    def find_by(context : Symbol? = nil, style : String? = nil, role : String? = nil, id : String? = nil) : Array(AbstractBlock)
      result = [] of AbstractBlock
      find_by_internal(context, style, role, id, result)
      result
    end

    def inline? : Bool
      false
    end

    # Get the source line number where this block started.
    def lineno : Int32?
      @source_location.try(&.lineno)
    end

    # Retrieve the list marker keyword for the specified list type.
    def list_marker_keyword(list_type : String? = nil) : String?
      ORDERED_LIST_KEYWORDS[list_type || @style]?
    end

    # Get the next adjacent block in the document tree (sibling or parent's next sibling).
    def next_adjacent_block : AbstractBlock?
      if (p = parent) && p.is_a?(AbstractBlock)
        siblings = p.blocks
        idx = siblings.index(self)
        if idx && idx < siblings.size - 1
          siblings[idx + 1]
        elsif p.is_a?(AbstractBlock)
          p.next_adjacent_block
        else
          nil
        end
      else
        nil
      end
    end

    # Alias for numeral (deprecated but present in Ruby).
    def number : String?
      @numeral
    end

    # Alias for numeral= (deprecated but present in Ruby).
    def number=(val : String?)
      @numeral = val
    end

    # Internal: Reassign the section indexes.
    def reindex_sections : Nil
      @next_section_index = 0
      @next_section_ordinal = 1
      @next_appendix_index = 0
      @blocks.each do |block|
        if block.context == :section && block.is_a?(Section)
          assign_numeral(block)
          block.reindex_sections
        end
      end
    end

    # Remove a substitution from this block.
    def remove_sub(sub : Substitution) : Nil
      @subs &= ~sub
    end

    # Get the Array of child Section objects.
    def sections : Array(AbstractBlock)
      @blocks.select { |block| block.context == :section }
    end

    # Check whether this block has any child Section objects.
    def sections? : Bool
      false
    end

    # A convenience method that checks whether the specified
    # substitution is enabled for this block.
    def sub?(name : Substitution) : Bool
      @subs.includes?(name)
    end

    # Get the String title of this Block with title substitutions applied.
    def title : String?
      @converted_title ||= if (t = @title)
        apply_title_subs(t)
      else
        nil
      end
    end

    # Apply inline substitutions to the title
    protected def apply_title_subs(title : String) : String
      apply_subs(title, [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements])
    end

    # Set the String block title.
    def title=(val : String?)
      @converted_title = nil
      @title = val
    end

    # A convenience method that checks whether the title is set.
    def title? : Bool
      !@title.nil?
    end

    # Generate cross reference text (xreftext) that can be used to refer
    # to this block.
    def xreftext(xrefstyle : String? = nil) : String?
      if (val = reftext) && !val.empty?
        val
      elsif xrefstyle && @title && @caption
        case xrefstyle
        when "full"
          quoted_title = title || ""
          if @numeral && (caption_attr_name = CAPTION_ATTRIBUTE_NAMES[@context]?) && (prefix = document.attributes[caption_attr_name]?)
            "#{prefix} #{@numeral}, \"#{quoted_title}\""
          else
            cap = (@caption || "").rstrip.rstrip('.')
            "#{cap}, \"#{quoted_title}\""
          end
        when "short"
          if @numeral && (caption_attr_name = CAPTION_ATTRIBUTE_NAMES[@context]?) && (prefix = document.attributes[caption_attr_name]?)
            "#{prefix} #{@numeral}"
          else
            (@caption || "").rstrip.rstrip('.')
          end
        else # "basic"
          title
        end
      else
        title
      end
    end

    # Section index accessors.
    protected def next_section_index : Int32
      @next_section_index
    end

    protected def next_section_index=(val : Int32)
      @next_section_index = val
    end

    protected def next_section_ordinal : Int32
      @next_section_ordinal
    end

    protected def next_section_ordinal=(val : Int32)
      @next_section_ordinal = val
    end

    protected def find_by_internal(context_selector : Symbol?, style_selector : String?, role_selector : String?, id_selector : String?, result : Array(AbstractBlock)) : Nil
      any_context = context_selector.nil?
      if (any_context || context_selector == @context) &&
         (style_selector.nil? || style_selector == @style) &&
         (role_selector.nil? || has_role?(role_selector)) &&
         (id_selector.nil? || id_selector == @id)
        result << self
        return if id_selector
      end

      @blocks.each do |b|
        next if context_selector == :section && b.context != :section
        b.find_by_internal(context_selector, style_selector, role_selector, id_selector, result)
      end
    end
  end
end
