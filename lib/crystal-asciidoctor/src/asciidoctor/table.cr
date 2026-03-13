require "./abstract_block"
require "./abstract_node"

module Asciidoctor
  # Methods and constants for managing AsciiDoc table content in a document.
  class Table < AbstractBlock
    # Precision of column widths.
    DEFAULT_PRECISION = 4

    # A data object that encapsulates the collection of rows (head, foot, body) for a table.
    class Rows
      property body : Array(Array(Cell))
      property foot : Array(Array(Cell))
      property head : Array(Array(Cell))

      def initialize(@head = [] of Array(Cell), @foot = [] of Array(Cell), @body = [] of Array(Cell))
      end

      # Retrieve the rows grouped by section as a nested Array.
      def by_section : Array(Tuple(Symbol, Array(Array(Cell))))
        [{:head, @head}, {:body, @body}, {:foot, @foot}]
      end

      # Retrieve the rows as a Hash.
      def to_h : Hash(Symbol, Array(Array(Cell)))
        {:head => @head, :body => @body, :foot => @foot}
      end
    end

    # The columns for this table.
    property columns : Array(Column)

    # Boolean specifying whether this table has a header row.
    property has_header_option : Bool

    # The parent block.
    getter parent_block : AbstractBlock

    # The Rows struct for this table.
    property rows : Rows

    # The document this table belongs to.
    @document : Document

    def initialize(@parent_block : AbstractBlock,
                   attributes : Hash(String, String) = {} of String => String)
      super(:table, attributes)
      @document = @parent_block.document
      @columns = [] of Column
      @has_header_option = false
      @parent = @parent_block
      @rows = Rows.new

      # Resolve table width.
      pcwidth = attributes["width"]?
      pcwidth_intval = if pcwidth
                         # Strip % if present (e.g., "75%" -> 75)
                         v = pcwidth.gsub("%", "").to_i? || 100
                         (v > 100 || v < 1) ? 100 : v
                       else
                         100
                       end
      @attributes["tablepcwidth"] = pcwidth_intval.to_s
    end

    # Assign column widths based on the width base and autowidth columns.
    def assign_column_widths(width_base : Float64? = nil, autowidth_cols : Array(Column)? = nil) : Nil
      precision = DEFAULT_PRECISION
      if width_base
        total = 0.0
        @columns.each do |col|
          total += col.assign_width(nil, width_base, precision)
        end
        # Distribute rounding error to last column.
        if total != 100.0 && !@columns.empty?
          last = @columns.last
          diff = 100.0 - total
          current = last.attributes["colpcwidth"]?.try(&.to_f) || 0.0
          last.attributes["colpcwidth"] = (current + diff).round(precision).to_s
        end
      elsif autowidth_cols
        if autowidth_cols.size == @columns.size
          # All columns are autowidth.
          col_pcwidth = (100.0 / @columns.size).round(precision)
          @columns.each do |col|
            col.assign_width(col_pcwidth, nil, precision)
          end
        else
          # Only some columns are autowidth.
          remaining = 100.0
          @columns.each do |col|
            unless autowidth_cols.includes?(col)
              remaining -= col.assign_width(nil, nil, precision)
            end
          end
          if autowidth_cols.size > 0
            col_pcwidth = (remaining / autowidth_cols.size).round(precision)
            autowidth_cols.each do |col|
              col.assign_width(col_pcwidth, nil, precision)
            end
          end
        end
      end
    end

    # Creates the Column objects from the column spec.
    def create_columns(colspecs : Array(Hash(String, String | Int32))) : Nil
      cols = [] of Column
      colspecs.each_with_index do |colspec, idx|
        cols << Column.new(self, idx, colspec)
      end
      @columns = cols
      @attributes["colcount"] = cols.size.to_s if cols.size > 0
    end

    def document : Document
      @document
    end

    # Returns the current state of the header option if the row being processed
    # is the header row, otherwise false.
    def header_row? : Bool
      @has_header_option && @rows.body.empty?
    end

    # Internal: Partition the rows into header, footer and body.
    def partition_header_footer(attrs : Hash(String, String)) : Nil
      body = @rows.body
      num_body_rows = body.size
      @attributes["rowcount"] = num_body_rows.to_s

      if num_body_rows > 0 && @has_header_option
        @rows.head = [body.shift]
        num_body_rows -= 1
      end

      if num_body_rows > 0 && attrs.has_key?("footer-option")
        @rows.foot = [body.pop]
      end
    end
  end

  # Methods to manage the columns of an AsciiDoc table.
  class Table::Column < AbstractNode
    # The parent table.
    getter table : Table

    # The style for this column.
    property style : String?

    # The document this column belongs to.
    @document : Document

    def initialize(@table : Table, index : Int32, attributes : Hash(String, String | Int32) = {} of String => String | Int32)
      super(:table_column, {} of String => String)
      @document = @table.document
      @parent = @table
      @style = attributes["style"]?.try(&.as(String))
      @attributes["colnumber"] = (index + 1).to_s
      @attributes["halign"] = (attributes["halign"]?.try(&.as(String))) || "left"
      @attributes["valign"] = (attributes["valign"]?.try(&.as(String))) || "top"
      @attributes["width"] = (attributes["width"]? || 1).to_s
    end

    # Calculate and assign the widths for this column.
    def assign_width(col_pcwidth : Float64?, width_base : Float64?, precision : Int32) : Float64
      if width_base
        w = @attributes["width"]?.try(&.to_f) || 1.0
        result = (w * 100.0 / width_base).round(precision)
      elsif col_pcwidth
        result = col_pcwidth
      else
        result = 0.0
      end
      @attributes["colpcwidth"] = result.to_s
      result
    end

    def block? : Bool
      false
    end

    def document : Document
      @document
    end

    def inline? : Bool
      false
    end
  end

  # Methods for managing a cell in an AsciiDoc table.
  class Table::Cell < AbstractBlock
    # The style of this cell.
    property cell_style : Symbol?

    # The parent column.
    getter column : Table::Column

    # The number of columns this cell will span.
    property colspan : Int32?

    # The nested Document in an AsciiDoc table cell (only set when style is :asciidoc).
    getter inner_document : Document?

    # The number of rows this cell will span.
    property rowspan : Int32?

    # The text content of this cell.
    @text : String

    # The document this cell belongs to.
    @document : Document

    def initialize(@column : Table::Column, cell_text : String = "",
                   attributes : Hash(String, String) = {} of String => String,
                   colspan : Int32? = nil, rowspan : Int32? = nil,
                   style : Symbol? = nil)
      super(:table_cell, attributes)
      @document = @column.document
      # Use cell style if provided, otherwise inherit from column
      col_style = @column.style
      # Map column style string to symbol
      col_sym = if col_style && !col_style.empty?
        case col_style
        when "e" then :emphasis
        when "m" then :monospaced
        when "s" then :strong
        when "h" then :header
        when "l" then :literal
        when "v" then :verse
        when "a" then :asciidoc
        when "d" then :default
        else nil
        end
      else
        nil
      end
      @cell_style = style || col_sym
      @colspan = colspan
      @content_model = ContentModel::Simple
      @inner_document = nil
      @parent = @column
      @rowspan = rowspan
      @subs = NORMAL_SUBS
      @text = cell_text
      # Inherit halign/valign from column if not already set in cell attributes
      @attributes["halign"] ||= @column.attributes["halign"]? || "left"
      @attributes["valign"] ||= @column.attributes["valign"]? || "top"
    end

    # Handles the body data (tbody, tfoot), applying styles and partitioning into paragraphs.
    def content : String | Array(String)
      if @cell_style == :asciidoc && (inner = @inner_document)
        inner.to_s
      elsif @text.includes?("\n\n")
        subs_to_apply = [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements] of Symbol
        @text.split(/\n{2,}/).map { |para| apply_subs(para, subs_to_apply) }
      else
        subs_to_apply = [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements] of Symbol
        [apply_subs(@text, subs_to_apply)]
      end
    end

    def document : Document
      @document
    end

    # Get the source file where this cell started.
    def file : String?
      @source_location.try(&.file)
    end

    # Get the source line number where this cell started.
    def lineno : Int32?
      @source_location.try(&.lineno)
    end

    def lines : Array(String)
      @text.split('\n')
    end

    def source : String
      @text
    end

    # Get the String text of this cell with substitutions applied.
    def text : String
      subs_to_apply = [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements] of Symbol
      apply_subs(@text, subs_to_apply)
    end

    # Set the String text for this cell.
    def text=(val : String)
      @text = val
    end

    def to_s(io : IO) : Nil
      io << "#<" << self.class.name << " {text: " << @text.inspect << ", colspan: " << (@colspan || 1) << ", rowspan: " << (@rowspan || 1) << "}>"
    end
  end
end
