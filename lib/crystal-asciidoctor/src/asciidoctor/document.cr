require "./abstract_block"
require "./safe_mode"
require "./callouts"

module Asciidoctor
  # The Document class represents a parsed AsciiDoc document.
  #
  # Document is the root node of a parsed AsciiDoc document. It provides an
  # abstract syntax tree (AST) that represents the structure of the AsciiDoc
  # document from which the Document object was parsed.
  class Document < AbstractBlock
    # A data object representing an image reference.
    record ImageReference, target : String, imagesdir : String do
      def to_s(io : IO) : Nil
        io << @target
      end
    end

    # A data object representing a footnote.
    record Footnote, index : Int32, id : String?, text : String?

    # A data object representing a document attribute entry.
    class AttributeEntry
      getter name : String
      getter negate : Bool
      property value : String?

      def initialize(@name : String, @value : String?, negate : Bool? = nil)
        @negate = negate.nil? ? @value.nil? : negate
      end

      # Save this attribute entry to the given attributes hash.
      def save_to(attrs : Hash(String, String)) : self
        if @negate
          attrs.delete @name
        else
          attrs[@name] = @value || ""
        end
        self
      end
    end

    # Parsed and stores a partitioned title (i.e., title & subtitle).
    class Title
      getter combined : String
      getter main : String
      getter? sanitized : Bool
      getter subtitle : String?

      def initialize(val : String, separator : String = ":", sanitize : Bool = false)
        @sanitized = sanitize
        val = val.gsub(/<[^>]+>/, "").squeeze(' ').strip if sanitize && val.includes?('<')

        sep = "#{separator} "
        if separator.empty? || !val.includes?(sep)
          @main = val
          @subtitle = nil
        else
          idx = val.rindex(sep)
          if idx
            @main = val[0...idx]
            @subtitle = val[(idx + sep.size)..]
          else
            @main = val
            @subtitle = nil
          end
        end
        @combined = val
      end

      def subtitle? : Bool
        !@subtitle.nil?
      end

      def to_s(io : IO) : Nil
        io << @combined
      end
    end

    # The Author class represents information about an author.
    record Author, name : String, firstname : String, middlename : String?, lastname : String, initials : String, email : String?

    # The cached value of the backend attribute.
    getter backend : String

    # The String base directory for converting this document.
    getter base_dir : String

    # The document catalog Hash.
    getter catalog : Catalog

    # The Boolean AsciiDoc compatibility mode.
    getter? compat_mode : Bool

    # The Converter associated with this document.
    property converter : Converter::Base?

    # The Hash of document counters.
    getter counters : Hash(String, Int32 | String)

    # The cached value of the doctype attribute.
    getter doctype : String

    # The activated Extensions::Registry associated with this document.
    property extensions : Extensions::Registry?

    # The level-0 Section (i.e., doctitle).
    property header : Section?

    # The Hash of resolved options.
    getter options : Hash(String, String | Bool | Int32)

    # The outfilesuffix defined at the end of the header.
    getter outfilesuffix : String

    # A reference to the parent Document of this nested document.
    getter parent_document : Document?

    # A read-only integer value indicating the level of security.
    getter safe : Int32

    # Whether source map information should be tracked by the parser.
    property? sourcemap : Bool

    # The SyntaxHighlighter associated with this document.
    property syntax_highlighter : SyntaxHighlighterBase?

    # Whether the document has been parsed.
    property parsed : Bool = false

    # The attribute overrides (locked attributes).
    getter attribute_overrides : Hash(String, String?)

    # The set of attributes modified during header processing.
    @attributes_modified : Set(String)

    # The saved header attributes for restoration.
    @header_attributes : Hash(String, String)?

    # The maximum attribute value size.
    property max_attribute_value_size : Int32?

    # The Reader associated with this document.
    property reader : Reader?

    # The source location of the document.
    @source_location_doc : SourceLocation?

    def initialize(@safe : Int32 = SafeMode::SECURE,
                   @backend : String = DEFAULT_BACKEND,
                   @doctype : String = DEFAULT_DOCTYPE,
                   @base_dir : String = ".",
                   @sourcemap : Bool = false,
                   @parent_document : Document? = nil,
                   @options : Hash(String, String | Bool | Int32) = {} of String => String | Bool | Int32)
      super(:document, {} of String => String)
      @catalog = Catalog.new
      @compat_mode = false
      @converter = nil
      @counters = {} of String => Int32 | String
      @extensions = nil
      @header = nil
      @outfilesuffix = DEFAULT_EXTENSIONS[@backend.gsub(/\d+$/, "")]? || ".html"
      @syntax_highlighter = nil
      @parsed = false
      @attribute_overrides = {} of String => String?
      @attributes_modified = Set(String).new
      @header_attributes = nil
      # In SECURE mode, default to 4096 bytes for attribute value size limit
      @max_attribute_value_size = @safe >= SafeMode::SECURE ? 4096 : nil
      @reader = nil
      @source_location_doc = nil
    end

    # Append a content block to this block's list of blocks.
    # If the child block is a Section, assign an index to it.
    def <<(block : AbstractBlock) : self
      if block.is_a?(Section)
        assign_numeral(block)
      end
      super(block)
    end

    # Internal: Apply substitutions to the attribute value.
    #
    # If the value is an inline passthrough macro (e.g., pass:<subs>[value]),
    # apply the substitutions defined in <subs> to the value, or leave the value
    # unmodified if no substitutions are specified. If the value is not an
    # inline passthrough macro, apply header substitutions to the value.
    def apply_attribute_value_subs(value : String) : String
      if (md = AttributeEntryPassMacroRx.match(value))
        result = md[2]? || ""
        if (subs_str = md[1]?) && !subs_str.empty?
          result = apply_subs(result, resolve_pass_subs(subs_str))
        end
        result
      else
        apply_subs(value, [:specialcharacters, :attributes])
      end
    end

    # Assign a numeral to a section (delegates to AbstractBlock).
    # This override is needed because Document also calls assign_numeral
    # from the parser's parse() method for top-level sections.
    # We simply call super to use the AbstractBlock implementation.
    # :nodoc:
    # Note: This method is intentionally left to delegate to super.
    # Removing it would also work since Document < AbstractBlock.

    # Check if the specified attribute is locked (set via overrides).
    def attribute_locked?(name : String) : Bool
      @attribute_overrides.has_key?(name)
    end

    # Get the author.
    def author : String?
      @attributes["author"]?
    end

    # Get the Array of authors.
    def authors : Array(String)
      result = [] of String
      if (a = @attributes["author"]?)
        result << a
      end
      (2..10).each do |i|
        if (a = @attributes["author_#{i}"]?)
          result << a
        else
          break
        end
      end
      result
    end

    # Check whether the current backend matches the base backend.
    def basebackend?(base : String) : Bool
      @backend.starts_with?(base)
    end

    # Get the callouts.
    def callouts : Callouts
      @catalog.callouts
    end

    # Internal: Delete any attributes stored for playback.
    def clear_playback_attributes(attrs : Hash(String, String)) : Nil
      attrs.delete("attribute_entries")
    end

    # Get the converted result of the child blocks.
    def content : String?
      @attributes.delete("title")
      super
    end

    # Convert the AsciiDoc document using the converter.
    def convert(opts : Hash(String, String) = {} of String => String) : String?
      parse unless @parsed

      output = if @doctype == "inline"
                 if (block = @blocks[0]? || @header)
                   if block.content_model == ContentModel::Compound || block.content_model == ContentModel::Empty
                     logger.warn { "no inline candidate; use the inline doctype to convert a single paragraph, verbatim, or raw block" }
                     nil
                   else
                     block.content
                   end
                 else
                   nil
                 end
               else
                 transform = if @options["standalone"]?
                               "document"
                             else
                               "embedded"
                             end
                 if (conv = @converter)
                   conv.convert(self, transform)
                 else
                   ""
                 end
               end
      output.is_a?(String) ? output : output.try(&.to_s)
    end

    # Increment a string like Ruby's String#next/succ
    # Increments the last alphanumeric character, carrying over as needed
    # For strings with no alphanumeric chars, increments the last character directly
    private def string_next(s : String) : String
      return "a" if s.empty?
      chars = s.chars
      i = chars.size - 1
      # Find last alphanumeric character
      while i >= 0 && !chars[i].alphanumeric?
        i -= 1
      end
      if i < 0
        # No alphanumeric chars: increment the last character directly
        chars[-1] = (chars[-1].ord + 1).chr
        return chars.join
      end
      # Increment from last alphanumeric char
      while i >= 0
        c = chars[i]
        if c.alphanumeric?
          if c == 'z'
            chars[i] = 'a'
            i -= 1
          elsif c == 'Z'
            chars[i] = 'A'
            i -= 1
          elsif c == '9'
            chars[i] = '0'
            i -= 1
          else
            chars[i] = (c.ord + 1).chr
            return chars.join
          end
        else
          i -= 1
        end
      end
      # All alphanumeric chars wrapped around, prepend first char type
      first = chars.find(&.alphanumeric?) || 'a'
      if first.uppercase?
        "A" + chars.join
      elsif first.lowercase?
        "a" + chars.join
      else
        "1" + chars.join
      end
    end

    # Get the named counter and take the next number in the sequence.
    def counter(name : String, seed : String | Int32 | Nil = nil) : String | Int32
      return @parent_document.not_nil!.counter(name, seed) if @parent_document
      locked = attribute_locked?(name)
      if (locked && (curr_val = @counters[name]?)) || (cv = @attributes[name]?) && !cv.empty?
        actual_val = curr_val || cv.not_nil!
        case actual_val
        when Int32
          next_val = actual_val + 1
        when String
          if actual_val == actual_val.to_i?.try(&.to_s)
            next_val = actual_val.to_i + 1
          else
            next_val = string_next(actual_val)
          end
        else
          next_val = 1
        end
        @counters[name] = next_val
      elsif seed
        case seed
        when Int32
          next_val = seed
        when String
          if seed == seed.to_i?.try(&.to_s)
            next_val = seed.to_i
          else
            next_val = seed
          end
        else
          next_val = 1
        end
        @counters[name] = next_val
      else
        next_val = 1
        @counters[name] = next_val
      end
      unless locked
        @attributes[name] = next_val.to_s
      end
      next_val
    end

    # Create or retrieve the converter for this document.
    # Uses the DefaultRegistry to find a converter matching the backend.
    def create_converter : Converter::Base
      if (existing = @converter)
        return existing
      end

      converter = Converter::DefaultRegistry.create(@backend)
      unless converter
        converter = Converter::Html5Converter.new
      end
      @converter = converter
      converter
    end

    # Internal: Create and initialize an instance of the converter for this document.
    def create_converter(backend_name : String) : Converter::Base
      case backend_name
      when "html5", "html", "xhtml5", "xhtml"
        Converter::Html5Converter.new(backend_name)
      when "docbook5", "docbook", "docbook45"
        Converter::DocBook5Converter.new(backend_name)
      when "manpage"
        Converter::ManPageConverter.new(backend_name)
      else
        Converter::Html5Converter.new("html5")
      end
    end

    # Delete the specified attribute from the document if the name is not locked.
    def delete_attribute(name : String) : Bool
      if attribute_locked?(name)
        false
      else
        @attributes.delete(name)
        @attributes_modified << name
        true
      end
    end

    # Read the docinfo file(s) for inclusion in the document template.
    def docinfo(location : Symbol = :head, suffix : String? = nil) : String
      if @safe < SafeMode::SECURE
        qualifier = location == :head ? "" : "-#{location}"
        actual_suffix = suffix || @outfilesuffix

        docinfo_val = @attributes["docinfo"]?
        if docinfo_val.nil? || docinfo_val.empty?
          if @attributes.has_key?("docinfo2")
            docinfo_keywords = ["private", "shared"]
          elsif @attributes.has_key?("docinfo1")
            docinfo_keywords = ["shared"]
          elsif docinfo_val
            docinfo_keywords = ["private"]
          else
            docinfo_keywords = nil
          end
        else
          docinfo_keywords = docinfo_val.split(',').map(&.strip)
        end

        if docinfo_keywords
          content_parts = [] of String
          docinfo_file = "docinfo#{qualifier}#{actual_suffix}"

          unless (docinfo_keywords & ["shared", "shared-#{location}"]).empty?
            docinfo_path = normalize_system_path(docinfo_file, @attributes["docinfodir"]?)
            if File.exists?(docinfo_path)
              shared_docinfo = File.read(docinfo_path)
              content_parts << apply_subs(shared_docinfo, [:attributes])
            end
          end

          docname = @attributes["docname"]?
          unless docname.nil? || docname.empty? || (docinfo_keywords & ["private", "private-#{location}"]).empty?
            docinfo_path = normalize_system_path("#{docname}-#{docinfo_file}", @attributes["docinfodir"]?)
            if File.exists?(docinfo_path)
              private_docinfo = File.read(docinfo_path)
              content_parts << apply_subs(private_docinfo, [:attributes])
            end
          end

          return content_parts.join(LF)
        end
      end
      ""
    end

    def document : Document
      self
    end

    # Get the doctitle as a String.
    def doctitle(opts : Hash(Symbol, Bool) = {} of Symbol => Bool) : String?
      if (hdr = @header)
        hdr.title
      elsif (dt = @attributes["doctitle"]?)
        dt
      elsif @title
        @title
      elsif opts[:use_fallback]?
        @attributes["untitled-label"]? || "Untitled"
      else
        nil
      end
    end

    # Get the document title as a Title object.
    def doctitle_as_title(separator : String = ":") : Title?
      if dt = doctitle
        Title.new(dt, separator)
      end
    end

    def document : Document
      self
    end

    # Check if the document is embedded.
    def embedded? : Bool
      @attributes.has_key?("embedded")
    end

    # Check if the document has extensions.
    def extensions? : Bool
      !@extensions.nil?
    end

    # Get the extensions registry, raising if nil.
    def extensions! : Extensions::Registry
      @extensions.not_nil!
    end

    # Internal: Assign the local and document datetime attributes.
    def fill_datetime_attributes(attrs : Hash(String, String), input_mtime : Time? = nil) : Nil
      now = Time.local
      if !(localdate = attrs["localdate"]?)
        localdate = now.to_s("%F")
        attrs["localdate"] = localdate
        attrs["localyear"] ||= now.year.to_s
      else
        attrs["localyear"] ||= localdate.index('-') == 4 ? localdate[0, 4] : ""
      end

      offset = now.offset
      tz_str = offset == 0 ? "UTC" : now.to_s("%z")
      localtime = attrs["localtime"]? || (now.to_s("%T") + " " + tz_str)
      attrs["localtime"] ||= localtime
      attrs["localdatetime"] ||= "#{localdate} #{localtime}"

      input_time = input_mtime || now
      if !(docdate = attrs["docdate"]?)
        docdate = input_time.to_s("%F")
        attrs["docdate"] = docdate
        attrs["docyear"] ||= input_time.year.to_s
      else
        attrs["docyear"] ||= docdate.index('-') == 4 ? docdate[0, 4] : ""
      end

      doc_offset = input_time.offset
      doc_tz_str = doc_offset == 0 ? "UTC" : input_time.to_s("%z")
      doctime = attrs["doctime"]? || (input_time.to_s("%T") + " " + doc_tz_str)
      attrs["doctime"] ||= doctime
      attrs["docdatetime"] ||= "#{docdate} #{doctime}"
      nil
    end

    # Finalize the document header after parsing.
    def finalize_header(block_attrs : Hash(String, String), apply_header : Bool = true) : Hash(String, String)
      block_attrs.each do |key, val|
        @attributes[key] = val unless @attributes.has_key?(key)
      end
      clear_playback_attributes(block_attrs)
      save_attributes
      # Create a header Section if the document has a title
      if apply_header && (doctitle = @attributes["doctitle"]?) && !doctitle.empty?
        header_section = Section.new(self, self, 0)
        header_section.title = doctitle
        @header = header_section
      end
      block_attrs
    end

    # Get the first section of the document.
    def first_section : Section?
      if (hdr = @header)
        return hdr
      end
      @blocks.each do |block|
        return block.as(Section) if block.is_a?(Section)
      end
      nil
    end

    # Get the footnotes.
    def footnotes : Array(Footnote)
      @catalog.footnotes
    end

    # Check whether this document has footnotes.
    def footnotes? : Bool
      !@catalog.footnotes.empty?
    end

    # Check whether this document has a header.
    def header? : Bool
      !@header.nil?
    end

    # Increment and store a counter.
    def increment_and_store_counter(counter_name : String, block : AbstractBlock? = nil) : String
      val = counter(counter_name)
      result = val.to_s
      if block
        entry = AttributeEntry.new(counter_name, result)
        entry.save_to(block.attributes)
      end
      result
    end

    # Initialize the syntax highlighter based on the source-highlighter attribute.
    def init_syntax_highlighter : SyntaxHighlighterBase?
      if basebackend?("html") && @safe <= SafeMode::SECURE
        if (source_hl_name = @attributes["source-highlighter"]?)
          @syntax_highlighter = SyntaxHighlighter::DefaultRegistry.create(source_hl_name, @backend)
        end
      end
      @syntax_highlighter
    end

    # Check if this is a multipart (book) document.
    def multipart? : Bool
      @doctype == "book" && @blocks.any? { |b| b.context == :section && b.level == 0 }
    end

    # Check if the document is nested (i.e., has a parent document).
    def nested? : Bool
      !@parent_document.nil?
    end

    # Check if the document should not render a footer.
    def nofooter : Bool
      @attributes.has_key?("nofooter")
    end

    # Check if the document should not render a header.
    def noheader : Bool
      @attributes.has_key?("noheader")
    end

    # Check if the document should not render a title.
    def notitle : Bool
      @attributes.has_key?("notitle")
    end

    # Parse the AsciiDoc source stored in the Reader into an abstract syntax tree.
    def parse(data : Array(String) | String | Nil = nil) : self
      return self if @parsed
      if data
        @reader = Reader.new(data, Cursor.new(@attributes["docfile"]?, @base_dir))
      end
      # Sync sourcemap setting to the reader (may have been changed after reader creation)
      if (reader = @reader)
        if reader.is_a?(PreprocessorReader)
          reader.sourcemap = @sourcemap
        end
        if @sourcemap
          @source_location_doc = reader.cursor.to_source_location
        end
        Parser.parse(reader, self)
      end
      restore_attributes
      @parsed = true
      self
    end

    # Check whether the source has been parsed.
    def parsed? : Bool
      @parsed
    end

    # Replay attribute assignments at the block level.
    # Processes __attr_entries__ stored in block attributes during parsing.
    def playback_attributes(attrs : Hash(String, String)) : Nil
      return unless (entries_str = attrs["__attr_entries__"]?)
      entries_str.split("\u0001").each do |entry|
        parts = entry.split("\u0000", 2)
        next if parts.size < 2
        name = parts[0]
        value = parts[1]
        if value == "\u0002" # negate signal
          @attributes.delete(name)
        else
          @attributes[name] = value
        end
      end
    end

    # Register a reference in the document catalog.
    def register(type : Symbol, value : String | Array(String) | Tuple(String, AbstractNode)) : AbstractNode?
      case type
      when :ids
        if value.is_a?(Tuple(String, AbstractNode))
          @catalog.refs[value[0]] ||= value[1]
        end
      when :refs
        if value.is_a?(Tuple(String, AbstractNode))
          id = value[0]
          ref = value[1]
          unless @catalog.refs.has_key?(id)
            @catalog.refs[id] = ref
            return ref
          end
          nil
        end
      when :footnotes
        # handled separately
        nil
      when :images
        @catalog.images << ImageReference.new(value.as(String), @attributes["imagesdir"]? || "") if value.is_a?(String)
        nil
      when :includes
        @catalog.includes[value.as(String)] = true if value.is_a?(String)
        nil
      when :links
        @catalog.links << value.as(String) if value.is_a?(String)
        nil
      else
        nil
      end
    end

    # Resolve a string to an id.
    def resolve_id(text : String) : String?
      @catalog.refs.each do |id, node|
        if node.is_a?(AbstractBlock)
          return id if node.title == text
        end
      end
      nil
    end

    # Restore the attributes to the previously saved state (attributes in header).
    def restore_attributes : Nil
      @catalog.callouts.rewind unless @parent_document
      if (saved = @header_attributes)
        @attributes.clear
        saved.each { |k, v| @attributes[k] = v }
      end
    end

    # Get the revision date.
    def revdate : String?
      @attributes["revdate"]?
    end

    # Internal: Branch the attributes so that the original state can be restored
    # at a future time.
    def save_attributes : Nil
      attrs = @attributes

      unless attrs.has_key?("doctitle") || !(doctitle_val = doctitle)
        attrs["doctitle"] = doctitle_val
      end

      @id ||= attrs["css-signature"]?

      # Handle toc attributes
      if (toc_val = (attrs.delete("toc2") ? "left" : attrs["toc"]?))
        toc_placement_val = attrs.fetch("toc-placement", "macro")
        toc_position_val = toc_placement_val != "auto" ? toc_placement_val : attrs["toc-position"]?
        unless toc_val.empty? && (toc_position_val.nil? || toc_position_val.empty?)
          default_toc_position = "left"
          default_toc_class : String? = "toc2"
          position = (toc_position_val.nil? || toc_position_val.empty?) ? (toc_val.empty? ? default_toc_position : toc_val) : toc_position_val
          attrs["toc"] = ""
          attrs["toc-placement"] = "auto"
          case position
          when "left", "<", "&lt;"
            attrs["toc-position"] = "left"
          when "right", ">", "&gt;"
            attrs["toc-position"] = "right"
          when "top", "^"
            attrs["toc-position"] = "top"
          when "bottom", "v"
            attrs["toc-position"] = "bottom"
          when "preamble", "macro"
            attrs["toc-position"] = "content"
            attrs["toc-placement"] = position
            default_toc_class = nil
          else
            attrs.delete("toc-position")
            default_toc_class = nil
          end
          if default_toc_class && !attrs.has_key?("toc-class")
            attrs["toc-class"] = default_toc_class
          end
        end
      end

      # Handle icons attribute
      if (icons_val = attrs["icons"]?) && !attrs.has_key?("icontype")
        case icons_val
        when "", "font"
          # nothing to do
        else
          attrs["icons"] = ""
          attrs["icontype"] = icons_val unless icons_val == "image"
        end
      end

      @compat_mode = attrs.has_key?("compat-mode")

      # In compat-mode, alias 'language' to 'source-language'
      if @compat_mode && (lang_val = attrs["language"]?)
        attrs["source-language"] ||= lang_val
      end

      # Initialize max_attribute_value_size
      # In SECURE mode, default to 4096 bytes; can be overridden by max-attribute-value-size attribute
      if (max_size_str = attrs["max-attribute-value-size"]?)
        if max_size_str.empty?
          @max_attribute_value_size = nil  # disabled
        elsif (max_size = max_size_str.to_i?)
          @max_attribute_value_size = max_size
        end
      elsif @safe >= SafeMode::SECURE
        @max_attribute_value_size = 4096
      end

      unless @parent_document
        @outfilesuffix = attrs["outfilesuffix"]? || @outfilesuffix

        # Unfreeze flexible attributes
        FLEXIBLE_ATTRIBUTES.each do |name|
          if @attribute_overrides.has_key?(name) && @attribute_overrides[name]
            @attribute_overrides.delete(name)
          end
        end
      end

      @header_attributes = attrs.dup
    end

    # Write the output to the specified file.
    def save_to(output : String, target : String) : Nil
      write(output, target)
    end

    # Check whether this Document has any child Section objects.
    def sections? : Bool
      next_section_index > 0
    end

    # Set the specified attribute on the document if the name is not locked.
    def set_attribute(name : String, value : String = "") : String?
      return nil if attribute_locked?(name)
      actual_value = value.empty? ? value : apply_attribute_value_subs(value)
      # Limit attribute value size if max_attribute_value_size is set
      if !actual_value.empty? && (max_size = @max_attribute_value_size)
        if actual_value.bytesize > max_size
          # Truncate at byte boundary without mangling multibyte chars
          byte_slice = actual_value.to_slice[0, max_size]
          actual_value = String.new(byte_slice)
          # Fix potential truncated multibyte char at end
          while !actual_value.valid_encoding?
            byte_slice = byte_slice[0, byte_slice.size - 1]
            actual_value = String.new(byte_slice)
          end
        end
      end
      if @header_attributes
        @attributes[name] = actual_value
        # In compat-mode, alias 'language' to 'source-language'
        if name == "language" && @compat_mode
          @attributes["source-language"] = actual_value
        end
      else
        case name
        when "backend"
          update_backend_attributes(actual_value)
        when "doctype"
          update_doctype_attributes(actual_value)
        else
          @attributes[name] = actual_value
          # In compat-mode, alias 'language' to 'source-language'
          if name == "language" && @compat_mode
            @attributes["source-language"] = actual_value
          end
        end
        @attributes_modified << name
      end
      actual_value
    end

    # Assign a value to the specified attribute in the document header.
    def set_header_attribute(name : String, value : String = "", overwrite : Bool = true) : Bool
      attrs = @header_attributes || @attributes
      if !overwrite && attrs.has_key?(name)
        false
      else
        attrs[name] = value
        true
      end
    end

    # Make the raw source for the Document available.
    def source : String?
      @reader.try(&.source)
    end

    # Get the source lines of the document.
    def source_lines : Array(String)
      @reader.try(&.source_lines) || [] of String
    end

    # Internal: Update the backend attributes to reflect a change in the active backend.
    def update_backend_attributes(new_backend : String, init : Bool = false) : String?
      return nil unless init || new_backend != @backend
      attrs = @attributes
      current_backend = @backend
      current_basebackend = attrs["basebackend"]?
      current_doctype = @doctype

      actual_backend = new_backend
      if new_backend.starts_with?("xhtml")
        attrs["htmlsyntax"] = "xml"
        actual_backend = new_backend[1..]
      elsif new_backend.starts_with?("html")
        attrs["htmlsyntax"] ||= "html"
      end
      actual_backend = BACKEND_ALIASES[actual_backend]? || actual_backend

      # Clean up old backend attributes
      if current_doctype
        if current_backend != ""
          attrs.delete("backend-#{current_backend}")
          attrs.delete("backend-#{current_backend}-doctype-#{current_doctype}")
        end
        attrs["backend-#{actual_backend}-doctype-#{current_doctype}"] = ""
        attrs["doctype-#{current_doctype}"] = ""
      elsif current_backend != ""
        attrs.delete("backend-#{current_backend}")
      end
      attrs["backend-#{actual_backend}"] = ""

      @backend = actual_backend
      attrs["backend"] = actual_backend

      # Create converter
      @converter = create_converter(actual_backend)

      # Derive backend traits
      new_basebackend = actual_backend.gsub(/\d+$/, "")
      new_filetype = DEFAULT_EXTENSIONS[new_basebackend]?.try { |ext| ext[1..] } || new_basebackend

      if init
        attrs["outfilesuffix"] ||= DEFAULT_EXTENSIONS[new_basebackend]? || ".#{new_filetype}"
      else
        unless attribute_locked?("outfilesuffix")
          attrs["outfilesuffix"] = DEFAULT_EXTENSIONS[new_basebackend]? || ".#{new_filetype}"
        end
      end

      # Update filetype attributes
      if (current_filetype = attrs["filetype"]?)
        attrs.delete("filetype-#{current_filetype}")
      end
      attrs["filetype"] = new_filetype
      attrs["filetype-#{new_filetype}"] = ""

      # Update page width
      if (page_width = DEFAULT_PAGE_WIDTHS[new_basebackend]?)
        attrs["pagewidth"] = page_width.to_s
      else
        attrs.delete("pagewidth")
      end

      # Update basebackend attributes
      if new_basebackend != current_basebackend
        if current_doctype
          if current_basebackend
            attrs.delete("basebackend-#{current_basebackend}")
            attrs.delete("basebackend-#{current_basebackend}-doctype-#{current_doctype}")
          end
          attrs["basebackend-#{new_basebackend}-doctype-#{current_doctype}"] = ""
        elsif current_basebackend
          attrs.delete("basebackend-#{current_basebackend}")
        end
        attrs["basebackend-#{new_basebackend}"] = ""
        attrs["basebackend"] = new_basebackend
      end

      actual_backend
    end

    # Internal: Update the doctype attributes to reflect a change in the active doctype.
    def update_doctype_attributes(new_doctype : String) : String?
      return nil unless new_doctype != @doctype
      attrs = @attributes
      current_backend = @backend
      current_basebackend = attrs["basebackend"]?
      current_doctype = @doctype

      if !current_doctype.empty?
        attrs.delete("doctype-#{current_doctype}")
        if !current_backend.empty?
          attrs.delete("backend-#{current_backend}-doctype-#{current_doctype}")
          attrs["backend-#{current_backend}-doctype-#{new_doctype}"] = ""
        end
        if current_basebackend
          attrs.delete("basebackend-#{current_basebackend}-doctype-#{current_doctype}")
          attrs["basebackend-#{current_basebackend}-doctype-#{new_doctype}"] = ""
        end
      else
        attrs["backend-#{current_backend}-doctype-#{new_doctype}"] = "" if !current_backend.empty?
        attrs["basebackend-#{current_basebackend}-doctype-#{new_doctype}"] = "" if current_basebackend
      end

      attrs["doctype-#{new_doctype}"] = ""
      @doctype = new_doctype
      attrs["doctype"] = new_doctype
      new_doctype
    end

    # Write the output to the specified file.
    def write(output : String?, target : String) : Nil
      return if output.nil? || output.empty?
      File.write(target, output.chomp + "\n")
    end

    # Generate cross reference text for this document.
    def xreftext(xrefstyle : String? = nil) : String?
      doctitle
    end
  end

  # The document catalog that stores references, footnotes, images, etc.
  class Catalog
    property callouts : Callouts
    property footnotes : Array(Document::Footnote)
    property images : Array(Document::ImageReference)
    property includes : Hash(String, Bool)
    property links : Array(String)
    property refs : Hash(String, AbstractNode)

    def initialize
      @callouts = Callouts.new
      @footnotes = [] of Document::Footnote
      @images = [] of Document::ImageReference
      @includes = {} of String => Bool
      @links = [] of String
      @refs = {} of String => AbstractNode
    end
  end

  module Extensions
  end
end
