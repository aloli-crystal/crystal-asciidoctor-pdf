module Asciidoctor
  # Internal: Struct to hold block match data returned by is_delimited_block?
  record BlockMatchData, context : Symbol, masq : Set(String), tip : String, terminator : String

  # Internal: Methods to parse lines of AsciiDoc into an object hierarchy
  # representing the structure of the document. All methods are module methods
  # and should be invoked from the Parser module.
  #
  # The object hierarchy created by the Parser consists of zero or more Section
  # and Block objects. Section objects may be nested and a Section object
  # contains zero or more Block objects.
  module Parser
    extend self
    include Logging

    TAB = '\t'

    TabIndentRx = /^\t+/

    # A Hash mapping horizontal alignment abbreviations to alignments
    TableCellHorzAlignments = {
      '<' => "left",
      '>' => "right",
      '^' => "center",
    }

    # A Hash mapping vertical alignment abbreviations to alignments
    TableCellVertAlignments = {
      '<' => "top",
      '>' => "bottom",
      '^' => "middle",
    }

    # A Hash mapping style abbreviations to styles for table cells
    TableCellStyles = {
      'd' => :none,
      's' => :strong,
      'e' => :emphasis,
      'm' => :monospaced,
      'h' => :header,
      'l' => :literal,
      'a' => :asciidoc,
    }

    AuthorKeys = Set{"author", "authorinitials", "firstname", "middlename", "lastname", "email"}

    # --------------------------------------------------------------------------
    # Utility methods (sorted alphabetically)
    # --------------------------------------------------------------------------

    # Remove the block indentation, replace tabs with spaces, and indent by margin.
    def adjust_indentation!(lines : Array(String), indent_size : Int32 = 0, tab_size : Int32 = 0) : Nil
      return if lines.empty?

      # expand tabs if a tab character is detected and tab_size > 0
      if tab_size > 0 && lines.any? { |line| line.includes?('\t') }
        full_tab_space = " " * tab_size
        lines.map! do |line|
          if line.empty? || !(tab_idx = line.index('\t'))
            line
          else
            if tab_idx == 0
              leading_tabs = 0
              line.each_byte do |b|
                break unless b == 9_u8
                leading_tabs += 1
              end
              line = "#{full_tab_space * leading_tabs}#{line[leading_tabs..]}"
              next line unless line.includes?('\t')
            end
            spaces_added = 0
            idx = 0
            result = String::Builder.new
            line.each_char do |c|
              if c == '\t'
                offset = idx + spaces_added
                if offset % tab_size == 0
                  spaces_added += tab_size - 1
                  result << full_tab_space
                else
                  spaces = tab_size - offset % tab_size
                  spaces_added += spaces - 1 unless spaces == 1
                  result << (" " * spaces)
                end
              else
                result << c
              end
              idx += 1
            end
            result.to_s
          end
        end
      end

      return if indent_size < 0

      # determine block indent
      block_indent : Int32? = nil
      lines.each do |line|
        next if line.empty?
        line_indent = line.size - line.lstrip.size
        if line_indent == 0
          block_indent = nil
          break
        end
        block_indent = line_indent unless block_indent && block_indent < line_indent
      end

      # remove block indent then apply indent_size
      if indent_size == 0
        lines.map! { |line| line.empty? ? line : line[block_indent..] } if block_indent
      else
        new_block_indent = " " * indent_size
        if block_indent
          lines.map! { |line| line.empty? ? line : "#{new_block_indent}#{line[block_indent..]}" }
        else
          lines.map! { |line| line.empty? ? line : "#{new_block_indent}#{line}" }
        end
      end

      nil
    end

    # Catalog callout markers found in the text.
    def catalog_callouts(text : String, document : Document) : Bool
      found = false
      autonum = 0
      if text.includes?('<')
        text.scan(CalloutScanRx) do |md|
          found = true
          unless md[0].starts_with?("\\")
            num_str = md[2]? || ""
            num = num_str == "." ? (autonum += 1).to_s : num_str
            document.callouts.register(num.to_i)
          end
        end
      end
      found
    end

    # Catalog a matched inline anchor.
    def catalog_inline_anchor(id : String, reftext : String?, node : AbstractBlock, location : Reader | Cursor, doc : Document? = nil) : Nil
      doc = node.document unless doc
      reftext = doc.sub_attributes(reftext) if reftext && reftext.includes?(ATTR_REF_HEAD)
      ref = Inline.new(node, :anchor, reftext, type: :ref, id: id)
      unless doc.register(:refs, {id, ref.as(AbstractNode)})
        cursor = location.is_a?(Reader) ? location.cursor_at_prev_line : location.as(Cursor)
        logger.warn { "id assigned to anchor already in use: #{id}" }
      end
      nil
    end

    # Catalog any inline anchors found in the text (but don't convert).
    def catalog_inline_anchors(text : String, block : AbstractBlock, document : Document, reader : Reader) : Nil
      return unless text.includes?("[[") || text.includes?("or:")
      text.scan(InlineAnchorScanRx) do |md|
        if (id = md[1]?)
          reftext = md[2]?
          if reftext && reftext.includes?(ATTR_REF_HEAD)
            subbed = document.sub_attributes(reftext)
            next if subbed.empty?
            reftext = subbed
          end
        else
          id = md[3]?
          next unless id
          reftext = md[4]?
          if reftext
            if reftext.includes?(']')
              reftext = reftext.gsub("\\]", "]")
              reftext = document.sub_attributes(reftext) if reftext.includes?(ATTR_REF_HEAD)
            elsif reftext.includes?(ATTR_REF_HEAD)
              subbed = document.sub_attributes(reftext)
              reftext = subbed.empty? ? nil : subbed
            end
          end
        end
        ref = Inline.new(block, :anchor, reftext, type: :ref, id: id)
        unless document.register(:refs, {id, ref.as(AbstractNode)})
          logger.warn { "id assigned to anchor already in use: #{id}" }
        end
      end
      nil
    end

    # Catalog the bibliography inline anchor found in the start of the list item.
    def catalog_inline_biblio_anchor(id : String, reftext : String?, node : AbstractBlock, reader : Reader) : Nil
      display_text = reftext ? "[#{reftext}]" : nil
      ref = Inline.new(node, :anchor, display_text, type: :bibref, id: id)
      unless node.document.register(:refs, {id, ref.as(AbstractNode)})
        logger.warn { "id assigned to bibliography anchor already in use: #{id}" }
      end
      nil
    end

    # Check whether the line given is an atx section title.
    def atx_section_title?(line : String) : Int32?
      if line.starts_with?('=') && (m = AtxSectionTitleRx.match(line))
        m[1].size - 1
      elsif COMPLIANCE_MARKDOWN_SYNTAX && line.starts_with?('#') && (m = ExtAtxSectionTitleRx.match(line))
        m[1].size - 1
      else
        nil
      end
    end

    # Determine whether this line is the start of a known delimited block.
    def is_delimited_block?(line : String, return_match_data : Bool = false) : BlockMatchData?
      line_len = line.size
      return nil unless line_len > 1 && DELIMITED_BLOCK_HEADS.has_key?(line[0, 2])

      if line_len == 2
        tip = line
        tip_len = 2
      else
        if line_len < 5
          tip = line
          tip_len = line_len
        else
          tip = line[0, 4]
          tip_len = 4
        end
        # special case for fenced code blocks
        if COMPLIANCE_MARKDOWN_SYNTAX && tip.starts_with?('`')
          if tip_len == 4
            if tip == "````" || (tip = tip[0, 3]) != "```"
              return nil
            end
            line_len = tip_len = 3
          elsif tip != "```"
            return nil
          end
        elsif tip_len == 3
          return nil
        end
      end

      if (entry = DELIMITED_BLOCKS[tip]?)
        context = entry[0]
        masq = entry[1]
        tail_char = DELIMITED_BLOCK_TAILS[tip]?
        if line_len == tip_len || (tail_char && uniform?(line[1..], tail_char, line_len - 1))
          return_match_data ? BlockMatchData.new(context, masq, tip, line) : BlockMatchData.new(context, masq, tip, line)
        else
          nil
        end
      else
        nil
      end
    end

    # Check if the next line on the Reader is the document title.
    def is_next_line_doctitle?(reader : Reader, attributes : Hash(String, String), leveloffset : String?) : Bool
      if leveloffset
        (sect_level = is_next_line_section?(reader, attributes)) != nil && (sect_level.not_nil! + leveloffset.to_i == 0)
      else
        is_next_line_section?(reader, attributes) == 0
      end
    end

    # Check if the next line on the Reader is a section title.
    def is_next_line_section?(reader : Reader, attributes : Hash(String, String)) : Int32?
      style = attributes["1"]?
      return nil if style && (style == "discrete" || style == "float")
      if COMPLIANCE_UNDERLINE_STYLE_SECTION_TITLES
        next_lines = reader.peek_lines(2, style != nil && style == "comment")
        is_section_title?(next_lines[0]? || "", next_lines[1]?)
      else
        atx_section_title?(reader.peek_line || "")
      end
    end

    # Check whether the lines given are a section title (atx or setext).
    def is_section_title?(line1 : String, line2 : String? = nil) : Int32?
      atx_section_title?(line1) || (line2 && !line2.empty? ? setext_section_title?(line1, line2) : nil)
    end

    # Check whether a line is a sibling list item.
    def is_sibling_list_item?(line : String, list_type : Symbol, sibling_trait : String | Regex) : Bool
      case sibling_trait
      when Regex
        sibling_trait.matches?(line)
      when String
        if (m = LIST_RX_MAP[list_type.to_s]?.try(&.match(line)))
          sibling_trait == resolve_list_marker(list_type, m[1])
        else
          false
        end
      else
        false
      end
    end

    # Public: Parses AsciiDoc source read from the Reader into the Document.
    def parse(reader : Reader, document : Document, header_only : Bool = false) : Document
      # Hook: run Preprocessors before parsing
      if document.extensions?
        registry = document.extensions!
        if registry.preprocessors?
          registry.preprocessors.each do |ext|
            preprocessor = ext.instance.as(Extensions::Preprocessor)
            result = preprocessor.process(document, reader)
            reader = result if result
          end
        end
      end

      block_attributes = parse_document_header(reader, document, header_only)

      unless header_only
        while reader.has_more_lines?
          new_section, block_attributes = next_section(reader, document, block_attributes)
          if new_section
            document.assign_numeral(new_section)
            document.blocks << new_section
          end
        end
      end

      # Extract manpage attributes from document title and NAME section
      if document.doctype == "manpage" && document.backend == "manpage"
        extract_manpage_attributes(document)
      end

      # Hook: run TreeProcessors after parsing
      if document.extensions?
        registry = document.extensions!
        if registry.tree_processors?
          registry.tree_processors.each do |ext|
            tree_processor = ext.instance.as(Extensions::TreeProcessor)
            result = tree_processor.process(document)
            # If the tree processor returns a new document, use it
          end
        end
      end

      document
    end

    # Parse blocks from this reader until there are no more lines.
    def parse_blocks(reader : Reader, parent : AbstractBlock, attributes : Hash(String, String)? = nil) : Nil
      attrs = attributes ? attributes.dup : {} of String => String
      while (block = next_block(reader, parent, attrs)) || reader.has_more_lines?
        if block
          # Merge adjacent lists of the same type (ulist, olist, dlist, colist)
          # when they are separated only by blank lines and have no attributes
          # Do NOT merge if a comment was seen between them
          comment_seen = attrs.has_key?("__comment_seen__")
          if !comment_seen && (NESTABLE_LIST_CONTEXTS + [:colist]).includes?(block.context) && !parent.blocks.empty?
            prev = parent.blocks.last
            if prev.is_a?(List) && prev.context == block.context &&
               prev.style == block.as(List).style &&
               prev.attributes.keys.none? { |k| k != "style" } &&
               block.as(List).attributes.keys.none? { |k| k != "style" }
              block.as(List).items.each { |item| prev.items << item }
              attrs = {} of String => String unless attributes
              next
            end
          end
          parent.blocks << block
        end
        attrs = {} of String => String unless attributes
      end
    end

    # Parse and construct a callout list Block from the current position of the Reader.
    def parse_callout_list(reader : Reader, match : Regex::MatchData, parent : AbstractBlock, callouts : Callouts) : List
      list_block = List.new(parent, :colist)
      next_index = 1
      autonum = 0
      first = true
      while first || ((peek = reader.peek_line) && (match_data = CalloutListRx.match(peek)) && reader.mark && (match = match_data))
        first = false
        num_str = match[1]? || ""
        if num_str == "."
          num_str = (autonum += 1).to_s
        end
        unless num_str == next_index.to_s
          logger.warn { "callout list item index: expected #{next_index}, got #{num_str}" }
        end
        item_text = match[2]? || ""
        list_item = ListItem.new(list_block, item_text)
        list_item.marker = "<1>"
        # Read continuation lines for this callout list item
        reader.advance
        while reader.has_more_lines?
          next_line = reader.peek_line
          break unless next_line
          if next_line.empty?
            reader.advance
            reader.skip_blank_lines
            cont_line = reader.peek_line
            break unless cont_line
            if cont_line == LIST_CONTINUATION
              reader.advance
              if (cont_block = next_block(reader, list_item))
                list_item.blocks << cont_block
              end
            elsif CalloutListRx.matches?(cont_line)
              break
            else
              break
            end
          elsif next_line == LIST_CONTINUATION
            reader.advance
            if (cont_block = next_block(reader, list_item))
              list_item.blocks << cont_block
            end
          elsif CalloutListRx.matches?(next_line)
            break
          elsif is_delimited_block?(next_line)
            break
          else
            reader.advance
            list_item.text = "#{list_item.text}\n#{next_line}"
          end
        end
        list_block.items << list_item
        coids = callouts.callout_ids(list_block.items.size)
        if coids.empty?
          logger.warn { "no callout found for <#{list_block.items.size}>" }
        else
          list_item.attributes["coids"] = coids
        end
        next_index += 1
        match = nil.as(Regex::MatchData?)
        break unless reader.has_more_lines?
        peek2 = reader.peek_line
        break unless peek2
        match2 = CalloutListRx.match(peek2)
        break unless match2
        reader.mark
        match = match2
      end
      callouts.next_list
      list_block
    end

    # Parse a cell spec for a table.
    def parse_cellspec(line : String, pos : Symbol = :end, delimiter : String? = nil) : Tuple(Hash(String, String | Int32)?, String)
      if pos == :start
        return {nil, line} unless delimiter && line.includes?(delimiter)
        idx = line.index(delimiter)
        return {nil, line} unless idx
        spec_part = line[0...idx]
        rest = line[(idx + delimiter.size)..]
        m = CellSpecStartRx.match(spec_part)
        return {nil, line} unless m
        return { {} of String => String | Int32, rest} if m[0].empty?
      elsif (m = CellSpecEndRx.match(line))
        if m[0].lstrip.empty?
          return { {} of String => String | Int32, line.rstrip}
        end
        rest = m.pre_match
      else
        # Check if the entire fragment is a spec (no content, no leading space needed)
        # This handles cases like "3*" or "2+" at the start of a fragment
        # But only if the spec contains meaningful elements (colspan, rowspan, alignment, or valid style)
        if (m2 = CellSpecStartRx.match(line.strip)) && !m2[0].empty? && line.strip == m2[0]
          # Verify the match contains meaningful spec elements
          has_span = m2[1]? && m2[2]?  # colspan/rowspan spec like "2+" or "3*"
          has_align = m2[3]?  # alignment like "<", ">", "^"
          has_valid_style = m2[4]? && !m2[4].empty? && TableCellStyles.has_key?(m2[4][0])
          if has_span || has_align || has_valid_style
            m = m2
            rest = ""
          else
            return { {} of String => String | Int32, line}
          end
        else
          return { {} of String => String | Int32, line}
        end
      end
      spec = {} of String => String | Int32
      if m[1]?
        parts = m[1].split('.')
        colspec_str = parts[0]? || ""
        rowspec_str = parts[1]? || ""
        colspec = colspec_str.empty? ? 1 : colspec_str.to_i
        rowspec = rowspec_str.empty? ? 1 : rowspec_str.to_i
        case m[2]?
        when "+"
          spec["colspan"] = colspec unless colspec == 1
          spec["rowspan"] = rowspec unless rowspec == 1
        when "*"
          spec["repeatcol"] = colspec unless colspec == 1
        end
      end
      if (align = m[3]?)
        parts = align.split('.')
        colspec_align = parts[0]? || ""
        rowspec_align = parts[1]? || ""
        if !colspec_align.empty? && colspec_align.size == 1 && TableCellHorzAlignments.has_key?(colspec_align[0])
          spec["halign"] = TableCellHorzAlignments[colspec_align[0]]
        end
        if !rowspec_align.empty? && rowspec_align.size == 1 && TableCellVertAlignments.has_key?(rowspec_align[0])
          spec["valign"] = TableCellVertAlignments[rowspec_align[0]]
        end
      end
      if (style_char = m[4]?) && !style_char.empty? && TableCellStyles.has_key?(style_char[0])
        spec["style"] = style_char
      end
      {spec, rest}
    end

    # Parse the document header.
    def parse_document_header(reader : Reader, document : Document, header_only : Bool = false) : Hash(String, String)
      block_attrs = reader.skip_blank_lines ? parse_block_metadata_lines(reader, document) : {} of String => String
      doc_attrs = document.attributes

      # check for implicit document title
      if is_next_line_doctitle?(reader, block_attrs, doc_attrs["leveloffset"]?) && (block_attrs.has_key?("title") || block_attrs.has_key?("style"))
        doc_attrs["authorcount"] = "0"
        return document.finalize_header(block_attrs, false)
      end

      unless (val = doc_attrs["doctitle"]?).nil? || val.empty?
        document.title = val
      end

      if is_next_line_doctitle?(reader, block_attrs, doc_attrs["leveloffset"]?)
        _sect_id, _, l0_section_title, _, atx = parse_section_title(reader, document)
        if doc_attrs["doctitle"]? && !doc_attrs["doctitle"]?.try(&.empty?)
          l0_section_title = nil
        else
          document.title = l0_section_title
          doc_attrs["doctitle"] = l0_section_title || ""
        end

        if (doc_id = block_attrs["id"]?)
          document.id = doc_id
        end
        if (role = block_attrs["role"]?)
          doc_attrs["role"] = role
        end
        if (reftext = block_attrs["reftext"]?)
          doc_attrs["reftext"] = reftext
        end
        block_attrs.clear
        parse_header_metadata(reader, document)
      elsif (author = doc_attrs["author"]?)
        author_metadata = process_authors(author, true, false)
        doc_attrs.merge!(author_metadata)
      else
        doc_attrs["authorcount"] = "0"
      end

      parse_manpage_header(reader, document, block_attrs, header_only) if document.doctype == "manpage"
      document.finalize_header(block_attrs)
    end

    # Parse the section title from the current position of the reader.
    def parse_section_title(reader : Reader, document : Document, sect_id : String? = nil) : Tuple(String?, String?, String, Int32, Bool)
      sect_reftext = nil
      line1 = reader.read_line.not_nil!

      if line1.starts_with?('=') && (m = AtxSectionTitleRx.match(line1))
        sect_level = m[1].size - 1
        sect_title = m[2]
        atx = true
        if !sect_id && sect_title.ends_with?("]]") && (am = InlineSectionAnchorRx.match(sect_title)) && !am[1]?
          sect_title = sect_title[0, sect_title.size - am[0].size]
          sect_id = am[2]
          sect_reftext = am[3]?
        end
      elsif COMPLIANCE_MARKDOWN_SYNTAX && line1.starts_with?('#') && (m = ExtAtxSectionTitleRx.match(line1))
        sect_level = m[1].size - 1
        sect_title = m[2]
        atx = true
        if !sect_id && sect_title.ends_with?("]]") && (am = InlineSectionAnchorRx.match(sect_title)) && !am[1]?
          sect_title = sect_title[0, sect_title.size - am[0].size]
          sect_id = am[2]
          sect_reftext = am[3]?
        end
      elsif COMPLIANCE_UNDERLINE_STYLE_SECTION_TITLES && (line2 = reader.peek_line(direct: true)) &&
            (line2_ch0 = line2[0]?) && (sect_level = SETEXT_SECTION_LEVELS[line2_ch0]?) &&
            uniform?(line2, line2_ch0.to_s, line2.size) &&
            (m = SetextSectionTitleRx.match(line1)) && (line1.size - line2.size).abs < 2
        sect_title = m[1]
        atx = false
        if !sect_id && sect_title.ends_with?("]]") && (am = InlineSectionAnchorRx.match(sect_title)) && !am[1]?
          sect_title = sect_title[0, sect_title.size - am[0].size]
          sect_id = am[2]
          sect_reftext = am[3]?
        end
        reader.advance
      else
        raise "Unrecognized section at #{reader.cursor_at_prev_line}"
      end

      if (lo = document.attributes["leveloffset"]?)
        sect_level = sect_level.not_nil! + lo.to_i
        sect_level = 0 if sect_level < 0
      end

      {sect_id, sect_reftext, sect_title.not_nil!, sect_level.not_nil!, atx.not_nil!}
    end

    # Parse consecutive lines of block metadata.
    def parse_block_metadata_lines(reader : Reader, document : Document, attributes : Hash(String, String) = {} of String => String) : Hash(String, String)
      while parse_block_metadata_line(reader, document, attributes)
        reader.advance
        # Continue without blank line if next line is also metadata
        next_line = reader.peek_line
        if next_line && (next_line.starts_with?(':') || next_line.starts_with?('[') || next_line.starts_with?('.') || next_line.starts_with?("//"))
          next
        end
        reader.skip_blank_lines || break
      end
      attributes
    end

    # Parse the next line if it contains metadata for the following block.
    def parse_block_metadata_line(reader : Reader, document : Document, attributes : Hash(String, String), text_only : Bool = false) : Bool
      next_line = reader.peek_line
      return false unless next_line

      if text_only
        return false unless next_line.starts_with?('[') || next_line.starts_with?('/')
      else
        return false unless next_line.starts_with?('[') || next_line.starts_with?('.') || next_line.starts_with?('/') || next_line.starts_with?(':')
      end

      if next_line.starts_with?('[')
        if next_line.starts_with?("[[")
          # Skip empty block anchors [[]]
          return true if next_line == "[[]]"
          if next_line.ends_with?("]]")
            if (m = BlockAnchorRx.match(next_line))
              attributes["id"] = m[1]
              if (reftext = m[2]?)
                attributes["reftext"] = reftext
              end
              return true
            end
          end
        elsif next_line.ends_with?(']') && (m = BlockAttributeListRx.match(next_line))
          if (raw = m[1]?) && !raw.empty?
            # Apply attribute substitutions before parsing the attribute list
            raw = document.sub_attributes(raw) if raw.includes?('{')
            parse_block_attribute_list(raw, attributes, document)
          end
          return true
        end
      elsif !text_only && next_line.starts_with?('.')
        if (m = BlockTitleRx.match(next_line))
          attributes["title"] = m[1]
          return true
        end
      elsif next_line.starts_with?("//")
        if next_line == "//"
          attributes["__comment_seen__"] = ""
          return true
        elsif !next_line.starts_with?("///") && next_line.starts_with?("//")
          attributes["__comment_seen__"] = ""
          return true
        elsif uniform?(next_line, "/", next_line.size) && next_line.size > 3
          reader.read_lines_until(terminator: next_line, skip_first_line: true, preserve_last_line: true, skip_processing: true, context: :comment)
          attributes["__comment_seen__"] = ""
          return true
        end
      elsif !text_only && next_line.starts_with?(':') && (m = AttributeEntryRx.match(next_line))
        process_attribute_entry(reader, document, attributes, m)
        return true
      end

      false
    end

    # Parse a block attribute list into a Hash.
    def parse_block_attribute_list(raw : String, attributes : Hash(String, String), block : AbstractBlock? = nil) : Hash(String, String)
      return attributes if raw.empty?
      # Use AttributeList for proper parsing (handles quoted values with commas, etc.)
      al = AttributeList.new(raw, block)
      parsed = al.parse
      parsed.each do |key, value|
        case key
        when Int32
          attributes[key.to_s] = value
        when String
          attributes[key] = value
        end
      end
      # Parse style attribute (shorthand: style#id.role%option)
      if (raw_style = attributes["1"]?) && !raw_style.includes?(' ')
        parse_style_attribute(attributes)
      end
      attributes
    end

    # Parse the style attribute shorthand (style#id.role%option).
    def parse_style_attribute(attributes : Hash(String, String)) : String?
      raw_style = attributes["1"]?
      return nil unless raw_style && !raw_style.includes?(' ')

      name : Symbol? = nil
      accum = String::Builder.new
      parsed_style : String? = nil
      parsed_id : String? = nil
      parsed_roles = [] of String
      parsed_options = [] of String

      raw_style.each_char do |c|
        case c
        when '.'
          flush_shorthand(name, accum.to_s, parsed_style, parsed_id, parsed_roles, parsed_options).try do |ps, pi, pr, po|
            parsed_style, parsed_id, parsed_roles, parsed_options = ps, pi, pr, po
          end
          accum = String::Builder.new
          name = :role
        when '#'
          flush_shorthand(name, accum.to_s, parsed_style, parsed_id, parsed_roles, parsed_options).try do |ps, pi, pr, po|
            parsed_style, parsed_id, parsed_roles, parsed_options = ps, pi, pr, po
          end
          accum = String::Builder.new
          name = :id
        when '%'
          flush_shorthand(name, accum.to_s, parsed_style, parsed_id, parsed_roles, parsed_options).try do |ps, pi, pr, po|
            parsed_style, parsed_id, parsed_roles, parsed_options = ps, pi, pr, po
          end
          accum = String::Builder.new
          name = :option
        else
          accum << c
        end
      end

      if name
        flush_shorthand(name, accum.to_s, parsed_style, parsed_id, parsed_roles, parsed_options).try do |ps, pi, pr, po|
          parsed_style, parsed_id, parsed_roles, parsed_options = ps, pi, pr, po
        end

        # Always remove the positional attribute ("1") after parsing shorthand
        attributes.delete("1")
        if parsed_style
          attributes["style"] = parsed_style
        end
        attributes["id"] = parsed_id if parsed_id
        unless parsed_roles.empty?
          if (existing_role = attributes["role"]?)
            # Roles are additive: append new roles to existing ones
            attributes["role"] = "#{existing_role} #{parsed_roles.join(' ')}"
          else
            attributes["role"] = parsed_roles.join(' ')
          end
        end
        parsed_options.each { |opt| attributes["#{opt}-option"] = "" }
        parsed_style
      else
        attributes["style"] = raw_style
        raw_style
      end
    end

    private def flush_shorthand(name : Symbol?, value : String, style : String?, id : String?, roles : Array(String), options : Array(String)) : Tuple(String?, String?, Array(String), Array(String))?
      return nil if value.empty? && name
      case name
      when :id
        {style, value, roles, options}
      when :role
        roles << value unless value.empty?
        {style, id, roles, options}
      when :option
        options << value unless value.empty?
        {style, id, roles, options}
      else # style (first positional)
        {value.empty? ? style : value, id, roles, options}
      end
    end

    # Parse the header metadata (author line, revision line, attribute entries).
    def parse_header_metadata(reader : Reader, document : Document) : Nil
      doc_attrs = document.attributes
      process_attribute_entries(reader, document)

      if reader.has_more_lines? && !reader.next_line_empty?
        author_metadata = process_authors(reader.read_line.not_nil!)
        if (authorcount = author_metadata["authorcount"]?) && authorcount.to_i > 0
          author_metadata.each do |key, val|
            doc_attrs[key] = val unless doc_attrs.has_key?(key)
          end
        end
        doc_attrs["authorcount"] = authorcount || "0"

        process_attribute_entries(reader, document)

        if reader.has_more_lines? && !reader.next_line_empty?
          rev_line = reader.read_line.not_nil!
          # Don't consume section titles (== NAME, etc.) as revision info
          if is_section_title?(rev_line)
            reader.unshift_line(rev_line)
          elsif (match = RevisionInfoLineRx.match(rev_line))
            rev_metadata_empty = true
            if match[1]?
              doc_attrs["revnumber"] = match[1].rstrip
              rev_metadata_empty = false
            end
            component = match[2]?.try(&.strip) || ""
            unless component.empty?
              rev_metadata_empty = false
              if !match[1]? && component.starts_with?('v')
                doc_attrs["revnumber"] = component[1..]
              else
                doc_attrs["revdate"] = component
              end
            end
            if match[3]?
              doc_attrs["revremark"] = match[3].rstrip
              rev_metadata_empty = false
            end
            reader.unshift_line(rev_line) if rev_metadata_empty
          else
            reader.unshift_line(rev_line)
          end
        end

        process_attribute_entries(reader, document)
        reader.skip_blank_lines
      end

      nil
    end

    # Return the next section from the Reader.
    def next_section(reader : Reader, parent : AbstractBlock, attributes : Hash(String, String) = {} of String => String) : Tuple(Section?, Hash(String, String))
      preamble : Block? = nil
      intro : Block? = nil
      part = false

      if parent.context == :document && parent.blocks.empty?
        document = parent.as(Document)
        book = document.doctype == "book"
        has_header = document.header?
        if has_header || (book && attributes["1"]? != "abstract") || !is_next_line_section?(reader, attributes)
          if has_header || (book && attributes["1"]? != "abstract")
            preamble = intro = Block.new(parent, :preamble, content_model: ContentModel::Compound)
            parent.blocks << preamble
          end
          section = parent
          current_level = 0
          if parent.attributes.has_key?("fragment")
            expected_next_level = -1
          elsif book
            expected_next_level = 1
          else
            expected_next_level = 1
          end
        else
          document = parent.as(Document)
          book = document.doctype == "book"
          section = initialize_section(reader, parent, attributes)
          attributes = attributes.has_key?("title") ? {"title" => attributes["title"]} : {} of String => String
          expected_next_level = (current_level = section.level) + 1
          if current_level == 0
            part = book
          end
        end
      else
        document = parent.document
        book = document.doctype == "book"
        section = initialize_section(reader, parent, attributes)
        attributes = attributes.has_key?("title") ? {"title" => attributes["title"]} : {} of String => String
        expected_next_level = (current_level = section.level) + 1
        if current_level == 0
          part = book
        end
      end

      reader.skip_blank_lines

      while reader.has_more_lines?
        parse_block_metadata_lines(reader, document, attributes)
        if (next_level = is_next_line_section?(reader, attributes))
          if (lo = document.attributes["leveloffset"]?)
            next_level += lo.to_i
            next_level = 0 if next_level < 0
          end
          if next_level > current_level
            new_section, attributes = next_section(reader, section, attributes)
            if new_section
              section.assign_numeral(new_section)
              section.blocks << new_section
            end
          elsif next_level == 0 && section == parent
            new_section, attributes = next_section(reader, section, attributes)
            if new_section
              section.assign_numeral(new_section)
              section.blocks << new_section
            end
          else
            break
          end
        else
          block_cursor = reader.cursor
          if (new_block = next_block(reader, intro || section, attributes))
            target = intro || section
            # Merge adjacent lists of the same type when separated only by blank lines
            # Do NOT merge if a comment or block attribute was seen between them
            comment_seen = attributes.has_key?("__comment_seen__")
            if !comment_seen && (NESTABLE_LIST_CONTEXTS + [:colist]).includes?(new_block.context) && !target.blocks.empty?
              prev_b = target.blocks.last
              if prev_b.is_a?(List) && prev_b.context == new_block.context &&
                 prev_b.style == new_block.as(List).style &&
                 prev_b.attributes.keys.none? { |k| k != "style" } &&
                 new_block.as(List).attributes.keys.none? { |k| k != "style" }
                new_block.as(List).items.each { |item| prev_b.items << item }
                attributes.clear
                next
              end
            end
            target.blocks << new_block
            attributes.clear
          end
        end

        reader.skip_blank_lines || break
      end

      if preamble
        if preamble.blocks?
          # Only keep preamble if there are sections in the document
          has_sections = parent.as(AbstractBlock).blocks.any? { |b| b.is_a?(Section) }
          unless has_sections
            # No sections - move preamble content directly to parent
            preamble.blocks.each { |b| parent.as(AbstractBlock).blocks << b }
            parent.as(AbstractBlock).blocks.delete(preamble)
          end
        else
          parent.as(AbstractBlock).blocks.delete(preamble)
        end
      end

      {section == parent ? nil : section.as(Section), attributes.dup}
    end

    # Parse and return the next Block at the Reader's current location.
    def next_block(reader : Reader, parent : AbstractBlock, attributes : Hash(String, String) = {} of String => String, parse_metadata : Bool = true, text_only : Bool = false) : AbstractBlock?
      skipped = reader.skip_blank_lines
      return nil unless skipped
      # If skipped blank/placeholder lines, assume list continuation was used and block content is acceptable
      text_only = false if text_only && skipped > 0
      document = parent.document
      if parse_metadata
        while parse_block_metadata_line(reader, document, attributes, text_only)
          reader.advance
          # Continue without blank line if next line is also metadata
          next_line = reader.peek_line
          if next_line && (next_line.starts_with?(':') || next_line.starts_with?('[') || next_line.starts_with?('.') || next_line.starts_with?("//"))
            next
          end
          # If no blank line but content follows, continue to parse the block
          skipped2 = reader.skip_blank_lines
          return nil unless skipped2 || reader.has_more_lines?
          break unless skipped2
        end
      end

      reader.mark
      this_line = reader.read_line
      return nil unless this_line

      # Ignore a lone list continuation (+) outside of a list context
      if this_line == LIST_CONTINUATION && !parent.is_a?(ListItem)
        return nil
      end

      doc_attrs = document.attributes
      style = attributes["1"]? || attributes["style"]?
      block : AbstractBlock? = nil
      block_context : Symbol? = nil
      cloaked_context : Symbol? = nil
      terminator : String? = nil

      if (delimited_block = is_delimited_block?(this_line, true))
        block_context = cloaked_context = delimited_block.context
        terminator = delimited_block.terminator
        if style
          # Convert hardbreaks to an option before style processing
          if style == "hardbreaks"
            attributes["hardbreaks-option"] = ""
            attributes.delete("1")
            attributes.delete("style")
            style = nil
          end
          if style
            unless style == block_context.to_s
              if delimited_block.masq.includes?(style)
                block_context = string_to_block_context(style) || block_context
              elsif delimited_block.masq.includes?("admonition") && ADMONITION_STYLES.includes?(style)
                block_context = :admonition
              else
                style = block_context.to_s
              end
            end
          else
            style = block_context.to_s
            attributes["style"] = style
          end
        else
          style = block_context.to_s
          attributes["style"] = style
        end
      end

      # Process non-delimited blocks
      unless delimited_block
        indented = this_line.starts_with?(' ') || this_line.starts_with?(TAB)
        ch0 = this_line[0]?

        # Check for indented list markers before treating as literal paragraph
        if indented && style != "normal"
          if (m = UnorderedListRx.match(this_line))
            reader.unshift_line(this_line)
            block = parse_list(reader, :ulist, parent, attributes)
            return finalize_block(block, document, reader, attributes, style)
          elsif (m = OrderedListRx.match(this_line))
            reader.unshift_line(this_line)
            block = parse_list(reader, :olist, parent, attributes)
            return finalize_block(block, document, reader, attributes, style)
          elsif (this_line.includes?("::") || this_line.includes?(";;" )) && (m = DescriptionListRx.match(this_line))
            reader.unshift_line(this_line)
            block = parse_description_list(reader, parent, attributes)
            return finalize_block(block, document, reader, attributes, style)
          end
        end

        unless indented
          # Check for layout breaks
          if ch0 && LAYOUT_BREAK_CHARS.has_key?(ch0.to_s) && uniform?(this_line, ch0.to_s, this_line.size) && this_line.size > 2
            block = Block.new(parent, LAYOUT_BREAK_CHARS[ch0.to_s], content_model: ContentModel::Empty)
            return finalize_block(block, document, reader, attributes, style)
          end

          # Check for discrete (floating) headings
          if (style == "discrete" || style == "float") && (ch0 == '=' || (COMPLIANCE_MARKDOWN_SYNTAX && ch0 == '#'))
            if (sect_level = atx_section_title?(this_line))
              # Parse the title from the ATX heading line
              if (m = AtxSectionTitleRx.match(this_line)) || (COMPLIANCE_MARKDOWN_SYNTAX && (m = ExtAtxSectionTitleRx.match(this_line)))
                float_title = m[2]
                # Apply attribute substitutions to the title
                if float_title.includes?(ATTR_REF_HEAD)
                  float_title = document.sub_attributes(float_title)
                end
                float_id = attributes["id"]?
                block = Block.new(parent, :floating_title, content_model: ContentModel::Empty)
                block.title = float_title
                block.level = sect_level
                block.style = style
                if float_id
                  block.id = float_id
                elsif document.attributes.has_key?("sectids")
                  block.id = Section.generate_id(float_title, document)
                end
                return finalize_block(block, document, reader, attributes, style)
              end
            end
          end

          # Check for block macros
          if this_line.ends_with?(']') && this_line.includes?("::")

            # Hook: check for BlockMacroProcessor extensions
            if document.extensions?
              registry = document.extensions!
              if registry.block_macros?
                if (bm_match = CustomBlockMacroRx.match(this_line))
                  macro_name = bm_match[1]
                  if (ext = registry.find_block_macro_extension(macro_name))
                    macro_target = bm_match[2]? || ""
                    raw_attrs = bm_match[3]? || ""
                    macro_attrs = {} of String => String
                    parse_block_attribute_list(raw_attrs, macro_attrs) unless raw_attrs.empty?
                    processor = ext.instance.as(Extensions::BlockMacroProcessor)
                    result = processor.process(parent, macro_target, macro_attrs)
                    if result.is_a?(AbstractBlock)
                      return finalize_block(result, document, reader, attributes, style)
                    end
                  end
                end
              end
            end

            if (ch0 == 'i' || this_line.starts_with?("video:") || this_line.starts_with?("audio:")) && (m = BlockMediaMacroRx.match(this_line))
              blk_ctx = string_to_block_context(m[1]) || :image
              target = m[2]
              block = Block.new(parent, blk_ctx, content_model: ContentModel::Empty)
              attributes["target"] = target
              # Parse macro attributes from the bracket content using AttributeList
              raw_attrs = m[3]? || ""
              # Apply attribute substitutions if needed
              if raw_attrs.includes?(ATTR_REF_HEAD)
                raw_attrs = document.sub_attributes(raw_attrs)
              end
              unless raw_attrs.empty?
                al = AttributeList.new(raw_attrs)
                parsed = al.parse
                parsed.each do |k, v|
                  key = k.is_a?(Int32) ? k.to_s : k.as(String)
                  # Macro attributes override block attributes (positional attrs 1,2,3 and named attrs)
                  attributes[key] = v
                end
              end
              # Map positional attributes for image/video/audio
              if blk_ctx == :image
                if !attributes.has_key?("alt")
                  attributes["alt"] = (attributes.delete("1") || File.basename(target, File.extname(target))).tr("-_", " ")
                else
                  attributes.delete("1")
                end
                if attributes.has_key?("2") && !attributes.has_key?("width")
                  attributes["width"] = attributes.delete("2").not_nil!
                end
                if attributes.has_key?("3") && !attributes.has_key?("height")
                  attributes["height"] = attributes.delete("3").not_nil!
                end
              elsif blk_ctx == :video
                if attributes.has_key?("1") && !attributes.has_key?("poster")
                  attributes["poster"] = attributes.delete("1").not_nil!
                end
                if attributes.has_key?("2") && !attributes.has_key?("width")
                  attributes["width"] = attributes.delete("2").not_nil!
                end
                if attributes.has_key?("3") && !attributes.has_key?("height")
                  attributes["height"] = attributes.delete("3").not_nil!
                end
              end
              return finalize_block(block, document, reader, attributes, style)
            elsif ch0 == 't' && this_line.starts_with?("toc:") && BlockTocMacroRx.matches?(this_line)
              block = Block.new(parent, :toc, content_model: ContentModel::Empty)
              return finalize_block(block, document, reader, attributes, style)
            end
          end

          # Check for lists
          if (m = UnorderedListRx.match(this_line))
            reader.unshift_line(this_line)
            block = parse_list(reader, :ulist, parent, attributes)
            return finalize_block(block, document, reader, attributes, style)
          elsif (m = OrderedListRx.match(this_line))
            reader.unshift_line(this_line)
            block = parse_list(reader, :olist, parent, attributes)
            return finalize_block(block, document, reader, attributes, style)
          elsif (this_line.includes?("::") || this_line.includes?(";;")) && (m = DescriptionListRx.match(this_line))
            reader.unshift_line(this_line)
            block = parse_description_list(reader, parent, attributes)
            return finalize_block(block, document, reader, attributes, style)
          elsif (m = CalloutListRx.match(this_line))
            reader.unshift_line(this_line)
            block = parse_list(reader, :colist, parent, attributes)
            return finalize_block(block, document, reader, attributes, style)
          end

          # Check for admonition paragraph
          if ch0 && ADMONITION_STYLE_HEADS.includes?(ch0) && this_line.includes?(':') && (m = AdmonitionParagraphRx.match(this_line))
            reader.unshift_line(this_line)
            lines = read_paragraph_lines(reader)
            lines[0] = this_line[(m[0].size)..]
            admonition_name = m[1].downcase
            attributes["style"] = m[1]
            attributes["name"] = admonition_name
            attributes["textlabel"] = doc_attrs["#{admonition_name}-caption"]? || m[1]
            block = Block.new(parent, :admonition, content_model: ContentModel::Simple, source: lines)
            return finalize_block(block, document, reader, attributes, style)
          end
        end

        # Normal or literal paragraph
        reader.unshift_line(this_line)
        # If style is comment, skip the paragraph
        if style == "comment"
          read_paragraph_lines(reader, text_only)
          attributes.clear
          return nil
        end
        if indented && style != "normal" && !text_only
          lines = read_paragraph_lines(reader, text_only)
          adjust_indentation!(lines)
          block = Block.new(parent, :literal, content_model: ContentModel::Verbatim, source: lines)
        else
          lines = read_paragraph_lines(reader, text_only)
          if indented && style == "normal"
            adjust_indentation!(lines)
          end
          # Markdown-style quote block: lines starting with '> '
          if !text_only && ch0 == '>' && this_line.starts_with?("\> ")
            lines.map! { |line| line == ">" ? line[1..] : (line.starts_with?("\> ") ? line[2..] : line) }
            credit_line = nil
            if !lines.empty? && lines[-1].starts_with?("-- ")
              credit_line = lines.pop[3..]
              while !lines.empty? && lines[-1].empty?
                lines.pop
              end
            end
            attributes["style"] = "quote"
            block_reader = Reader.new(lines)
            quote_block = Block.new(parent, :quote, content_model: ContentModel::Compound)
            parse_blocks(block_reader, quote_block)
            block = quote_block
            if credit_line
              parts = credit_line.split(", ", 2)
              attributes["attribution"] = parts[0] unless parts[0].empty?
              attributes["citetitle"] = parts[1] if parts.size > 1
            end
          # Quoted paragraph-style quote block: starts with '"', ends with '"' then '-- '
          elsif !text_only && ch0 == '"' && lines.size > 1 && lines[-1].starts_with?("-- ") && lines[-2].ends_with?('"')
            lines[0] = this_line[1..] # strip leading quote
            credit_line = lines.pop[3..]
            while !lines.empty? && lines[-1].empty?
              lines.pop
            end
            lines[-1] = lines[-1][..-2] # strip trailing quote
            attributes["style"] = "quote"
            block = Block.new(parent, :quote, content_model: ContentModel::Simple, source: lines)
            parts = credit_line.split(", ", 2)
            attributes["attribution"] = parts[0] unless parts[0].empty?
            attributes["citetitle"] = parts[1] if parts.size > 1
          elsif style && VERBATIM_STYLES.includes?(style)
            # Restyle paragraph as verbatim block based on style attribute
            case style
            when "literal"
              block = Block.new(parent, :literal, content_model: ContentModel::Verbatim, source: lines)
            when "listing"
              block = Block.new(parent, :listing, content_model: ContentModel::Verbatim, source: lines)
            when "source"
              block = Block.new(parent, :listing, content_model: ContentModel::Verbatim, source: lines)
              attributes["style"] = "source"
              unless attributes.has_key?("language")
                if (lang = attributes["2"]?) && !lang.empty?
                  attributes["language"] = lang
                elsif (src_lang = doc_attrs["source-language"]?)
                  attributes["language"] = src_lang
                end
              end
            when "verse"
              block = Block.new(parent, :verse, content_model: ContentModel::Verbatim, source: lines)
            else
              block = Block.new(parent, :paragraph, content_model: ContentModel::Simple, source: lines)
            end
          else
            block = Block.new(parent, :paragraph, content_model: ContentModel::Simple, source: lines)
          end
        end
        return finalize_block(block, document, reader, attributes, style)
      end

      # Process delimited blocks
      case block_context
      when :listing, :source
        # Promote listing block to source if no explicit style but has a second positional argument (language)
        if block_context == :source
          # :source block - map positional attrs
          unless attributes.has_key?("language")
            if (lang = attributes["2"]?) && !lang.empty?
              attributes["language"] = lang
            elsif (src_lang = doc_attrs["source-language"]?)
              attributes["language"] = src_lang
            end
          end
        else
          # :listing block - promote to source if attr[1] is empty/nil and attr[2] is set
          attr1 = attributes["1"]?
          if (attr1.nil? || attr1.empty?) && (lang = attributes["2"]?) && !lang.empty?
            style = "source"
            attributes["style"] = "source"
            attributes["language"] = lang
          end
        end
        block = build_block(:listing, ContentModel::Verbatim, terminator, parent, reader, attributes)
      when :fenced_code
        style = "source"
        attributes["style"] = "source"
        # Extract language from the fenced code block delimiter line (e.g. ```ruby or ```ruby,numbered)
        if this_line && this_line.size > 3
          lang_part = this_line[3..].lstrip
          unless lang_part.empty?
            if (comma_idx = lang_part.index(','))
              if comma_idx > 0
                language = lang_part[0, comma_idx].strip
                attributes["linenums"] = "" if comma_idx < lang_part.size - 1
              else
                attributes["linenums"] = ""
                language = nil
              end
            else
              language = lang_part
            end
            attributes["language"] = language if language && !language.empty?
          end
        end
        unless attributes.has_key?("language")
          if (src_lang = doc_attrs["source-language"]?)
            attributes["language"] = src_lang
          end
        end
        term = terminator.not_nil!
        term = term[0, 3] if term.size > 3
        block = build_block(:listing, ContentModel::Verbatim, term, parent, reader, attributes)
      when :table
        block_cursor = reader.cursor
        # Determine format from delimiter if not explicitly set
        if !attributes.has_key?("format") && terminator
          case terminator[0]?
          when ','
            attributes["format"] = "csv"
          when ':'
            attributes["format"] = "dsv"
          when '!'
            attributes["format"] = "psv"
          end
        end
        table_lines = reader.read_lines_until(terminator: terminator, skip_line_comments: true, context: :table)
        block_reader = Reader.new(table_lines, block_cursor)
        block = parse_table(block_reader, parent, attributes)
      when :sidebar
        block = build_block(:sidebar, ContentModel::Compound, terminator, parent, reader, attributes)
      when :admonition
        admonition_name = (style || "note").downcase
        attributes["name"] = admonition_name
        attributes["textlabel"] = doc_attrs["#{admonition_name}-caption"]? || (style || "Note")
        block = build_block(:admonition, ContentModel::Compound, terminator, parent, reader, attributes)
      when :open, :abstract, :partintro
        block = build_block(:open, ContentModel::Compound, terminator, parent, reader, attributes)
      when :literal
        block = build_block(:literal, ContentModel::Verbatim, terminator, parent, reader, attributes)
      when :example
        block = build_block(:example, ContentModel::Compound, terminator, parent, reader, attributes)
      when :quote
        # Map positional attributes 2 and 3 to attribution and citetitle
        attributes["attribution"] = attributes["2"] if attributes.has_key?("2") && !attributes.has_key?("attribution")
        attributes["citetitle"] = attributes["3"] if attributes.has_key?("3") && !attributes.has_key?("citetitle")
        block = build_block(:quote, ContentModel::Compound, terminator, parent, reader, attributes)
      when :verse
        # Map positional attributes 2 and 3 to attribution and citetitle
        attributes["attribution"] = attributes["2"] if attributes.has_key?("2") && !attributes.has_key?("attribution")
        attributes["citetitle"] = attributes["3"] if attributes.has_key?("3") && !attributes.has_key?("citetitle")
        block = build_block(:verse, ContentModel::Verbatim, terminator, parent, reader, attributes)
      when :stem, :latexmath, :asciimath
        block = build_block(:stem, ContentModel::Raw, terminator, parent, reader, attributes)
      when :pass
        block = build_block(:pass, ContentModel::Raw, terminator, parent, reader, attributes)
      when :comment
        build_block(:comment, ContentModel::Skip, terminator, parent, reader, attributes)
        attributes.clear
        return nil
      else
        block = Block.new(parent, block_context || :paragraph, content_model: ContentModel::Simple)
      end

      return nil unless block
      finalize_block(block, document, reader, attributes, style)
    end

    # Finalize a block: assign source_location, title, caption, style, id.
    private def finalize_block(block : AbstractBlock, document : Document, reader : Reader, attributes : Hash(String, String), style : String?) : AbstractBlock
      block.source_location = reader.cursor_at_mark.to_source_location if document.sourcemap?
      if (title = attributes.delete("title"))
        block.title = title
        if CAPTION_ATTRIBUTE_NAMES.has_key?(block.context.to_s)
          block.assign_caption(attributes.delete("caption"))
        end
      end
      effective_style = style || attributes["style"]? || block.style
      # Convert hardbreaks style to hardbreaks-option (Ruby AsciiDoctor behavior)
      if effective_style == "hardbreaks"
        attributes["hardbreaks-option"] = ""
        effective_style = nil
        attributes.delete("style")
        attributes.delete("1")
      end
      block.style = effective_style
      if (block_id = attributes["id"]?)
        block.id = block_id
      end
      # Expand options attribute into individual -option attributes
      if (opts_val = attributes.delete("options"))
        opts_val.split(',').each do |opt|
          opt = opt.strip
          attributes["#{opt}-option"] = "" unless opt.empty?
        end
      end
      block.update_attributes(attributes) unless attributes.empty?
      # Resolve substitutions based on content model and custom subs attribute
      block.commit_subs if block.responds_to?(:commit_subs)
      block
    end

    # Build a block from delimited content.
    def build_block(block_context : Symbol, content_model : ContentModel, terminator : String?, parent : AbstractBlock, reader : Reader, attributes : Hash(String, String)) : Block?
      case content_model
      when ContentModel::Skip
        if terminator
          reader.read_lines_until(terminator: terminator, skip_processing: true, context: block_context)
        end
        return nil
      when ContentModel::Raw
        lines = if terminator
                  reader.read_lines_until(terminator: terminator, skip_processing: false, context: block_context)
                else
                  read_paragraph_lines(reader)
                end
        block = Block.new(parent, block_context, content_model: content_model, source: lines)
      when ContentModel::Verbatim
        lines = if terminator
                  reader.read_lines_until(terminator: terminator, skip_processing: false, context: block_context)
                else
                  reader.read_lines_until(break_on_blank_lines: true, break_on_list_continuation: true)
                end
        tab_size = (attributes["tabsize"]? || parent.document.attributes["tabsize"]?).try(&.to_i) || 0
        if (indent = attributes["indent"]?)
          adjust_indentation!(lines, indent.to_i, tab_size)
        elsif tab_size > 0
          adjust_indentation!(lines, -1, tab_size)
        end
        block = Block.new(parent, block_context, content_model: content_model, source: lines)
      when ContentModel::Compound
        lines = nil.as(Array(String)?)
        if terminator
          block_cursor = reader.cursor
          block_lines = reader.read_lines_until(terminator: terminator, skip_processing: false, context: block_context)
          block_reader = Reader.new(block_lines, block_cursor)
          block = Block.new(parent, block_context, content_model: content_model)
          parse_blocks(block_reader, block)
        else
          block = Block.new(parent, block_context, content_model: content_model)
        end
      else # Simple
        lines = if terminator
                  reader.read_lines_until(terminator: terminator, context: block_context)
                else
                  read_paragraph_lines(reader)
                end
        block = Block.new(parent, block_context, content_model: content_model, source: lines)
      end

      block
    end

    # Extract manpage-specific attributes from the document title and NAME section.
    # In Ruby Asciidoctor, the manpage doctype extracts manvolnum, manname, mantitle,
    # and manpurpose from the document title (e.g., "command (1)") and the NAME section.
    def extract_manpage_attributes(document : Document) : Nil
      # Extract manvolnum from document title: "command (1)" -> manvolnum=1
      if (doctitle = document.doctitle) && (m = doctitle.match(/^(.+?)\s*\((\w+)\)$/))
        mantitle = m[1].strip.downcase
        manvolnum = m[2]
        document.attributes["mantitle"] = mantitle
        document.attributes["manvolnum"] = manvolnum
        document.attributes["outfilesuffix"] = ".#{manvolnum}"
      end

      # Set filetype attributes
      document.attributes["filetype"] = "man"
      document.attributes["filetype-man"] = ""

      # Extract manname and manpurpose from the NAME section
      # The NAME section should contain: "command - does stuff"
      name_section = document.sections.find { |s| s.title.to_s.upcase == "NAME" }
      if name_section
        # Look for a paragraph in the NAME section
        name_section.blocks.each do |block|
          if block.is_a?(Block) && block.context == :paragraph
            text = block.source
            if text && (dash_idx = text.index(" - "))
              manname = text[0...dash_idx].strip
              manpurpose = text[(dash_idx + 3)..].strip
              document.attributes["manname"] = manname
              document.attributes["manpurpose"] = manpurpose
              # If mantitle was not set from doctitle, use manname
              document.attributes["mantitle"] ||= manname.downcase
            end
          end
        end
      end
    end

    # Initialize a new Section from the reader.
    def initialize_section(reader : Reader, parent : AbstractBlock, attributes : Hash(String, String) = {} of String => String) : Section
      document = parent.document
      reader.mark if document.sourcemap?
      book = document.doctype == "book"
      sect_style = attributes["1"]?
      sect_id, sect_reftext, sect_title, sect_level, _sect_atx = parse_section_title(reader, document, attributes["id"]?)

      sect_name = "section"
      sect_special = false
      sect_numbered = false

      if sect_style
        if book && sect_style == "abstract"
          sect_name = "chapter"
          sect_level = 1
        elsif sect_style.starts_with?("sect") && SectionLevelStyleRx.matches?(sect_style)
          sect_name = "section"
        else
          sect_name = sect_style
          sect_special = true
          sect_level = 1 if sect_level == 0
          sect_numbered = sect_name == "appendix"
        end
      elsif book
        sect_name = sect_level == 0 ? "part" : (sect_level > 1 ? "section" : "chapter")
      end

      section = Section.new(document, parent, sect_level)
      section.id = sect_id
      section.title = sect_title
      section.sectname = sect_name
      if sect_special
        section.special = true
        section.numbered = true if sect_numbered
      elsif document.attributes.has_key?("sectnums") && sect_level > 0
        section.numbered = true
      end


      if (reftext = sect_reftext || attributes["reftext"]?)
        section.attributes["reftext"] = reftext
      end

      # Apply attribute substitutions to the section title
      if sect_title.includes?(ATTR_REF_HEAD)
        sect_title = document.sub_attributes(sect_title)
        section.title = sect_title
      end

      # Generate an ID if one was not provided
      if (id = section.id)
        section.id = nil if id.empty?
      elsif document.attributes.has_key?("sectids")
        section.id = Section.generate_id(sect_title, document)
      end

      # Register the section in the document catalog for ID deduplication and xrefs
      if (sect_id_val = section.id)
        document.register(:refs, {sect_id_val, section.as(AbstractNode)})
      end

      section.update_attributes(attributes) unless attributes.empty?
      section.source_location = reader.cursor_at_mark.to_source_location if document.sourcemap?
      reader.skip_blank_lines
      section
    end
    # Parse a list (unordered, ordered, or callout).
    def parse_list(reader : Reader, list_type : Symbol, parent : AbstractBlock, attributes : Hash(String, String) = {} of String => String, start : String? = nil) : List
      list = List.new(parent, list_type)
      list.attributes.merge!(attributes)

      if list_type == :olist && start
        list.attributes["start"] = start
      end

      list_rx = LIST_RX_MAP[list_type.to_s]? || UnorderedListRx
      style = list.attributes["style"]?

      while reader.has_more_lines?
        line = reader.peek_line
        break unless line
        m = list_rx.match(line)
        break unless m
        sibling_trait = resolve_list_marker(list_type, m[1])
        if (list_item = parse_list_item(reader, list, m, sibling_trait, style))
          list.items << list_item
        end
        reader.skip_blank_lines || break
      end

      list
    end

    # Parse and construct the next ListItem for the specified list Block.
    def parse_list_item(reader : Reader, list_block : List, match : Regex::MatchData, sibling_trait : String | Regex, style : String? = nil) : ListItem
      list_type = list_block.context
      dlist = list_type == :dlist
      has_text = true

      if dlist
        # For description lists, match[1] is the term, match[3] is the description
        term_text = match[1]
        item_text = match[3]?
        has_text = !(item_text.nil? || item_text.empty?)
        list_item = ListItem.new(list_block, item_text)
        list_term = ListItem.new(list_block, term_text)
        if term_text.starts_with?("[[") && (am = LeadingInlineAnchorRx.match(term_text))
          catalog_inline_anchor(am[1], am[2]?, list_term, reader)
        end
      else
        item_text = match[2]
        list_item = ListItem.new(list_block, item_text)
        list_item.source_location = reader.cursor.to_source_location if list_block.document.sourcemap?
        case list_type
        when :ulist
          list_item.marker = sibling_trait.to_s
          if item_text.starts_with?('[')
            if style && style == "bibliography"
              if (bm = InlineBiblioAnchorRx.match(item_text))
                catalog_inline_biblio_anchor(bm[1], bm[2]?, list_item, reader)
              end
            elsif item_text.starts_with?("[[")
              if (am = LeadingInlineAnchorRx.match(item_text))
                catalog_inline_anchor(am[1], am[2]?, list_item, reader)
              end
            elsif item_text.starts_with?("[ ] ") || item_text.starts_with?("[x] ") || item_text.starts_with?("[*] ")
              list_block.attributes["checklist-option"] = ""
              list_item.attributes["checkbox"] = ""
              list_item.attributes["checked"] = "" unless item_text.starts_with?("[ ")
              list_item.text = item_text[4..]
            end
          end
        when :olist
          first = list_block.items.empty?
          ordinal = list_block.items.size
          validate = true
          if (list_start = list_block.attributes["start"]?)
            ordinal += list_start.to_i - 1
          elsif first && (list_start_val = resolve_ordered_list_start(sibling_trait.to_s)) != 1
            list_block.attributes["start"] = list_start_val.to_s
            ordinal += list_start_val - 1
            validate = false
          end
          resolved_marker, implicit_style = resolve_ordered_list_marker(sibling_trait.to_s, ordinal, validate, reader)
          sibling_trait = resolved_marker
          list_item.marker = resolved_marker
          if first && !style
            # Style based on marker length (for . markers) or implicit style from resolve_ordered_list_marker
            computed_style = implicit_style || ORDERED_LIST_STYLES[(resolved_marker.size - 1) % ORDERED_LIST_STYLES.size]
            list_block.style = computed_style.to_s
          end
          if item_text.starts_with?("[[") && (am = LeadingInlineAnchorRx.match(item_text))
            catalog_inline_anchor(am[1], am[2]?, list_item, reader)
          end
        else # :colist
          list_item.marker = sibling_trait.to_s
          if item_text.starts_with?("[[") && (am = LeadingInlineAnchorRx.match(item_text))
            catalog_inline_anchor(am[1], am[2]?, list_item, reader)
          end
        end
      end

      # Read continuation lines for this list item
      reader.shift
      block_cursor = reader.cursor
      item_lines = read_lines_for_list_item(reader, list_type, sibling_trait, has_text)
      list_item_reader = Reader.new(item_lines, block_cursor)
      if list_item_reader.has_more_lines?
        comment_lines = list_item_reader.skip_line_comments
        if (subsequent_line = list_item_reader.peek_line)
          list_item_reader.unshift_lines(comment_lines) unless comment_lines.empty?
          unless subsequent_line.empty?
            content_adjacent = true
            # treat lines as paragraph text if continuation does not connect first block
            has_text = nil unless dlist
          end
        end
        # text_only: true when content_adjacent (has_text = nil) to prevent block title interpretation
        first_text_only = !has_text
        if (block = next_block(list_item_reader, list_item, text_only: first_text_only))
          list_item.blocks << block
        end
        while list_item_reader.has_more_lines?
          if (block = next_block(list_item_reader, list_item))
            list_item.blocks << block
          end
        end
        list_item.fold_first if content_adjacent && (first_block = list_item.blocks[0]?) && first_block.is_a?(Block) && first_block.context == :paragraph
      end
      list_item
    end

    # Parse the manpage-specific header metadata.
    def parse_manpage_header(reader : Reader, document : Document, block_attributes : Hash(String, String), header_only : Bool = false) : Nil
      doc_attrs = document.attributes
      if (doctitle = doc_attrs["doctitle"]?) && (m = ManpageTitleVolnumRx.match(doctitle))
        manvolnum = m[2]
        mantitle = m[1]
        mantitle = document.sub_attributes(mantitle) if mantitle.includes?(ATTR_REF_HEAD)
        doc_attrs["manvolnum"] = manvolnum
        doc_attrs["mantitle"] = mantitle.downcase
      else
        logger.error { "non-conforming manpage title" }
        doc_attrs["mantitle"] = doc_attrs["doctitle"]? || doc_attrs["docname"]? || "command"
        doc_attrs["manvolnum"] = manvolnum = "1"
      end
      if (manname = doc_attrs["manname"]?) && doc_attrs["manpurpose"]?
        doc_attrs["manname-title"] ||= "Name"
        doc_attrs["mannames"] = manname
        if document.attributes["backend"]? == "manpage"
          doc_attrs["docname"] = manname
          doc_attrs["outfilesuffix"] = ".#{manvolnum}"
        end
      elsif header_only
        # done
      else
        reader.skip_blank_lines
        reader.save
        block_attributes.merge!(parse_block_metadata_lines(reader, document))
        if (name_section_level = is_next_line_section?(reader, {} of String => String))
          if name_section_level == 1
            name_section = initialize_section(reader, document, {} of String => String)
            name_section_buffer = reader.read_lines_until(break_on_blank_lines: true, skip_line_comments: true, preserve_last_line: true) { |line| !is_section_title?(line).nil? }.map(&.lstrip).join(' ')
            if (npm = ManpageNamePurposeRx.match(name_section_buffer))
              manname = npm[1]
              manname = document.sub_attributes(manname) if manname.includes?(ATTR_REF_HEAD)
              if manname.includes?(',')
                mannames = manname.split(',').map(&.lstrip)
                manname = mannames[0]
              else
                mannames = [manname]
              end
              manpurpose = npm[2]
              manpurpose = document.sub_attributes(manpurpose) if manpurpose.includes?(ATTR_REF_HEAD)
              doc_attrs["manname-title"] ||= name_section.title || "Name"
              doc_attrs["manname-id"] = name_section.id.to_s if name_section.id
              doc_attrs["manname"] = manname
              doc_attrs["mannames"] = mannames.join(", ")
              doc_attrs["manpurpose"] = manpurpose
              if document.attributes["backend"]? == "manpage"
                doc_attrs["docname"] = manname
                doc_attrs["outfilesuffix"] = ".#{manvolnum}"
              end
              reader.discard_save
            else
              reader.restore_save
              logger.error { "non-conforming name section body" }
              doc_attrs["manname"] = manname = doc_attrs["docname"]? || "command"
              doc_attrs["mannames"] = manname
            end
          else
            reader.restore_save
            logger.error { "name section must be at level 1" }
            doc_attrs["manname"] = manname = doc_attrs["docname"]? || "command"
            doc_attrs["mannames"] = manname
          end
        else
          reader.restore_save
          logger.error { "name section expected" }
          doc_attrs["manname"] = manname = doc_attrs["docname"]? || "command"
          doc_attrs["mannames"] = manname
        end
      end
      nil
    end

    # Parse a description list.
    def parse_description_list(reader : Reader, parent : AbstractBlock, attributes : Hash(String, String) = {} of String => String) : List
      parse_description_list_at_level(reader, parent, attributes, "::")
    end

    # Parse a description list at a given delimiter level.
    # Handles nesting: when a deeper delimiter is encountered, a nested dlist is created.
    private def parse_description_list_at_level(reader : Reader, parent : AbstractBlock, attributes : Hash(String, String), current_delimiter : String) : List
      list = List.new(parent, :dlist)
      list.attributes.merge!(attributes)

      while reader.has_more_lines?
        line = reader.peek_line
        break unless line

        unless (m = DescriptionListRx.match(line))
          break
        end

        delimiter = m[2]

        # If delimiter is shorter than current level, we're done with this list
        if delimiter.size < current_delimiter.size
          break
        end

        # If delimiter is deeper than current level, create a nested list
        # (this shouldn't happen at the start, but handle gracefully)
        if delimiter.size > current_delimiter.size
          # Create a nested list and attach it to the last term's description
          nested_list = parse_description_list_at_level(reader, list, {} of String => String, delimiter)
          # Attach nested list to the last description item if possible
          if !list.items.empty?
            last_item = list.items.last
            if last_item.is_a?(ListItem)
              last_item.blocks << nested_list
            end
          else
            # No parent item yet, just add the nested list directly
            list.items << nested_list
          end
          next
        end

        # Same level: consume the line and create the term
        reader.advance
        term_text = m[1]
        desc_text = m[3]?

        term = ListItem.new(list, term_text)
        term.marker = current_delimiter
        desc : ListItem? = nil

        if desc_text && !desc_text.empty?
          desc = ListItem.new(list, desc_text)
          desc.marker = "desc"
        else
          # Check if next line is a deeper delimiter (nested list)
          reader.skip_blank_lines
          if reader.has_more_lines?
            next_line = reader.peek_line
            if next_line
              if (nm = DescriptionListRx.match(next_line)) && nm[2].size > current_delimiter.size
                # Next item is a nested list - create it as the description
                nested_list = parse_description_list_at_level(reader, list, {} of String => String, nm[2])
                desc = ListItem.new(list, "")
                desc.marker = "desc"
                desc.blocks << nested_list
              elsif !next_line.empty? && !DescriptionListRx.matches?(next_line) && !is_delimited_block?(next_line)
                reader.advance
                desc = ListItem.new(list, next_line)
                desc.marker = "desc"
              end
            end
          end
        end

        list.items << term
        list.items << desc if desc
      end

      list
    end

    # Parse a table from a reader.
    def parse_table(table_reader : Reader, parent : AbstractBlock, attributes : Hash(String, String)) : Table
      table = Table.new(parent, attributes)

      # Parse column specs if provided
      if (cols = attributes["cols"]?)
        colspecs = parse_colspecs(cols)
        table.create_columns(colspecs) unless colspecs.empty?
      end

      format = attributes["format"]? || "psv"
      # TSV is an alias for CSV with tab separator
      format = "csv" if format == "tsv"
      separator = case format
                  when "csv"
                    # Custom separator overrides default comma
                    if (sep = attributes["separator"]?) && !sep.empty?
                      sep
                    else
                      ","
                    end
                  when "dsv" then ":"
                  else
                    # Custom separator for PSV
                    if (sep = attributes["separator"]?) && !sep.empty?
                      sep
                    else
                      "|"
                    end
                  end
      # Handle TSV tab separator
      separator = "\t" if attributes["format"]? == "tsv"

          has_header = attributes.has_key?("header-option")
      has_footer = attributes.has_key?("footer-option")
      row_index = 0
      implicit_header_checked = false
      implicit_header = false
      all_lines = table_reader.read_lines
      # Check for implicit header: first row followed immediately by blank line
      # The blank line must be at index 1 (right after the first non-blank line)
      unless has_header
        first_non_blank_idx = all_lines.index { |l| !l.empty? }
        if first_non_blank_idx
          next_idx = first_non_blank_idx + 1
          if next_idx < all_lines.size && all_lines[next_idx].empty?
            # Blank line immediately after first non-blank line - check there's more content
            post_blank = all_lines[(next_idx + 1)..].any? { |l| !l.empty? }
            implicit_header = post_blank
            has_header = implicit_header
          end
        end
      end
      # Parse cells with their specs (colspan, rowspan, style, etc.)
      # Each cell entry: {spec, content}
      parsed_cells = [] of Tuple(Hash(String, String | Int32), String)

      if format == "csv"
        # CSV: simple line-by-line parsing, no cell specs
        all_lines.each do |line|
          next if line.empty?
          parse_csv_cells(line, separator).each do |cell_text|
            parsed_cells << ({ {} of String => String | Int32, cell_text.strip })
          end
        end
      else
        # PSV/DSV: handle cell specs (colspan, rowspan, style, etc.)
        # Concatenate all lines with \n for multi-line cell support
        escaped_sep = "\\#{separator}"
        placeholder = "\x00ESCAPED_SEP\x00"
        full_content = all_lines.join("\n")
        safe_content = full_content.gsub(escaped_sep, placeholder)
        # Split by separator
        fragments = safe_content.split(separator)
        # Restore escaped separators
        fragments = fragments.map { |f| f.gsub(placeholder, separator) }
        # PSV format: [spec]|content[spec]|content...
        # fragments[0] = before first | (spec for cell 1, matched by CellSpecStartRx)
        # fragments[i] (i>0) = content of cell i + spec for cell i+1 (matched by CellSpecEndRx)
        # DSV format: cell1:cell2:cell3 (no leading separator, no cell specs)
        # fragments[0] = first cell content
        # fragments[i] = cell i+1 content
        #
        # Distinguish PSV from DSV: PSV starts with a separator (fragments[0] is empty or spec-only)
        # DSV: fragments[0] contains actual cell content
        is_psv_like = format != "dsv" # PSV and custom formats have leading separator

        if is_psv_like
          # Parse spec for cell 1 from fragments[0]
          first_frag = fragments[0]
          pending_spec = if first_frag.strip.empty?
            {} of String => String | Int32
          else
            # Use CellSpecStartRx directly on the first fragment
            m = CellSpecStartRx.match(first_frag.strip)
            if m && !m[0].empty?
              s = {} of String => String | Int32
              if m[1]?
                parts = m[1].split('.')
                colspec = parts[0]?.try(&.to_i?) || 1
                rowspec = parts[1]?.try(&.to_i?) || 1
                case m[2]?
                when "+"
                  s["colspan"] = colspec unless colspec == 1
                  s["rowspan"] = rowspec unless rowspec == 1
                when "*"
                  s["repeatcol"] = colspec unless colspec == 1
                end
              end
              if (align = m[3]?)
                parts = align.split('.')
                colspec_align = parts[0]? || ""
                rowspec_align = parts[1]? || ""
                if !colspec_align.empty? && colspec_align.size == 1 && TableCellHorzAlignments.has_key?(colspec_align[0])
                  s["halign"] = TableCellHorzAlignments[colspec_align[0]]
                end
                if !rowspec_align.empty? && rowspec_align.size == 1 && TableCellVertAlignments.has_key?(rowspec_align[0])
                  s["valign"] = TableCellVertAlignments[rowspec_align[0]]
                end
              end
              if (style_char = m[4]?) && !style_char.empty? && TableCellStyles.has_key?(style_char[0])
                s["style"] = style_char
              end
              s
            else
              {} of String => String | Int32
            end
          end
          (1...fragments.size).each do |i|
            frag = fragments[i]
            spec_for_next, cell_content = parse_cellspec(frag, :end)
            spec_for_next ||= {} of String => String | Int32
            # Strip leading newline from cell content (from line join)
            cell_content = cell_content.lstrip('\n').rstrip
            # Handle repeatcol: duplicate cell
            repeat = (pending_spec["repeatcol"]?.try { |v| v.is_a?(Int32) ? v : v.to_s.to_i? } || 1)
            repeat.times do
              parsed_cells << ({pending_spec.reject { |k, _| k == "repeatcol" }, cell_content})
            end
            pending_spec = spec_for_next
          end
        else
          # DSV: no cell specs, each fragment is a cell content
          # fragments are separated by newlines within the full_content join
          # We need to handle multi-line cells: each line is a separate row
          # DSV: cell1:cell2:cell3\ncell4:cell5:cell6
          # fragments = ["cell1", "cell2", "cell3\ncell4", "cell5", "cell6"]
          # The \n in fragments means a new row starts
          # We need to split fragments at \n boundaries
          fragments.each do |frag|
            # Split by newline to handle row boundaries
            sub_frags = frag.split("\n")
            sub_frags.each_with_index do |sf, idx|
              cell_content = sf.strip
              # Empty fragment at end of line means empty cell (trailing separator)
              parsed_cells << ({ {} of String => String | Int32, cell_content})
            end
          end
        end
      end

      # Determine number of columns
      num_cols = table.columns.size
      if num_cols == 0
        # Auto-detect from first row: count cells until we fill a row
        # For PSV with spans, count effective columns in first row
        first_row_cols = 0
        parsed_cells.each do |spec, _|
          colspan = spec["colspan"]?.try { |v| v.is_a?(Int32) ? v : v.to_s.to_i? } || 1
          first_row_cols += colspan
          break if first_row_cols >= (parsed_cells.size > 0 ? parsed_cells.size : 1)
        end
        # Simple heuristic: use first non-spanning row to determine column count
        # Count cells in first logical row
        col_count = 0
        parsed_cells.each do |spec, _|
          colspan = spec["colspan"]?.try { |v| v.is_a?(Int32) ? v : v.to_s.to_i? } || 1
          col_count += colspan
          # Check if we've completed a row by looking at total columns
          # We'll use a simple approach: count until we have a reasonable number
          break
        end
        # Count effective columns from first row of parsed_cells
        # A row is complete when effective_cols >= some threshold
        # Use first line to count: parse specs and sum colspan+repeatcol
        first_line = all_lines.find { |l| !l.empty? }
        if first_line
          if format == "csv"
            num_cols = parse_csv_cells(first_line, separator).size
          elsif format == "dsv"
            # DSV: count separators in first line + 1
            esc_sep = "\\#{separator}"
            ph = "\x00ESCAPED_SEP\x00"
            safe_line = first_line.gsub(esc_sep, ph)
            num_cols = safe_line.split(separator).size
          else
            esc_sep = "\\#{separator}"
            ph = "\x00ESCAPED_SEP\x00"
            safe_line = first_line.gsub(esc_sep, ph)
            first_frags = safe_line.split(separator)
            # first_frags[0] is the spec before the first |
            # first_frags[i] (i>0) is content + spec for next cell
            # Count effective columns in first line
            pending_first_spec = if first_frags[0].strip.empty?
              {} of String => String | Int32
            else
              m2 = CellSpecStartRx.match(first_frags[0].strip)
              if m2 && !m2[0].empty?
                s2 = {} of String => String | Int32
                if m2[1]?
                  parts2 = m2[1].split('.')
                  cs2 = parts2[0]?.try(&.to_i?) || 1
                  rs2 = parts2[1]?.try(&.to_i?) || 1
                  case m2[2]?
                  when "+"
                    s2["colspan"] = cs2 unless cs2 == 1
                    s2["rowspan"] = rs2 unless rs2 == 1
                  when "*"
                    s2["repeatcol"] = cs2 unless cs2 == 1
                  end
                end
                s2
              else
                {} of String => String | Int32
              end
            end
            effective_cols = 0
            (1...first_frags.size).each do |fi|
              frag_r = first_frags[fi].gsub(ph, separator)
              spec_next, _ = parse_cellspec(frag_r, :end)
              spec_next ||= {} of String => String | Int32
              # Count this cell's effective columns
              colspan_f = pending_first_spec["colspan"]?.try { |v| v.is_a?(Int32) ? v : v.to_s.to_i? } || 1
              repeat_f = pending_first_spec["repeatcol"]?.try { |v| v.is_a?(Int32) ? v : v.to_s.to_i? } || 1
              effective_cols += colspan_f * repeat_f
              pending_first_spec = spec_next
            end
            num_cols = effective_cols if effective_cols > 0
          end
        end
        num_cols = 1 if num_cols == 0
        # Create columns
        num_cols.times do |i|
          col = Table::Column.new(table, i)
          table.columns << col
        end
      end

      # Distribute cells into rows based on column count, respecting colspan/rowspan
      # Track which cells are occupied by rowspans
      current_row = [] of Table::Cell
      current_row_cols = 0  # effective columns used in current row (accounting for colspan)
      row_num = 0
      # Grid to track rowspan occupancy: grid[row][col] = true if occupied
      rowspan_grid = Array(Array(Bool)).new

      parsed_cells.each do |spec, cell_text|
        colspan = spec["colspan"]?.try { |v| v.is_a?(Int32) ? v : v.to_s.to_i? } || 1
        rowspan = spec["rowspan"]?.try { |v| v.is_a?(Int32) ? v : v.to_s.to_i? } || 1
        halign = spec["halign"]?.try { |v| v.is_a?(String) ? v : nil }
        valign = spec["valign"]?.try { |v| v.is_a?(String) ? v : nil }
        style_char = spec["style"]?.try { |v| v.is_a?(String) ? v : nil }
        cell_style = if style_char
          case style_char
          when "d" then :none
          when "s" then :strong
          when "e" then :emphasis
          when "m" then :monospaced
          when "h" then :header
          when "l" then :literal
          when "a" then :asciidoc
          else nil
          end
        end

        # Ensure rowspan_grid has enough rows
        (rowspan_grid.size..row_num + rowspan).each do |r|
          rowspan_grid << Array(Bool).new(num_cols, false)
        end

        # Find next available column in current row
        col_idx = 0
        while col_idx < num_cols
          row_arr = rowspan_grid[row_num]? || Array(Bool).new(num_cols, false)
          break unless row_arr[col_idx]? == true
          col_idx += 1
        end

        # Skip if no column available (shouldn't happen in well-formed tables)
        next if col_idx >= num_cols

        # Ensure column exists
        while table.columns.size <= col_idx
          col = Table::Column.new(table, table.columns.size)
          table.columns << col
        end

        # Create cell attributes
        cell_attrs = {} of String => String
        cell_attrs["halign"] = halign if halign
        cell_attrs["valign"] = valign if valign

        cell = Table::Cell.new(table.columns[col_idx], cell_text,
          attributes: cell_attrs,
          colspan: colspan > 1 ? colspan : nil,
          rowspan: rowspan > 1 ? rowspan : nil,
          style: cell_style)

        # Mark rowspan_grid for occupied cells
        rowspan.times do |r|
          colspan.times do |c|
            gr = row_num + r
            gc = col_idx + c
            while rowspan_grid.size <= gr
              rowspan_grid << Array(Bool).new(num_cols, false)
            end
            while rowspan_grid[gr].size <= gc
              rowspan_grid[gr] << false
            end
            rowspan_grid[gr][gc] = true
          end
        end

        current_row << cell
        current_row_cols += colspan

        # Check if current row is complete
        # Count effective columns used (including rowspan-occupied slots)
        effective_used = 0
        num_cols.times do |c|
          row_arr = rowspan_grid[row_num]? || Array(Bool).new(num_cols, false)
          effective_used += 1 if row_arr[c]? == true
        end

        if effective_used >= num_cols
          # Row is complete
          if has_header && row_num == 0
            table.rows.head << current_row
          else
            body_row = has_header ? row_num - 1 : row_num
            table.rows.body << current_row
          end
          current_row = [] of Table::Cell
          current_row_cols = 0
          row_num += 1
        end
      end

      # Add any remaining cells as a partial row
      unless current_row.empty?
        if has_header && row_num == 0
          table.rows.head << current_row
        else
          body_row = has_header ? row_num - 1 : row_num
          table.rows.body << current_row
        end
      end

      # Move last body row to footer if footer option is set
      if has_footer && table.rows.body.size > 0
        table.rows.foot << table.rows.body.pop
      end

      # Assign column widths based on colspecs or distribute evenly
      if !table.columns.empty?
        # Calculate width_base from colspecs if available
        if attributes.has_key?("cols")
          colspecs = parse_colspecs(attributes["cols"])
          unless colspecs.empty?
            width_base = colspecs.sum { |cs| (cs["width"]?.try(&.to_s.to_f?) || 1.0) }
            table.assign_column_widths(width_base)
          end
        end
        # If no colpcwidth assigned yet, distribute evenly
        if table.columns.any? { |col| col.attr("colpcwidth").nil? }
          precision = 4
          col_pcwidth = (100.0 / table.columns.size).round(precision)
          table.columns.each_with_index do |col, idx|
            if idx == table.columns.size - 1
              # Last column gets the remainder
              assigned = table.columns[0...-1].sum { |c| c.attr("colpcwidth").try(&.to_f) || 0.0 }
              col.attributes["colpcwidth"] = (100.0 - assigned).round(precision).to_s
            else
              col.attributes["colpcwidth"] = col_pcwidth.to_s
            end
          end
        end
      end

      table
    end

    # Parse a CSV line into cells, handling quoted values with commas and escaped quotes.
    def parse_csv_cells(line : String, sep : String = ",") : Array(String)
      cells = [] of String
      current = IO::Memory.new
      in_quotes = false
      i = 0
      while i < line.size
        c = line[i]
        if in_quotes
          if c == '"'
            if i + 1 < line.size && line[i + 1] == '"'
              # Escaped quote
              current << '"'
              i += 2
              next
            else
              in_quotes = false
            end
          else
            current << c
          end
        else
          if c == '"'
            in_quotes = true
          elsif line[i...(i + sep.size)] == sep
            cells << current.to_s.strip
            current = IO::Memory.new
            i += sep.size
            next
          else
            current << c
          end
        end
        i += 1
      end
      cells << current.to_s.strip
      cells
    end

    # Parse column specs for a table.
    def parse_colspecs(records : String) : Array(Hash(String, String | Int32))
      records = records.delete(' ') if records.includes?(' ')

      # Check for simple number (equal column spread)
      if records == records.to_i?.try(&.to_s)
        return Array.new(records.to_i) { {"width" => 1} of String => String | Int32 }
      end

      specs = [] of Hash(String, String | Int32)
      delimiter = records.includes?(',') ? ',' : ';'
      records.split(delimiter, remove_empty: false).each do |record|
        if record.empty?
          specs << {"width" => 1} of String => String | Int32
        elsif (m = ColumnSpecRx.match(record))
          spec = {} of String => String | Int32
          if (align = m[2]?)
            parts = align.split('.')
            colspec = parts[0]? || ""
            rowspec = parts[1]? || ""
            if !colspec.empty? && colspec.size == 1 && TableCellHorzAlignments.has_key?(colspec[0])
              spec["halign"] = TableCellHorzAlignments[colspec[0]]
            end
            if !rowspec.empty? && rowspec.size == 1 && TableCellVertAlignments.has_key?(rowspec[0])
              spec["valign"] = TableCellVertAlignments[rowspec[0]]
            end
          end
          if (width = m[3]?)
            if width == "~"
              spec["width"] = -1
            elsif width.ends_with?("%")
              spec["width"] = width.rchop.to_i
              spec["width_type"] = "%"
            else
              spec["width"] = width.to_i
            end
          else
            spec["width"] = 1
          end
          if (style_char = m[4]?) && !style_char.empty? && TableCellStyles.has_key?(style_char[0])
            spec["style"] = style_char
          end
          if (repeat = m[1]?)
            repeat.to_i.times { specs << spec.dup }
          else
            specs << spec
          end
        end
      end
      specs
    end

    # Process consecutive attribute entry lines.
    def process_attribute_entries(reader : Reader, document : Document, attributes : Hash(String, String)? = nil) : Nil
      reader.skip_comment_lines
      while process_attribute_entry(reader, document, attributes)
        reader.advance
        reader.skip_comment_lines
      end
    end

    # Process a single attribute entry line.
    def process_attribute_entry(reader : Reader, document : Document, attributes : Hash(String, String)? = nil, match : Regex::MatchData? = nil) : Bool
      unless match
        return false unless reader.has_more_lines?
        line = reader.peek_line
        return false unless line
        match = AttributeEntryRx.match(line)
        return false unless match
      end

      value = match[2]? || ""
      # Handle multi-line attribute values
      if value.ends_with?(" \\")
        # Check if it's a line-break continuation: ends with " + \"
        if value.rstrip.ends_with?(" + \\")
          # Line-break continuation: preserve + and join with \n
          value = value.rstrip[0...-2].rstrip  # remove " \\"
          while reader.advance
            next_line = reader.peek_line || ""
            break if next_line.empty?
            next_line = next_line.lstrip
            keep_open = next_line.ends_with?(" \\")
            next_line = next_line[0, next_line.size - 2].rstrip if keep_open
            value = "#{value}\n#{next_line}"
            break unless keep_open
          end
        else
          # Modern continuation with backslash: join with space
          value = value[0, value.size - 2].rstrip
          while reader.advance
            next_line = reader.peek_line || ""
            break if next_line.empty?
            next_line = next_line.lstrip
            keep_open = next_line.ends_with?(" \\")
            next_line = next_line[0, next_line.size - 2].rstrip if keep_open
            value = "#{value} #{next_line}"
            break unless keep_open
          end
        end
      elsif value.rstrip.ends_with?(" +")
        # Legacy continuation with +
        value = value.rstrip[0...-2].rstrip
        while reader.advance
          next_line = reader.peek_line || ""
          break if next_line.empty?
          next_line = next_line.lstrip
          keep_open = next_line.rstrip.ends_with?(" +")
          next_line = next_line.rstrip[0...-2].rstrip if keep_open
          value = "#{value} #{next_line}"
          break unless keep_open
        end
      end

      store_attribute(match[1], value, document, attributes)
      true
    end

    # Read paragraph lines until a break condition is met.
    def read_paragraph_lines(reader : Reader, break_on_list : Bool = false) : Array(String)
      if break_on_list
        reader.read_lines_until(break_on_blank_lines: true, break_on_list_continuation: true, preserve_last_line: true, skip_line_comments: true) { |line| AnyListRx.matches?(line) || !!is_delimited_block?(line) || (line.starts_with?(':') && AttributeEntryRx.matches?(line)) }
      else
        reader.read_lines_until(break_on_blank_lines: true, break_on_list_continuation: true, preserve_last_line: true, skip_line_comments: true) { |line| !!is_delimited_block?(line) || (line.starts_with?(':') && AttributeEntryRx.matches?(line)) }
      end
    end

    # Resolve the 0-index marker for a list item.
    def resolve_list_marker(list_type : Symbol, marker : String) : String
      case list_type
      when :ulist
        marker
      when :olist
        resolve_ordered_list_marker(marker)[0]
      else # :colist
        "<1>"
      end
    end

    # Collect the lines belonging to the current list item, navigating
    # through all the rules that determine what comprises a list item.
    def read_lines_for_list_item(reader : Reader, list_type : Symbol, sibling_trait : String | Regex, has_text : Bool = true) : Array(String)
      buffer = [] of String
      continuation = :inactive
      within_nested_list = false
      detached_continuation : Int32? = nil
      dlist = list_type == :dlist

      while reader.has_more_lines?
        this_line = reader.read_line
        break unless this_line

        # if we've arrived at a sibling item in this list, we've captured
        # the complete list item and can begin processing it
        if is_sibling_list_item?(this_line, list_type, sibling_trait)
          reader.unshift_line(this_line)
          break
        end

        this_line = LIST_CONTINUATION_STRING if this_line == LIST_CONTINUATION

        prev_line = buffer.empty? ? nil : buffer[-1]

        if prev_line && (prev_line == LIST_CONTINUATION_STRING || prev_line == LIST_CONTINUATION_PLACEHOLDER)
          if continuation == :inactive
            continuation = :active
            has_text = true
            buffer[-1] = LIST_CONTINUATION_PLACEHOLDER unless within_nested_list
          end
          # dealing with adjacent list continuations
          if this_line == LIST_CONTINUATION_STRING || this_line == LIST_CONTINUATION_PLACEHOLDER
            if continuation != :frozen
              continuation = :frozen
              buffer << this_line
            end
            next
          end
        end

        # a delimited block immediately breaks the list unless preceded by a list continuation
        if (match = is_delimited_block?(this_line, true))
          unless continuation == :active
            reader.unshift_line(this_line)
            break
          end
          buffer << this_line
          buffer.concat(reader.read_lines_until(terminator: match.terminator, read_last_line: true))
          continuation = :inactive
        elsif dlist && continuation != :active && this_line.starts_with?('[') && BlockAttributeLineRx.matches?(this_line)
          # BlockAttributeLineRx only breaks dlist if ensuing line is not a list item
          block_attribute_lines = [this_line]
          interrupt = false
          while (next_line = reader.peek_line)
            if is_delimited_block?(next_line)
              interrupt = true
            elsif next_line.empty? || (next_line.starts_with?('[') && BlockAttributeLineRx.matches?(next_line))
              block_attribute_lines << reader.read_line.not_nil!
              next
            elsif AnyListRx.matches?(next_line) && !is_sibling_list_item?(next_line, list_type, sibling_trait)
              buffer.concat(block_attribute_lines)
            else
              interrupt = true
            end
            break
          end
          if interrupt
            reader.unshift_lines(block_attribute_lines)
            break
          end
        elsif continuation == :active && !this_line.empty?
          if LiteralParagraphRx.matches?(this_line)
            reader.unshift_line(this_line)
            if dlist
              buffer.concat(reader.read_lines_until(preserve_last_line: true, break_on_blank_lines: true, break_on_list_continuation: true) { |line| is_sibling_list_item?(line, list_type, sibling_trait) })
            else
              buffer.concat(reader.read_lines_until(preserve_last_line: true, break_on_blank_lines: true, break_on_list_continuation: true))
            end
            continuation = :inactive
          elsif (this_line.starts_with?('.') && BlockTitleRx.matches?(this_line)) ||
                (this_line.starts_with?('[') && BlockAttributeLineRx.matches?(this_line)) ||
                (this_line.starts_with?(':') && AttributeEntryRx.matches?(this_line))
            buffer << this_line
          else
            nestable_contexts = within_nested_list ? [:dlist] : NESTABLE_LIST_CONTEXTS
            if (nested_list_type = nestable_contexts.find { |ctx| ListRxMap[ctx].matches?(this_line) })
              within_nested_list = true
              if nested_list_type == :dlist && (dm = DescriptionListRx.match(this_line)) && (dm[3]?.nil? || dm[3].empty?)
                has_text = false
              end
            end
            buffer << this_line
            continuation = :inactive
          end
        elsif prev_line && prev_line.empty?
          # advance to the next line of content
          if this_line.empty?
            reader.skip_blank_lines
            this_line = reader.read_line
            unless this_line
              break
            end
            if is_sibling_list_item?(this_line, list_type, sibling_trait)
              reader.unshift_line(this_line)
              break
            end
          end
          if this_line == LIST_CONTINUATION || this_line == LIST_CONTINUATION_STRING
            detached_continuation = buffer.size
            buffer << LIST_CONTINUATION_STRING
          elsif has_text
            if is_sibling_list_item?(this_line, list_type, sibling_trait)
              reader.unshift_line(this_line)
              break
            end
            nestable_contexts2 = NESTABLE_LIST_CONTEXTS
            if (nested_list_type = nestable_contexts2.find { |ctx| ListRxMap[ctx].matches?(this_line) })
              buffer << this_line
              within_nested_list = true
              if nested_list_type == :dlist && (dm = DescriptionListRx.match(this_line)) && (dm[3]?.nil? || dm[3].empty?)
                has_text = false
              end
            elsif LiteralParagraphRx.matches?(this_line)
              reader.unshift_line(this_line)
              if dlist
                buffer.concat(reader.read_lines_until(preserve_last_line: true, break_on_blank_lines: true, break_on_list_continuation: true) { |line| is_sibling_list_item?(line, list_type, sibling_trait) })
              else
                buffer.concat(reader.read_lines_until(preserve_last_line: true, break_on_blank_lines: true, break_on_list_continuation: true))
              end
            else
              reader.unshift_line(this_line)
              break
            end
          else # only dlist in need of item text, so slurp it up!
            buffer.pop unless within_nested_list
            buffer << this_line
            has_text = true
          end
        elsif this_line == LIST_CONTINUATION_STRING || this_line == LIST_CONTINUATION_PLACEHOLDER
          has_text = true
          buffer << this_line
        else
          unless this_line.empty?
            has_text = true
            nestable_contexts3 = within_nested_list ? [:dlist] : NESTABLE_LIST_CONTEXTS
            if (nested_list_type = nestable_contexts3.find { |ctx| ListRxMap[ctx].matches?(this_line) })
              within_nested_list = true
              if nested_list_type == :dlist && (dm = DescriptionListRx.match(this_line)) && (dm[3]?.nil? || dm[3].empty?)
                has_text = false
              end
            end
          end
          buffer << this_line
        end
      end

      buffer[detached_continuation] = LIST_CONTINUATION_PLACEHOLDER if detached_continuation

      # trim trailing blank lines and trailing continuation
      until buffer.empty?
        last_line = buffer[-1]
        if last_line == LIST_CONTINUATION_STRING || last_line == LIST_CONTINUATION_PLACEHOLDER
          buffer.pop
          break
        elsif last_line.empty?
          buffer.pop
        else
          break
        end
      end

      buffer
    end

    # Resolve the 0-index marker for an ordered list item.
    # When ordinal and validate are provided, validates the marker against the expected value.
    def resolve_ordered_list_marker(marker : String, ordinal : Int32? = nil, validate : Bool = false, reader : Reader? = nil) : Tuple(String, Symbol?)
      return {marker, nil} if marker.starts_with?('.')
      style = ORDERED_LIST_STYLES.find { |s| OrderedListMarkerRxMap[s].matches?(marker) }
      expected : String? = nil
      actual : String? = nil
      case style
      when :arabic
        if validate && ordinal
          expected = (ordinal + 1).to_s
          actual = marker.chomp('.')
        end
        marker = "1."
      when :loweralpha
        if validate && ordinal
          expected = (97 + ordinal).chr.to_s
          actual = marker.chomp('.')
        end
        marker = "a."
      when :upperalpha
        if validate && ordinal
          expected = (65 + ordinal).chr.to_s
          actual = marker.chomp('.')
        end
        marker = "A."
      when :lowerroman
        if validate && ordinal
          expected = Helpers.int_to_roman(ordinal + 1).downcase
          actual = marker.chomp(')')
        end
        marker = "i)"
      when :upperroman
        if validate && ordinal
          expected = Helpers.int_to_roman(ordinal + 1)
          actual = marker.chomp(')')
        end
        marker = "I)"
      end
      if validate && expected && actual && expected != actual
        logger.warn { "list item index: expected #{expected}, got #{actual}" }
      end
      {marker, style}
    end

    # Resolve the start number for an ordered list based on its marker.
    def resolve_ordered_list_start(marker : String) : Int32
      return 1 if marker.starts_with?('.')
      style = ORDERED_LIST_STYLES.find { |s| OrderedListMarkerRxMap[s].matches?(marker) }
      case style
      when :arabic
        marker.chomp('.').to_i
      when :loweralpha
        marker.chomp('.').char_at(0).ord - 96
      when :upperalpha
        marker.chomp('.').char_at(0).ord - 64
      when :lowerroman
        Helpers.roman_to_int(marker.chomp(')').upcase)
      when :upperroman
        Helpers.roman_to_int(marker.chomp(')'))
      else
        1
      end
    end

    # Convert a string to a legal attribute name.
    def sanitize_attribute_name(name : String) : String
      name.gsub(InvalidAttributeNameCharsRx, "").downcase
    end

    # Store an attribute in the document.
    def store_attribute(name : String, value : String, doc : Document? = nil, attrs : Hash(String, String)? = nil) : Tuple(String, String?)
      actual_value : String? = value
      if name.ends_with?('!')
        name = name[0, name.size - 1]
        actual_value = nil
      elsif name.starts_with?('!')
        name = name[1..]
        actual_value = nil
      end

      name = sanitize_attribute_name(name)
      name = "sectnums" if name == "numbered"
      name = "hardbreaks-option" if name == "hardbreaks"

      if doc
        # Check if attribute is locked by API override
        if doc.attribute_overrides.has_key?(name)
          override_val = doc.attribute_overrides[name]
          if override_val.nil?
            # Attribute was unset via API - cannot be set by document
            doc.attributes.delete(name)
            return {name, nil}
          else
            # Attribute was set via API - cannot be overridden or unset by document
            return {name, override_val}
          end
        end
        if actual_value
          if name == "leveloffset" && (actual_value.starts_with?('+') || actual_value.starts_with?('-'))
            current = (doc.attributes["leveloffset"]? || "0").to_i
            offset = actual_value.to_i
            actual_value = (current + offset).to_s
          end
          # set_attribute applies apply_attribute_value_subs (specialcharacters + attributes subs)
          resolved_value = doc.set_attribute(name, actual_value) || actual_value
          if attrs
            # Store attribute entry for playback during conversion.
            # Store the resolved value (after substitutions) so playback uses the correct value.
            existing = attrs["__attr_entries__"]?
            entry_str = "#{name}\u0000#{resolved_value}"
            attrs["__attr_entries__"] = existing ? "#{existing}\u0001#{entry_str}" : entry_str
          end
        else
          doc.attributes.delete(name)
          if attrs
            # Store attribute entry (negate) for playback during conversion.
            # Do NOT delete from block_attributes directly.
            existing = attrs["__attr_entries__"]?
            entry_str = "#{name}\u0000\u0002" # \u0002 signals negate
            attrs["__attr_entries__"] = existing ? "#{existing}\u0001#{entry_str}" : entry_str
          end
        end
      elsif attrs
        if actual_value
          attrs[name] = actual_value
        else
          attrs.delete(name)
        end
      end

      {name, actual_value}
    end

    # Setext (two-line) section title levels.
    SETEXT_SECTION_LEVELS = {
      '=' => 0,
      '-' => 1,
      '~' => 2,
      '^' => 3,
      '+' => 4,
    }

    # Check whether the two lines form a setext-style section title.
    def setext_section_title?(line1 : String, line2 : String) : Int32?
      return nil if line2.empty?
      ch0 = line2[0]
      if (level = SETEXT_SECTION_LEVELS[ch0]?) &&
         uniform?(line2, ch0.to_s, line2.size) &&
         SetextSectionTitleRx.matches?(line1) &&
         (line1.size - line2.size).abs < 2
        level
      else
        nil
      end
    end

    # Convert a string to a block context Symbol.
    def string_to_block_context(name : String) : Symbol?
      BLOCK_CONTEXT_MAP[name]?
    end

    BLOCK_CONTEXT_MAP = {
      "abstract"     => :abstract,
      "admonition"   => :admonition,
      "asciimath"    => :asciimath,
      "audio"        => :audio,
      "colist"       => :colist,
      "comment"      => :comment,
      "dlist"        => :dlist,
      "example"      => :example,
      "fenced_code"  => :fenced_code,
      "floating_title" => :floating_title,
      "image"        => :image,
      "latexmath"    => :latexmath,
      "listing"      => :listing,
      "literal"      => :literal,
      "olist"        => :olist,
      "open"         => :open,
      "page_break"   => :page_break,
      "paragraph"    => :paragraph,
      "partintro"    => :partintro,
      "pass"         => :pass,
      "preamble"     => :preamble,
      "quote"        => :quote,
      "sidebar"      => :sidebar,
      "source"       => :source,
      "stem"         => :stem,
      "table"        => :table,
      "thematic_break" => :thematic_break,
      "toc"          => :toc,
      "ulist"        => :ulist,
      "verse"        => :verse,
      "video"        => :video,
    }

    # Check if a string is uniform (all the same character).
    def uniform?(str : String, chr : String, len : Int32) : Bool
      return false if str.empty? || chr.empty?
      str.count(chr[0]) == len
    end

    # Process authors from an author line.
    def process_authors(author_line : String, names_only : Bool = false, multiple : Bool = true) : Hash(String, String)
      author_metadata = {} of String => String
      author_idx = 0
      entries = multiple && author_line.includes?(';') ? author_line.split(AuthorDelimiterRx) : [author_line]

      entries.each do |author_entry|
        next if author_entry.empty?
        author_idx += 1

        key_suffix = author_idx == 1 ? "" : "_#{author_idx}"
        # Extract email if present (e.g. "John Doe <john@example.com>")
        author_entry_clean = author_entry.strip
        email = nil
        if (email_match = author_entry_clean.match(/<([^>]+)>/))
          email = email_match[1]
          author_entry_clean = author_entry_clean.sub(/<[^>]+>/, "").strip
          author_metadata["email#{key_suffix}"] = email unless names_only
        end

        segments = author_entry_clean.split(/\s+/, 3)

        if segments.size >= 1
          fname = segments[0].tr("_", " ")
          author = fname
          initials = fname[0].to_s

          author_metadata["firstname#{key_suffix}"] = fname
          if segments.size == 3
            mname = segments[1].tr("_", " ")
            lname = segments[2].tr("_", " ")
            author = "#{fname} #{mname} #{lname}"
            initials = "#{fname[0]}#{mname[0]}#{lname[0]}"
            author_metadata["middlename#{key_suffix}"] = mname
            author_metadata["lastname#{key_suffix}"] = lname
          elsif segments.size == 2
            lname = segments[1].tr("_", " ")
            author = "#{fname} #{lname}"
            initials = "#{fname[0]}#{lname[0]}"
            author_metadata["lastname#{key_suffix}"] = lname
          end

          author_metadata["author#{key_suffix}"] = author
          author_metadata["authorinitials#{key_suffix}"] = initials
        end

        if author_idx == 1
          author_metadata["authors"] = author_metadata["author"]? || ""
        else
          if author_idx == 2
            AuthorKeys.each do |key|
              author_metadata["#{key}_1"] = author_metadata[key] if author_metadata.has_key?(key)
            end
          end
          author_metadata["authors"] = "#{author_metadata["authors"]?}, #{author_metadata["author#{key_suffix}"]?}"
        end
      end

      author_metadata["authorcount"] = author_idx.to_s
      author_metadata
    end

    # Save the collected attribute (:id, :option, :role, or nil for :style) in the attribute Hash.
    def yield_buffered_attribute(attrs : Hash(Symbol, String | Array(String)), name : Symbol?, value : String, reader : Reader? = nil) : Nil
      if name
        if value.empty?
          logger.warn { "invalid empty #{name} detected in style attribute" }
        elsif name == :id
          if attrs.has_key?(:id)
            logger.warn { "multiple ids detected in style attribute" }
          end
          attrs[name] = value
        else
          existing = attrs[name]?
          if existing.is_a?(Array(String))
            existing << value
          else
            attrs[name] = [value]
          end
        end
      else
        attrs[:style] = value unless value.empty?
      end
      nil
    end

    # --------------------------------------------------------------------------
    # Compliance flags (can be made configurable later)
    # --------------------------------------------------------------------------

    COMPLIANCE_MARKDOWN_SYNTAX                = true
    COMPLIANCE_UNDERLINE_STYLE_SECTION_TITLES = true
  end
end
