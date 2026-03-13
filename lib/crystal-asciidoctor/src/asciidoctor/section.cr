require "./abstract_block"

module Asciidoctor
  # Methods for managing sections of AsciiDoc content in a document.
  # The section responds as an Array of content blocks by delegating
  # block-related methods to its @blocks Array.
  class Section < AbstractBlock
    # The 0-based index order of this section within the parent block.
    property index : Int32

    # Flag to indicate whether this section should be numbered.
    property numbered : Bool

    # The parent block.
    getter parent_block : AbstractBlock?

    # The section name of this section.
    property sectname : String?

    # Flag to indicate whether this is a special section or a child of one.
    property special : Bool

    def special? : Bool
      @special
    end

    # The document this section belongs to.
    @document : Document

    def initialize(document : Document, parent : AbstractBlock? = nil, level : Int32? = nil, numbered : Bool = false, attributes : Hash(String, String) = {} of String => String)
      super(:section, attributes)
      @document = document
      @parent_block = parent
      @parent = parent
      if parent.is_a?(Section)
        @level = level || (parent.level + 1)
        @special = parent.special
      else
        @level = level || 1
        @special = false
      end
      @index = 0
      @numbered = numbered
      @sectname = @special ? nil : "section"
    end

    # Append a content block to this block's list of blocks.
    # If the child block is a Section, assign an index to it.
    def <<(block : AbstractBlock) : self
      if block.is_a?(Section)
        assign_numeral(block)
      end
      super(block)
    end

    def document : Document
      @document
    end

    # Generate a String id for this section based on its title.
    def generate_id : String?
      if t = title
        Section.generate_id(t, @document)
      end
    end

    # The name of this section, an alias of the section title.
    def name : String?
      title
    end

    # Get the section number for the current Section.
    #
    # The section number is a dot-separated String that uniquely describes
    # the position of this Section in the document.
    def sectnum(delimiter : String = ".", append : String? = nil) : String
      actual_append = append || delimiter
      if @level > 1 && (p = @parent_block).is_a?(Section)
        "#{p.sectnum(delimiter, delimiter)}#{@numeral}#{actual_append}"
      else
        "#{@numeral}#{actual_append}"
      end
    end

    # Check whether this Section has any child Section objects.
    def sections? : Bool
      next_section_index > 0
    end

    def to_s(io : IO) : Nil
      if t = @title
        formal_title = @numbered ? "#{sectnum} #{t}" : t
        io << "#<" << self.class.name << " {level: " << @level << ", title: " << formal_title.inspect << ", blocks: " << @blocks.size << "}>"
      else
        io << "#<" << self.class.name << " {level: " << @level << ", blocks: " << @blocks.size << "}>"
      end
    end

    # Generate cross reference text (xreftext) that can be used to refer
    # to this section.
    def xreftext(xrefstyle : String? = nil) : String?
      if (val = reftext) && !val.empty?
        val
      elsif xrefstyle
        case xrefstyle
        when "full"
          if @numbered
            if (refsig = document.attributes["#{@sectname || "section"}-refsig"]?)
              "#{refsig} #{sectnum(".", "")}, \"#{title}\""
            else
              "\"#{title}\""
            end
          else
            "\"#{title}\""
          end
        when "short"
          if @numbered
            if (refsig = document.attributes["#{@sectname || "section"}-refsig"]?)
              "#{refsig} #{sectnum(".", "")}"
            else
              sectnum(".", "")
            end
          else
            title
          end
        else # "basic"
          title
        end
      else
        title
      end
    end

    # Generate a String id from the given section title and document.
    # If the generated id already exists in the document catalog, a numeric
    # suffix is appended to make it unique (e.g., _my_section_2).
    def self.generate_id(title : String, document : Document) : String
      prefix = document.attributes["idprefix"]? || "_"
      separator = document.attributes["idseparator"]? || "_"
      base_id = title.downcase
        .gsub(/[^a-z0-9 -]/, "")
        .strip
        .gsub(/\s+/, separator)
      candidate = "#{prefix}#{base_id}"
      if document.catalog.refs.has_key?(candidate)
        count = 2
        while document.catalog.refs.has_key?("#{candidate}#{separator}#{count}")
          count += 1
        end
        candidate = "#{candidate}#{separator}#{count}"
      end
      candidate
    end
  end
end
