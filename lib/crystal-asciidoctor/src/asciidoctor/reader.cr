module Asciidoctor
  # A Cursor tracks the file, directory, path, and line number of a position
  # in the source.
  class Cursor
    getter dir : String
    getter file : String?
    getter lineno : Int32
    getter path : String

    def initialize(file : String? = nil, dir : String? = nil, path : String? = nil, @lineno : Int32 = 1)
      @file = file
      if file
        @dir = dir || File.dirname(file)
        @path = path || File.basename(file)
      else
        @dir = dir || "."
        @path = path || "<stdin>"
      end
    end

    def advance(num : Int32) : Nil
      @lineno += num
    end

    def line_info : String
      "#{@path}: line #{@lineno}"
    end

    def to_s(io : IO) : Nil
      io << line_info
    end

    def to_source_location : SourceLocation
      SourceLocation.new(@file, @lineno, @dir, @path)
    end
  end

  # Methods for retrieving lines from AsciiDoc source files.
  class Reader
    include Logging

    getter dir : String
    getter file : String?
    getter lineno : Int32
    getter path : String
    getter source_lines : Array(String)

    property process_lines : Bool
    property unterminated : Bool?

    @lines : Array(String)
    @look_ahead : Int32
    @mark : Tuple(String?, String, String, Int32)?
    @saved : NamedTuple(
      lines: Array(String),
      file: String?,
      dir: String,
      path: String,
      lineno: Int32,
      look_ahead: Int32,
      process_lines: Bool,
    )?
    @unescape_next_line : Bool

    def initialize(data : Array(String) | String | Nil = nil, cursor : Cursor | String | Nil = nil, opts = {} of Symbol => String | Bool)
      @file = nil
      @dir = "."
      @path = "<stdin>"
      @lineno = 1

      case cursor
      when String
        @file = cursor
        @dir = File.dirname(cursor)
        @path = File.basename(cursor)
      when Cursor
        @file = cursor.file
        @dir = cursor.dir
        @path = cursor.path
        @lineno = cursor.lineno
      end

      @source_lines = prepare_lines(data, opts)
      @lines = @source_lines.reverse
      @mark = nil
      @look_ahead = 0
      # Allow disabling line processing via opts[:process_lines]
      process_lines_opt = opts[:process_lines]?
      @process_lines = process_lines_opt.nil? ? true : (process_lines_opt == true)
      @unescape_next_line = false
      @unterminated = nil
      @saved = nil
    end

    # Advance to the next line by discarding the line at the front of the stack.
    def advance : Bool
      shift ? true : false
    end

    # Return a Cursor for the current position.
    def cursor : Cursor
      Cursor.new(@file, @dir, @path, @lineno)
    end

    # Return a Cursor at the specified line number.
    def cursor_at_line(lineno : Int32) : Cursor
      Cursor.new(@file, @dir, @path, lineno)
    end

    # Return a Cursor at the marked position.
    def cursor_at_mark : Cursor
      if (m = @mark)
        Cursor.new(m[0], m[1], m[2], m[3])
      else
        cursor
      end
    end

    # Return a Cursor one line before the marked position.
    def cursor_before_mark : Cursor
      if (m = @mark)
        Cursor.new(m[0], m[1], m[2], m[3] - 1)
      else
        Cursor.new(@file, @dir, @path, @lineno - 1)
      end
    end

    # Return a Cursor at the previous line.
    def cursor_at_prev_line : Cursor
      Cursor.new(@file, @dir, @path, @lineno - 1)
    end

    # Discard a previous saved state.
    def discard_save : Nil
      @saved = nil
    end

    # Check whether this reader is empty (contains no lines).
    def empty? : Bool
      if @lines.empty?
        @look_ahead = 0
        true
      else
        false
      end
    end

    # Alias for empty?
    def eof? : Bool
      empty?
    end

    # Check whether there are any lines left to read.
    def has_more_lines? : Bool
      if @lines.empty?
        @look_ahead = 0
        false
      else
        true
      end
    end

    # Get information about the last line read.
    def line_info : String
      "#{@path}: line #{@lineno}"
    end

    # Get a copy of the remaining lines.
    def lines : Array(String)
      @lines.reverse
    end

    # Mark the current position.
    def mark : Nil
      @mark = {@file, @dir, @path, @lineno}
      nil
    end

    # Peek at the next line and check if it's empty (i.e., whitespace only).
    def next_line_empty? : Bool
      line = peek_line
      line.nil? || line.empty?
    end

    # Peek at the next line of source data. Processes the line if not
    # already marked as processed, but does not consume it.
    def peek_line(direct : Bool = false) : String?
      loop do
        next_line = @lines.last?
        if direct || @look_ahead > 0
          return next_line.nil? ? nil : (@unescape_next_line ? next_line[1..] : next_line)
        end
        if next_line
          line = process_line(next_line)
          return line if line
        else
          @look_ahead = 0
          return nil
        end
      end
    end

    # Peek at the next multiple lines of source data.
    def peek_lines(num : Int32? = nil, direct : Bool = false) : Array(String)
      old_look_ahead = @look_ahead
      result = [] of String
      max = num || @lines.size
      max.times do
        line = direct ? shift : read_line
        if line
          result << line
        else
          @lineno -= 1 if direct
          break
        end
      end

      unless result.empty?
        unshift_all(result)
        @look_ahead = old_look_ahead if direct
      end

      result
    end

    # Get the remaining lines of source data joined as a String.
    def read : String
      read_lines.join(LF)
    end

    # Get the next line of source data. Consumes the line returned.
    def read_line : String?
      shift if @look_ahead > 0 || has_more_lines?
    end

    # Get the remaining lines of source data.
    def read_lines : Array(String)
      lines = [] of String
      while has_more_lines?
        line = shift
        lines << line if line
      end
      lines
    end

    # Return all lines until a terminator, blank line, or block condition.
    def read_lines_until(
      terminator : String? = nil,
      break_on_blank_lines : Bool = false,
      break_on_list_continuation : Bool = false,
      skip_first_line : Bool = false,
      preserve_last_line : Bool = false,
      read_last_line : Bool = false,
      skip_line_comments : Bool = false,
      skip_processing : Bool = false,
      context : Symbol? = nil,
      cursor_at : Cursor? = nil,
      &block : String -> Bool
    ) : Array(String)
      read_lines_until_impl(
        terminator: terminator,
        break_on_blank_lines: break_on_blank_lines,
        break_on_list_continuation: break_on_list_continuation,
        skip_first_line: skip_first_line,
        preserve_last_line: preserve_last_line,
        read_last_line: read_last_line,
        skip_line_comments: skip_line_comments,
        skip_processing: skip_processing,
        context: context,
        cursor_at: cursor_at,
        &block
      )
    end

    # Overload without block.
    def read_lines_until(
      terminator : String? = nil,
      break_on_blank_lines : Bool = false,
      break_on_list_continuation : Bool = false,
      skip_first_line : Bool = false,
      preserve_last_line : Bool = false,
      read_last_line : Bool = false,
      skip_line_comments : Bool = false,
      skip_processing : Bool = false,
      context : Symbol? = nil,
      cursor_at : Cursor? = nil
    ) : Array(String)
      read_lines_until_impl(
        terminator: terminator,
        break_on_blank_lines: break_on_blank_lines,
        break_on_list_continuation: break_on_list_continuation,
        skip_first_line: skip_first_line,
        preserve_last_line: preserve_last_line,
        read_last_line: read_last_line,
        skip_line_comments: skip_line_comments,
        skip_processing: skip_processing,
        context: context,
        cursor_at: cursor_at,
      )
    end

    # Replace the next line with the specified line.
    def replace_next_line(replacement : String) : Bool
      shift
      unshift(replacement)
      true
    end

    # Restore the state of the reader.
    def restore_save : Nil
      if (saved = @saved)
        @lines = saved[:lines]
        @file = saved[:file]
        @dir = saved[:dir]
        @path = saved[:path]
        @lineno = saved[:lineno]
        @look_ahead = saved[:look_ahead]
        @process_lines = saved[:process_lines]
        @saved = nil
      end
    end

    # Save the state of the reader.
    def save : Nil
      @saved = {
        lines:         @lines.dup,
        file:          @file,
        dir:           @dir,
        path:          @path,
        lineno:        @lineno,
        look_ahead:    @look_ahead,
        process_lines: @process_lines,
      }
      nil
    end

    # Skip blank lines at the cursor.
    # Also skips LIST_CONTINUATION_PLACEHOLDER lines (treated as blank in Ruby AsciiDoctor).
    def skip_blank_lines : Int32?
      return nil if empty?

      num_skipped = 0
      while (next_line = peek_line)
        return num_skipped unless next_line.empty? || next_line == LIST_CONTINUATION_PLACEHOLDER
        shift
        num_skipped += 1
      end
      nil
    end

    # Skip consecutive comment lines and block comments.
    def skip_comment_lines : Nil
      return if empty?

      while (next_line = peek_line) && !next_line.empty?
        break unless next_line.starts_with?("//")
        if next_line.starts_with?("///")
          ll = next_line.size
          break unless ll > 3 && next_line == "/" * ll
          read_lines_until(terminator: next_line, skip_first_line: true, read_last_line: true, skip_processing: true, context: :comment)
        else
          shift
        end
      end

      nil
    end

    # Skip consecutive comment lines and return them.
    def skip_line_comments : Array(String)
      return [] of String if empty?

      comment_lines = [] of String
      while (next_line = peek_line) && !next_line.empty?
        break unless next_line.starts_with?("//")
        line = shift
        comment_lines << line if line
      end

      comment_lines
    end

    # Get the source lines joined as a String.
    def source : String
      @source_lines.join(LF)
    end

    # Get a copy of the remaining lines joined as a String.
    def string : String
      @lines.reverse.join(LF)
    end

    # Advance to the end, consuming all remaining lines.
    def terminate : Nil
      @lineno += @lines.size
      @lines.clear
      @look_ahead = 0
      nil
    end

    def to_s(io : IO) : Nil
      io << "#<#{self.class} {path: #{@path.inspect}, line: #{@lineno}}>"
    end

    # Push a line onto the beginning of the Array of source data.
    def unshift_line(line_to_restore : String) : Nil
      unshift(line_to_restore)
      nil
    end

    # Push an Array of lines onto the front of the Array of source data.
    def unshift_lines(lines_to_restore : Array(String)) : Nil
      unshift_all(lines_to_restore)
    end

    # --------------------------------------------------------------------------
    # Protected / private methods
    # --------------------------------------------------------------------------

    # Prepare the source data for parsing.
    protected def prepare_lines(data : Array(String) | String | Nil, opts = {} of Symbol => String | Bool) : Array(String)
      normalize = opts[:normalize]?
      if normalize
        case data
        when Array(String)
          Helpers.prepare_source_array(data, normalize != :chomp)
        when String
          Helpers.prepare_source_string(data, normalize != :chomp)
        else
          [] of String
        end
      else
        case data
        when Array(String)
          data.dup
        when String
          data.chomp.split(LF, remove_empty: false)
        else
          [] of String
        end
      end
    end

    # Process a previously unvisited line.
    protected def process_line(line : String) : String?
      @look_ahead += 1 if @process_lines
      line
    end

    # Internal implementation for read_lines_until (with block).
    private def read_lines_until_impl(
      terminator : String? = nil,
      break_on_blank_lines : Bool = false,
      break_on_list_continuation : Bool = false,
      skip_first_line : Bool = false,
      preserve_last_line : Bool = false,
      read_last_line : Bool = false,
      skip_line_comments : Bool = false,
      skip_processing : Bool = false,
      context : Symbol? = nil,
      cursor_at : Cursor? = nil,
      &block : String -> Bool
    ) : Array(String)
      result = [] of String
      restore_process_lines = false
      if @process_lines && skip_processing
        @process_lines = false
        restore_process_lines = true
      end

      start_cursor = cursor_at || cursor
      line_read = false
      line_restored = false

      shift if skip_first_line

      while (line = read_line)
        is_list_cont = break_on_list_continuation && line_read && (line == LIST_CONTINUATION || line == LIST_CONTINUATION_PLACEHOLDER)
        should_break = if terminator
                         line == terminator
                       else
                         (break_on_blank_lines && line.empty?) ||
                           is_list_cont ||
                           (yield line)
                       end
        if should_break
          result << line if read_last_line
          if preserve_last_line || is_list_cont
            unshift(line)
            line_restored = true
          end
          break
        end
        unless skip_line_comments && line.starts_with?("//") && !line.starts_with?("///")
          result << line
          line_read = true
        end
      end

      if restore_process_lines
        @process_lines = true
        @look_ahead -= 1 if line_restored && !terminator
      end

      if terminator && terminator != line
        effective_context = context || terminator
        logger.warn { "unterminated #{effective_context} block at #{start_cursor}" }
        @unterminated = true
      end

      result
    end

    # Internal implementation for read_lines_until (without block).
    private def read_lines_until_impl(
      terminator : String? = nil,
      break_on_blank_lines : Bool = false,
      break_on_list_continuation : Bool = false,
      skip_first_line : Bool = false,
      preserve_last_line : Bool = false,
      read_last_line : Bool = false,
      skip_line_comments : Bool = false,
      skip_processing : Bool = false,
      context : Symbol? = nil,
      cursor_at : Cursor? = nil
    ) : Array(String)
      result = [] of String
      restore_process_lines = false
      if @process_lines && skip_processing
        @process_lines = false
        restore_process_lines = true
      end

      start_cursor = cursor_at || cursor
      line_read = false
      line_restored = false

      shift if skip_first_line

      while (line = read_line)
        is_list_cont = break_on_list_continuation && line_read && (line == LIST_CONTINUATION || line == LIST_CONTINUATION_PLACEHOLDER)
        should_break = if terminator
                         line == terminator
                       else
                         (break_on_blank_lines && line.empty?) ||
                           is_list_cont
                       end
        if should_break
          result << line if read_last_line
          if preserve_last_line || is_list_cont
            unshift(line)
            line_restored = true
          end
          break
        end
        unless skip_line_comments && line.starts_with?("//") && !line.starts_with?("///")
          result << line
          line_read = true
        end
      end

      if restore_process_lines
        @process_lines = true
        @look_ahead -= 1 if line_restored && !terminator
      end

      if terminator && terminator != line
        effective_context = context || terminator
        logger.warn { "unterminated #{effective_context} block at #{start_cursor}" }
        @unterminated = true
      end

      result
    end

    # Shift the line off the stack and increment the lineno.
    protected def shift : String?
      return nil if @lines.empty?
      @lineno += 1
      @look_ahead -= 1 unless @look_ahead == 0
      line = @lines.pop
      if @unescape_next_line
        @unescape_next_line = false
        line ? line[1..] : nil
      else
        line
      end
    end

    # Restore the line to the stack and decrement the lineno.
    protected def unshift(line : String) : Nil
      @lineno -= 1
      @look_ahead += 1
      @lines.push(line)
      nil
    end

    # Restore lines to the stack and decrement the lineno.
    protected def unshift_all(lines_to_restore : Array(String)) : Nil
      @lineno -= lines_to_restore.size
      @look_ahead += lines_to_restore.size
      lines_to_restore.reverse_each { |l| @lines.push(l) }
      nil
    end
  end

  # Public: Methods for retrieving lines from AsciiDoc source files, evaluating
  # preprocessor directives as each line is read off the Array of lines.
  class PreprocessorReader < Reader
    # The include stack tracks nested includes.
    getter include_stack : Array(Tuple(Array(String), String?, String, String, Int32, NamedTuple(abs: Int32, curr: Int32, rel: Int32)?, Bool))

    # The document this reader is associated with.
    getter document : Document

    # Whether the reader is currently skipping lines (inside a false conditional).
    property? skipping : Bool

    # The stack of conditional directives being tracked.
    getter conditional_stack : Array(NamedTuple(name: String, target: String?, skip: Bool, skipping: Bool, expr: String?, source_location: SourceLocation?))

    # The maximum include depth configuration.
    @maxdepth : NamedTuple(abs: Int32, curr: Int32, rel: Int32)?

    # Include processor extensions (nil = not checked, false-like = none).
    @include_processor_extensions : Bool

    # The includes catalog from the document.
    @includes : Hash(String, Bool)

    # Whether source map is enabled.
    property sourcemap : Bool = false

    def initialize(@document : Document, data : Array(String) | String | Nil = nil, cursor : Cursor | String | Nil = nil, opts = {} of Symbol => String | Bool)
      @sourcemap = @document.sourcemap?
      if @document.attributes.has_key?("skip-front-matter") && !opts.has_key?(:skip_front_matter)
        opts = opts.dup
        opts[:skip_front_matter] = true
      end
      super(data, cursor, opts)

      default_include_depth = (@document.attributes["max-include-depth"]? || "64").to_i
      if default_include_depth > 0
        @maxdepth = {abs: default_include_depth, curr: default_include_depth, rel: default_include_depth}
      else
        @maxdepth = nil
      end

      @include_stack = [] of Tuple(Array(String), String?, String, String, Int32, NamedTuple(abs: Int32, curr: Int32, rel: Int32)?, Bool)
      @includes = @document.catalog.includes
      @skipping = false
      @conditional_stack = [] of NamedTuple(name: String, target: String?, skip: Bool, skipping: Bool, expr: String?, source_location: SourceLocation?)
      @include_processor_extensions = false
    end

    # Create a Cursor for an include file.
    def create_include_cursor(file : String, path : String, lineno : Int32) : Cursor
      dir = File.dirname(file)
      Cursor.new(file, dir, path, lineno)
    end

    # Check whether this reader is empty (contains no lines).
    # Overrides Reader#empty? to pop the include stack if needed.
    def empty? : Bool
      peek_line ? false : true
    end

    # Alias for empty?
    def eof? : Bool
      empty?
    end

    # Reports whether pushing an include on the include stack exceeds the max include depth.
    #
    # Returns nil if no max depth is set and includes are disabled (max-include-depth=0),
    # false if the current max depth will not be exceeded, and the relative max include
    # depth if the current max depth will be exceeded.
    def exceeds_max_depth? : Int32?
      if (md = @maxdepth)
        @include_stack.size >= md[:curr] ? md[:rel] : nil
      else
        0 # includes disabled
      end
    end

    # Check whether there are any lines left to read.
    # Overrides Reader#has_more_lines? to use peek_line (which pops include stack).
    def has_more_lines? : Bool
      peek_line ? true : false
    end

    # Get the current include depth (number of includes on the stack).
    def include_depth : Int32
      @include_stack.size
    end

    # Check whether there are include processor extensions registered.
    def include_processors? : Bool
      # Simplified: Crystal port does not yet support extension registry
      false
    end

    # Override the Reader#peek_line method to pop the include stack if the last
    # line has been reached and there's at least one include on the stack.
    def peek_line(direct : Bool = false) : String?
      if (line = super)
        line
      elsif @include_stack.empty?
        # Report unterminated conditional directives
        @conditional_stack.each do |conditional|
          logger.error { "detected unterminated preprocessor conditional directive: #{conditional[:name]}::#{conditional[:target] || ""}[#{conditional[:expr] || ""}]" }
        end
        @conditional_stack.clear
        nil
      else
        pop_include
        peek_line(direct)
      end
    end

    # Pop the current include context off the stack and restore the previous context.
    def pop_include : Nil
      return if @include_stack.empty?
      entry = @include_stack.pop
      @lines = entry[0]
      @file = entry[1]
      @dir = entry[2]
      @path = entry[3]
      @lineno = entry[4]
      @maxdepth = entry[5]
      @process_lines = entry[6]
      @look_ahead = 0
      nil
    end

    # Internal: Preprocess the directive to conditionally include or exclude content.
    #
    # name      - The name of the conditional inclusion directive (ifdef, ifndef, ifeval, endif)
    # target    - The target, which is the name of one or more attributes
    # delimiter - The conditional delimiter for multiple attributes ('+' or ',')
    # text      - The text associated with this directive (between square brackets)
    #
    # Returns a Boolean indicating whether the cursor should be advanced.
    def preprocess_conditional_directive(name : String, target : String, delimiter : String?, text : String?) : Bool
      no_target = target.empty?
      target = target.downcase unless no_target

      if name == "endif"
        if text
          logger.error { "malformed preprocessor directive - text not permitted: endif::#{target}[#{text}]" }
        elsif @conditional_stack.empty?
          logger.error { "unmatched preprocessor directive: endif::#{target}[]" }
        elsif no_target || target == @conditional_stack.last[:target]
          @conditional_stack.pop
          @skipping = @conditional_stack.empty? ? false : @conditional_stack.last[:skipping]
        else
          logger.error { "mismatched preprocessor directive: endif::#{target}[], expected endif::#{@conditional_stack.last[:target] || ""}[]" }
        end
        return true
      elsif @skipping
        if name == "ifeval"
          return true unless no_target && text && EvalExpressionRx.matches?(text.strip)
        elsif no_target
          return true
        end
        skip = false
      else
        case name
        when "ifdef"
          if no_target
            logger.error { "malformed preprocessor directive - missing target: ifdef::[#{text}]" }
            return true
          end
          case delimiter
          when ","
            skip = target.split(",", remove_empty: false).none? { |attr_name| @document.attributes.has_key?(attr_name) }
          when "+"
            skip = target.split("+", remove_empty: false).any? { |attr_name| !@document.attributes.has_key?(attr_name) }
          else
            skip = !@document.attributes.has_key?(target)
          end
        when "ifndef"
          if no_target
            logger.error { "malformed preprocessor directive - missing target: ifndef::[#{text}]" }
            return true
          end
          case delimiter
          when ","
            skip = target.split(",", remove_empty: false).any? { |attr_name| @document.attributes.has_key?(attr_name) }
          when "+"
            skip = target.split("+", remove_empty: false).all? { |attr_name| @document.attributes.has_key?(attr_name) }
          else
            skip = @document.attributes.has_key?(target)
          end
        when "ifeval"
          if no_target
            if text && (m = EvalExpressionRx.match(text.strip))
              lhs_str = m[1]
              op = m[2]
              rhs_str = m[3]
              lhs = resolve_expr_val(lhs_str)
              rhs = resolve_expr_val(rhs_str)
              skip = !eval_compare(lhs, op, rhs)
            else
              logger.error { "malformed preprocessor directive - #{text ? "invalid expression" : "missing expression"}: ifeval::[#{text}]" }
              return true
            end
          else
            logger.error { "malformed preprocessor directive - target not permitted: ifeval::#{target}[#{text}]" }
            return true
          end
        else
          skip = false
        end
      end

      # conditional inclusion block
      if name == "ifeval"
        @skipping = true if skip
        @conditional_stack << {name: name, target: nil, skip: skip, skipping: @skipping, expr: text, source_location: @sourcemap ? cursor.to_source_location : nil}
      elsif text
        # single line conditional inclusion
        unless @skipping || skip
          replace_next_line(text.rstrip)
          unshift("")
          @look_ahead -= 1 if text.starts_with?("include::")
        end
      else
        # conditional inclusion block
        @skipping = true if skip
        @conditional_stack << {name: name, target: target, skip: skip, skipping: @skipping, expr: nil, source_location: @sourcemap ? cursor.to_source_location : nil}
      end

      true
    end

    # Internal: Preprocess the directive to include lines from another document.
    #
    # target   - The unsubstituted String name of the target document
    # attrlist - An attribute list String (text between square brackets)
    #
    # Returns a Boolean indicating whether the line under the cursor was changed.
    def preprocess_include_directive(target : String, attrlist : String?) : Bool
      doc = @document

      # If running in SafeMode::SECURE or greater, don't process this directive
      if doc.safe >= SafeMode::SECURE
        target_display = target.includes?(" ") ? "pass:c[#{target}]" : target
        link_attrlist = doc.attributes.has_key?("compat-mode") ? (attrlist || "") : "role=include#{attrlist ? ",#{attrlist}" : ""}"
        replace_next_line("link:#{target_display}[#{link_attrlist}]")
        return false
      end

      if @maxdepth.nil?
        logger.error { "includes are disabled (max-include-depth=0)" }
        return false
      end

      if (md = @maxdepth) && @include_stack.size >= md[:curr]
        logger.error { "maximum include depth of #{md[:rel]} exceeded" }
        return false
      end

      # Substitute attributes in target
      resolved_target = doc.sub_attributes(target)

      # Resolve the include path
      inc_path = doc.normalize_system_path(resolved_target, @dir)

      # Parse attributes from attrlist first (needed for opts=optional check)
      parsed_attrs = {} of String => String
      if attrlist && !attrlist.empty?
        attrlist.split(",").each do |entry|
          key, _, val = entry.partition("=")
          parsed_attrs[key.strip] = val.strip
        end
      end

      # Check for optional option
      optional = (parsed_attrs["opts"]? || "").split(";").includes?("optional")

      unless File.file?(inc_path)
        if optional
          # Skip silently if optional
          shift
          return true
        end
        logger.error { "include file not found: #{inc_path}" }
        replace_next_line("Unresolved directive in #{@path} - include::#{target}[#{attrlist}]")
        return false
      end

      # Determine line selection or tag selection
      inc_linenos = nil
      inc_tags = nil

      if parsed_attrs.has_key?("lines")
        inc_linenos = [] of Int32
        split_delimited_value(parsed_attrs["lines"]).each do |linedef|
          if linedef.includes?("..")
            from_str, _, to_str = linedef.partition("..")
            from = from_str.to_i
            if to_str.empty? || (to_val = to_str.to_i?) && to_val.not_nil! < 0
              # open-ended range: select from 'from' to end
              inc_linenos << from
              inc_linenos << -1 # sentinel for "to end"
            else
              to = to_str.to_i
              (from..to).each { |n| inc_linenos << n }
            end
          else
            inc_linenos << linedef.to_i
          end
        end
        inc_linenos = inc_linenos.empty? ? nil : inc_linenos.sort.uniq
      elsif parsed_attrs.has_key?("tag")
        tag = parsed_attrs["tag"]
        unless tag.empty? || tag == "!"
          if tag.starts_with?("!")
            inc_tags = {tag[1..] => false}
          else
            inc_tags = {tag => true}
          end
        end
      elsif parsed_attrs.has_key?("tags")
        inc_tags = {} of String => Bool
        split_delimited_value(parsed_attrs["tags"]).each do |tagdef|
          next if tagdef.empty? || tagdef == "!"
          if tagdef.starts_with?("!")
            inc_tags[tagdef[1..]] = false
          else
            inc_tags[tagdef] = true
          end
        end
        inc_tags = nil if inc_tags.empty?
      end

      relpath = target

      if inc_linenos
        include_by_lines(inc_path, inc_linenos, relpath, target, attrlist, parsed_attrs)
      elsif inc_tags
        include_by_tags(inc_path, inc_tags, relpath, target, attrlist, parsed_attrs)
      else
        include_full_file(inc_path, relpath, target, attrlist, parsed_attrs)
      end

      true
    end

    # Override process_line to handle preprocessor directives.
    protected def process_line(line : String) : String?
      return line unless @process_lines

      if line.empty?
        if @skipping
          shift
          return nil
        end
        @look_ahead += 1
        return line
      end

      # Optimized check: line must end with ']', not start with '[', and contain '::'
      if line.ends_with?(']') && !line.starts_with?('[') && line.includes?("::")
        if line.includes?("if") && (m = ConditionalDirectiveRx.match(line))
          if m[1]? == "\\"
            @unescape_next_line = true
            @look_ahead += 1
            return line[1..]
          elsif preprocess_conditional_directive(m[2], m[3], m[4]?, m[5]?)
            shift
            return nil
          else
            @look_ahead += 1
            return line
          end
        elsif @skipping
          shift
          return nil
        elsif (line.starts_with?("inc") || line.starts_with?("\\inc")) && (m = IncludeDirectiveRx.match(line))
          if m[1]? == "\\"
            @unescape_next_line = true
            @look_ahead += 1
            return line[1..]
          elsif preprocess_include_directive(m[2], m[3]?)
            return nil
          else
            @look_ahead += 1
            return line
          end
        else
          @look_ahead += 1
          return line
        end
      elsif @skipping
        shift
        return nil
      else
        @look_ahead += 1
        return line
      end
    end

    # Push source onto the front of the reader and switch the context
    # based on the file, document-relative path and line information given.
    def push_include(data : Array(String) | String, file : String? = nil, path : String? = nil, lineno : Int32 = 1, attributes : Hash(String, String) = {} of String => String) : self
      @include_stack << {@lines, @file, @dir, @path, @lineno, @maxdepth, @process_lines}

      if file
        @file = file
        @dir = File.dirname(file)
        @path = path || File.basename(file)
        # Only process lines in AsciiDoc files
        @process_lines = ASCIIDOC_EXTENSIONS.has_key?(File.extname(file))
        if @process_lines
          rootname = @path.rindex('.').try { |idx| @path[0...idx] } || @path
          @includes[rootname] ||= !(attributes.has_key?("partial-option"))
        end
      else
        @dir = "."
        @process_lines = true
        if (p = path)
          @path = p
          rootname = p.rindex('.').try { |idx| p[0...idx] } || p
          @includes[rootname] ||= !(attributes.has_key?("partial-option"))
        else
          @path = "<stdin>"
        end
      end

      @lineno = lineno

      # Handle depth attribute
      if (md = @maxdepth) && attributes.has_key?("depth")
        rel_maxdepth = attributes["depth"].to_i
        if rel_maxdepth > 0
          curr_maxdepth = @include_stack.size + rel_maxdepth
          abs_maxdepth = md[:abs]
          curr_maxdepth = abs_maxdepth if curr_maxdepth > abs_maxdepth
          @maxdepth = {abs: abs_maxdepth, curr: curr_maxdepth, rel: rel_maxdepth}
        else
          @maxdepth = {abs: md[:abs], curr: @include_stack.size, rel: 0}
        end
      end

      # Prepare the lines
      new_lines = case data
                  when Array(String)
                    data.dup
                  when String
                    data.chomp.split(LF, remove_empty: false)
                  end

      if new_lines.nil?
        pop_include
      else
        if new_lines.empty?
          # Empty data: push the include but set lines to empty
          # The reader will pop_include when it tries to read a line
          @lines = [] of String
        else
          # Handle leveloffset
          if attributes.has_key?("leveloffset")
            leveloffset = @document.attributes["leveloffset"]?
            prefix_line = leveloffset ? ":leveloffset: #{leveloffset}" : ":leveloffset!:"
            suffix_line = ":leveloffset: #{attributes["leveloffset"]}"
            @lines = ([suffix_line, ""] + new_lines.reverse + ["", prefix_line])
            @lineno -= 2
          else
            @lines = new_lines.reverse
          end
        end
        @look_ahead = 0
      end

      self
    end

    # Internal: Resolve the value of one side of an ifeval expression.
    #
    # Returns the resolved value (String, Int32, Float64, Bool, or Nil).
    def resolve_expr_val(val : String) : String | Int32 | Float64 | Bool | Nil
      if (val.starts_with?('"') && val.ends_with?('"')) ||
         (val.starts_with?('\'') && val.ends_with?('\''))
        quoted = true
        val = val[1...-1]
      else
        quoted = false
      end

      # Substitute attribute references
      if val.includes?(ATTR_REF_HEAD)
        val = @document.apply_subs(val, [:attributes])
      end

      if quoted
        val
      elsif val.empty?
        nil
      elsif val == "true"
        true
      elsif val == "false"
        false
      elsif val.strip.empty?
        " "
      elsif val.includes?('.')
        val.to_f64? || val
      else
        val.to_i? || val
      end
    end

    # Private: Ignore front-matter, commonly used in static site generators.
    #
    # data             - The Array of String source lines
    # increment_linenos - Whether to increment line numbers (default: true)
    #
    # Returns the Array of front-matter lines, or nil if not detected.
    def skip_front_matter!(data : Array(String), increment_linenos : Bool = true) : Array(String)?
      return nil if data.empty?
      delim = data[0]
      return nil unless delim == "---" || delim == "+++"

      original_data = data.dup
      data.shift
      front_matter = [] of String
      @lineno += 1 if increment_linenos

      until data.empty? || data[0] == delim
        front_matter << data.shift
        @lineno += 1 if increment_linenos
      end

      if data.empty?
        # Not valid front matter, restore
        data.clear
        original_data.each { |l| data << l }
        @lineno -= (original_data.size) if increment_linenos
        return nil
      end

      data.shift
      @lineno += 1 if increment_linenos
      front_matter
    end

    # Private: Split a delimited value on comma (if found), otherwise semi-colon.
    private def split_delimited_value(val : String) : Array(String)
      val.includes?(',') ? val.split(',') : val.split(';')
    end

    # Private: Evaluate a comparison expression.
    private def eval_compare(lhs : String | Int32 | Float64 | Bool | Nil, op : String, rhs : String | Int32 | Float64 | Bool | Nil) : Bool
      # Coerce both sides to comparable types
      case op
      when "=="
        lhs == rhs || lhs.to_s == rhs.to_s
      when "!="
        lhs != rhs && lhs.to_s != rhs.to_s
      when "<"
        compare_values(lhs, rhs) < 0
      when ">"
        compare_values(lhs, rhs) > 0
      when "<="
        compare_values(lhs, rhs) <= 0
      when ">="
        compare_values(lhs, rhs) >= 0
      else
        false
      end
    end

    # Private: Compare two values numerically if possible, otherwise as strings.
    private def compare_values(lhs : String | Int32 | Float64 | Bool | Nil, rhs : String | Int32 | Float64 | Bool | Nil) : Int32
      lhs_f = to_numeric(lhs)
      rhs_f = to_numeric(rhs)
      if lhs_f && rhs_f
        (lhs_f <=> rhs_f) || 0
      else
        lhs.to_s <=> rhs.to_s
      end
    end

    # Private: Convert a value to Float64 if possible.
    private def to_numeric(val : String | Int32 | Float64 | Bool | Nil) : Float64?
      case val
      when Int32
        val.to_f64
      when Float64
        val
      when String
        val.to_f64?
      else
        nil
      end
    end

    # Private: Include by line number selection.
    private def include_by_lines(inc_path : String, inc_linenos : Array(Int32), relpath : String, target : String, attrlist : String?, parsed_attrs : Hash(String, String)) : Bool
      begin
        all_lines = File.read_lines(inc_path)
      rescue ex
        logger.error { "include file not readable: #{inc_path}: #{ex.message}" }
        replace_next_line("Unresolved directive in #{@path} - include::#{target}[#{attrlist}]")
        return false
      end

      inc_lines = [] of String
      inc_offset : Int32? = nil
      select_remaining = false

      all_lines.each_with_index do |l, idx|
        lineno = idx + 1
        if select_remaining
          inc_offset ||= lineno
          inc_lines << l
        elsif inc_linenos.includes?(lineno)
          inc_offset ||= lineno
          inc_lines << l
        elsif inc_linenos.includes?(-1) && lineno >= inc_linenos.first
          inc_offset ||= lineno
          inc_lines << l
          select_remaining = true
        end
      end

      shift
      if inc_offset
        parsed_attrs["partial-option"] = ""
        push_include(inc_lines, inc_path, relpath, inc_offset, parsed_attrs)
      end
      true
    end

    # Private: Include by tag selection.
    private def include_by_tags(inc_path : String, inc_tags : Hash(String, Bool), relpath : String, target : String, attrlist : String?, parsed_attrs : Hash(String, String)) : Bool
      begin
        all_lines = File.read_lines(inc_path)
      rescue ex
        logger.error { "include file not readable: #{inc_path}: #{ex.message}" }
        replace_next_line("Unresolved directive in #{@path} - include::#{target}[#{attrlist}]")
        return false
      end

      inc_lines = [] of String
      inc_offset : Int32? = nil
      tag_stack = [] of Tuple(String, Bool)
      active_tag : String? = nil

      base_select = !(inc_tags.values.any? { |v| v == true })
      selecting = base_select

      all_lines.each_with_index do |l, idx|
        lineno = idx + 1
        if (l.includes?(": :")) && (l.includes?("[]")) && (tm = TagDirectiveRx.match(l))
          this_tag = tm[2]
          if tm[1]? # end tag
            if this_tag == active_tag
              tag_stack.pop
              if tag_stack.empty?
                active_tag = nil
                selecting = base_select
              else
                active_tag = tag_stack.last[0]
                selecting = tag_stack.last[1]
              end
            end
          elsif inc_tags.has_key?(this_tag)
            selecting = inc_tags[this_tag]
            tag_stack << {(active_tag = this_tag), selecting}
          end
        elsif selecting
          inc_offset ||= lineno
          inc_lines << l
        end
      end

      shift
      if inc_offset
        parsed_attrs["partial-option"] = "" unless base_select && inc_tags.empty?
        push_include(inc_lines, inc_path, relpath, inc_offset, parsed_attrs)
      end
      true
    end

    # Private: Include the full file.
    private def include_full_file(inc_path : String, relpath : String, target : String, attrlist : String?, parsed_attrs : Hash(String, String)) : Bool
      begin
        inc_content = File.read(inc_path)
        shift
      rescue ex
        logger.error { "include file not readable: #{inc_path}: #{ex.message}" }
        replace_next_line("Unresolved directive in #{@path} - include::#{target}[#{attrlist}]")
        return false
      end
      push_include(inc_content, inc_path, relpath, 1, parsed_attrs)
      true
    end

    # Override prepare_lines to handle front matter and trailing blank lines.
    protected def prepare_lines(data : Array(String) | String | Nil, opts = {} of Symbol => String | Bool) : Array(String)
      result = super

      if opts[:skip_front_matter]?
        if (front_matter = skip_front_matter!(result))
          @document.attributes["front-matter"] = front_matter.join(LF) unless opts[:include]?
        end
      end

      unless opts[:include]?
        # Remove trailing blank lines
        while (last = result.last?) && last.empty?
          result.pop
        end
      end

      result
    end
  end
end
