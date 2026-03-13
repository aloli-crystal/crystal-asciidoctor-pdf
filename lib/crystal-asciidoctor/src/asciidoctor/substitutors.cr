module Asciidoctor
  # Additional constants used by the Substitutors module
  PASS_START = "\u0096"
  PASS_END   = "\u0097"
  R_SB       = "]"
  ESC_R_SB   = "\\]"
  RS         = "\\"
  PLUS_CHAR  = "+"

  # Sub groups map symbol names to arrays of substitution symbols
  SUB_GROUPS = {
    :attributes        => [:attributes],
    :macros            => [:macros],
    :none              => [] of Symbol,
    :normal            => [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements],
    :pass              => [] of Symbol,
    :post_replacements => [:post_replacements],
    :quotes            => [:quotes],
    :replacements      => [:replacements],
    :specialcharacters => [:specialcharacters],
    :verbatim          => [:specialcharacters, :callouts],
  }

  SUB_HINTS = {
    :a => :attributes,
    :c => :specialcharacters,
    :m => :macros,
    :n => :normal,
    :p => :post_replacements,
    :q => :quotes,
    :r => :replacements,
    :v => :verbatim,
  }

  SUB_OPTIONS = {
    :block  => [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements, :callouts, :highlight],
    :inline => [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements],
  }

  PassSlotRx = /#{Regex.escape(PASS_START)}(\d+)#{Regex.escape(PASS_END)}/

  # Quoted text substitution pattern prefix
  QUOTE_ATTR_LIST_RXT = "\\[([^\\[\\]]+)\\]"

  # Replacement patterns (order is significant)
  REPLACEMENTS = [
    {/\\?\(C\)/, "&#169;", :none},
    {/\\?\(R\)/, "&#174;", :none},
    {/\\?\(TM\)/, "&#8482;", :none},
    {/(?: |\n|^|\\)--(?: |\n|$)/, "&#8201;&#8212;&#8201;", :none},
    {/([\p{Xwd}])\\?--(?=[\p{Xwd}])/, "&#8212;&#8203;", :leading},
    {/\\?\.\.\./, "&#8230;&#8203;", :none},
    {/\\?`'/, "&#8217;", :none},
    {/([\p{Xan}])\\?'(?=[\p{L}])/, "&#8217;", :leading},
    {/\\?-&gt;/, "&#8594;", :none},
    {/\\?=&gt;/, "&#8658;", :none},
    {/\\?&lt;-/, "&#8592;", :none},
    {/\\?&lt;=/, "&#8656;", :none},
    {/\\?(&)amp;((?:[a-zA-Z][a-zA-Z]+\d{0,2}|#\d\d\d{0,4}|#x[\da-fA-F][\da-fA-F][\da-fA-F]{0,3});)/, "", :bounding},
  ]

  # Passthrough data stored during extraction
  record PassthroughEntry,
    text : String,
    subs : Array(Symbol) = [] of Symbol,
    type : Symbol? = nil,
    attributes : Hash(String, String)? = nil

  # Module included in AbstractBlock subclasses to provide text substitution capabilities.
  module Substitutors
    @passthroughs : Array(PassthroughEntry) = [] of PassthroughEntry

    # Apply header substitutions to the text.
    def apply_header_subs(text : String) : String
      apply_subs(text, [:specialcharacters, :attributes])
    end

    # Apply normal substitutions to the text.
    def apply_normal_subs(text : String) : String
      apply_subs(text, [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements])
    end

    # Apply reftext substitutions to the text.
    def apply_reftext_subs(text : String) : String
      apply_subs(text, [:specialcharacters, :quotes, :replacements])
    end

    # Apply the specified substitutions to the text.
    def apply_subs(text : String, subs : Array(Symbol)) : String
      return text if subs.empty?
      # Extract passthroughs before any substitutions (if text contains passthrough markers)
      has_passthroughs = (text.includes?("++") || text.includes?("$$") || text.includes?("ss:")) &&
                         (subs.includes?(:macros) || subs.includes?(:quotes) || subs.includes?(:attributes))
      result = has_passthroughs ? extract_passthroughs(text) : text
      subs.each do |sub|
        result = case sub
                 when :specialcharacters then sub_specialchars(result)
                 when :quotes            then sub_quotes(result)
                 when :attributes        then sub_attributes(result)
                 when :replacements      then sub_replacements(result)
                 when :macros            then sub_macros(result)
                 when :post_replacements then sub_post_replacements(result)
                 when :callouts          then sub_callouts(result)
                 when :highlight         then highlight_source(result, subs.includes?(:callouts))
                 else                         result
                 end
      end
      # Restore passthroughs after all substitutions
      has_passthroughs ? restore_passthroughs(result) : result
    end

    # Apply substitutions to a String value (convenience for AttributeList).
    def apply_subs_str(value : String) : String
      apply_subs(value, [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements])
    end

    # Commit substitutions based on content model and custom subs attribute.
    def commit_subs
      resolved_defaults = case @content_model
                          when ContentModel::Simple
                            [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements] of Symbol
                          when ContentModel::Verbatim
                            @context == :verse ? [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements] of Symbol : [:specialcharacters, :callouts] of Symbol
                          when ContentModel::Raw
                            @context == :stem ? [:specialcharacters] of Symbol : [] of Symbol
                          else
                            return @subs_list
                          end

      if (custom_subs = @attributes["subs"]?)
        @subs_list = resolve_block_subs(custom_subs, resolved_defaults) || [] of Symbol
      else
        @subs_list = resolved_defaults.dup
      end
      nil
    end

    # Expand all groups in the subs list.
    def expand_subs(subs : Array(Symbol)) : Array(Symbol)?
      expanded = [] of Symbol
      subs.each do |key|
        next if key == :none
        if (group = SUB_GROUPS[key]?)
          expanded += group
        else
          expanded << key
        end
      end
      expanded.empty? ? nil : expanded
    end

    # Extract passthrough text from the document for reinsertion after processing.
    def extract_passthroughs(text : String) : String
      return text unless text.includes?("++") || text.includes?("$$") || text.includes?("ss:")
      passthrus = @passthroughs
      result = text.gsub(InlinePassMacroRx) do |match_str, md|
        if (boundary = md[4]?)
          content = md[5]? || ""
          subs = boundary == "+++" ? [] of Symbol : [:specialcharacters]
          passthrus << PassthroughEntry.new(text: content, subs: subs)
          "#{PASS_START}#{passthrus.size - 1}#{PASS_END}"
        elsif md[6]?
          content = md[8]? || ""
          subs_str = md[7]?
          if subs_str
            passthrus << PassthroughEntry.new(text: normalize_text(content), subs: resolve_pass_subs(subs_str))
          else
            passthrus << PassthroughEntry.new(text: normalize_text(content))
          end
          "#{PASS_START}#{passthrus.size - 1}#{PASS_END}"
        else
          match_str
        end
      end
      result
    end

    # Normalize text by stripping whitespace and folding newlines.
    def normalize_text(text : String, normalize_whitespace : Bool? = nil, unescape_closing_square_brackets : Bool? = nil) : String
      return text if text.empty?
      result = text
      result = result.strip.tr("\n", " ") if normalize_whitespace
      result = result.gsub(ESC_R_SB, R_SB) if unescape_closing_square_brackets && result.includes?(R_SB)
      result
    end

    # Parse inline attributes from an attrlist string.
    def parse_inline_attributes(attrlist : String, positional_attrs : Array(String) = [] of String) : Hash(String, String)
      return {} of String => String if attrlist.empty?
      attrs = AttributeList.new(attrlist, self.as(AbstractBlock)).parse(positional_attrs)
      result = {} of String => String
      attrs.each do |k, v|
        result[k.to_s] = v
      end
      result
    end

    # Parse quoted text attributes (role and id shorthand).
    def parse_quoted_text_attributes(str : String) : Hash(String, String)
      str = sub_attributes(str) if str.includes?(ATTR_REF_HEAD)
      if str.includes?(',')
        idx = str.index(',')
        str = str[0...idx.not_nil!] if idx
      end
      str = str.strip
      return {} of String => String if str.empty?
      if str.starts_with?('.') || str.starts_with?('#')
        before, _, after = str.partition('#')
        attrs = {} of String => String
        if after.empty?
          attrs["role"] = before.tr(".", " ").lstrip if before.size > 1
        else
          id, _, roles = after.partition('.')
          attrs["id"] = id unless id.empty?
          if roles.empty?
            attrs["role"] = before.tr(".", " ").lstrip if before.size > 1
          elsif before.size > 1
            attrs["role"] = (before + "." + roles).tr(".", " ").lstrip
          else
            attrs["role"] = roles.tr(".", " ")
          end
        end
        attrs
      else
        {"role" => str}
      end
    end

    # Resolve block substitutions.
    def resolve_block_subs(subs : String, defaults : Array(Symbol), subject : String? = nil) : Array(Symbol)?
      resolve_subs(subs, :block, defaults, subject)
    end

    # Resolve pass substitutions.
    def resolve_pass_subs(subs : String, subject : String = "passthrough macro") : Array(Symbol)
      resolve_subs(subs, :inline, nil, subject) || [] of Symbol
    end

    # Resolve comma-delimited subs against the possible options.
    def resolve_subs(subs : String, type : Symbol = :block, defaults : Array(Symbol)? = nil, subject : String? = nil) : Array(Symbol)?
      return nil if subs.empty?
      candidates : Array(Symbol)? = nil
      subs = subs.delete(' ') if subs.includes?(' ')
      modifiers_present = SubModifierSniffRx.matches?(subs)
      subs.split(',').each do |key|
        modifier_operation : Symbol? = nil
        if modifiers_present
          first = key[0]?
          if first == '+'
            modifier_operation = :append
            key = key[1..]
          elsif first == '-'
            modifier_operation = :remove
            key = key[1..]
          elsif key.ends_with?('+')
            modifier_operation = :prepend
            key = key[0...-1]
          end
        end
        key_sym = string_to_sub_symbol(key)
        if type == :inline && (key_sym == :verbatim || key_sym == :v)
          resolved_keys = [:specialcharacters]
        elsif (group = SUB_GROUPS[key_sym]?)
          resolved_keys = group
        elsif type == :inline && key.size == 1 && (hint = SUB_HINTS[key_sym]?)
          if (candidate = SUB_GROUPS[hint]?)
            resolved_keys = candidate
          else
            resolved_keys = [hint]
          end
        else
          resolved_keys = [key_sym]
        end

        if modifier_operation
          candidates ||= defaults ? defaults.dup : [] of Symbol
          case modifier_operation
          when :append
            candidates = candidates.not_nil! + resolved_keys
          when :prepend
            candidates = resolved_keys + candidates.not_nil!
          when :remove
            candidates = candidates.not_nil! - resolved_keys
          end
        else
          candidates ||= [] of Symbol
          candidates = candidates.not_nil! + resolved_keys
        end
      end
      return nil unless candidates
      valid_options = SUB_OPTIONS[type]? || [] of Symbol
      candidates.not_nil!.select { |s| valid_options.includes?(s) }.uniq
    end

    # Restore the passthrough text by reinserting into the placeholder positions.
    def restore_passthroughs(text : String) : String
      return text unless text.includes?(PASS_START)
      passthrus = @passthroughs
      text.gsub(PassSlotRx) do |match_str, md|
        idx = md[1].to_i
        if idx < passthrus.size
          pass = passthrus[idx]
          subbed_text = apply_subs(pass.text, pass.subs)
          if (type = pass.type)
            subbed_text = Inline.new(self.as(AbstractBlock), :quoted, subbed_text,
              type: type,
              attributes: pass.attributes || {} of String => String).convert
          end
          subbed_text.includes?(PASS_START) ? restore_passthroughs(subbed_text) : subbed_text
        else
          "??pass??"
        end
      end
    end

    # Split text formatted as CSV with support for double-quoted values.
    def split_simple_csv(str : String) : Array(String)
      return [] of String if str.empty?
      if str.includes?('"')
        values = [] of String
        accum = ""
        quote_open = false
        str.each_char do |c|
          case c
          when ','
            if quote_open
              accum += c
            else
              values << accum.strip
              accum = ""
            end
          when '"'
            quote_open = !quote_open
          else
            accum += c
          end
        end
        values << accum.strip
        values
      else
        str.split(',').map(&.strip)
      end
    end

    # Substitute attribute references.
    def sub_attributes(text : String) : String
      return text unless text.includes?(ATTR_REF_HEAD)
      doc = if self.responds_to?(:document)
              self.document
            elsif self.is_a?(Document)
              self.as(Document)
            else
              return text
            end
      attribute_missing = doc.attr("attribute-missing", "skip")
      # For drop-line mode, process line by line
      if attribute_missing == "drop-line" && text.includes?('\n')
        lines = text.split('\n')
        processed_lines = lines.compact_map do |line|
          next line unless line.includes?(ATTR_REF_HEAD)
          processed = line.gsub(/\{([\p{L}\d_][\p{L}\d_-]*)\}/) do |match_str, md|
            attr_name = md[1].downcase
            if (val = doc.attributes[attr_name]?)
              val
            elsif (val = INTRINSIC_ATTRIBUTES[attr_name]?)
              val
            else
              "\x00DROP_LINE\x00"
            end
          end
          processed.includes?("\x00DROP_LINE\x00") ? nil : processed
        end
        return processed_lines.join('\n')
      end
      # Handle {counter:name}, {counter:name:seed}, {counter2:name}, {counter2:name:seed} macros
      if text.includes?("{counter")
        text = text.gsub(/\{(counter2?):(\p{L}[\p{L}\d_-]*)(?::([^}]*))?\}/) do |match_str, md|
          macro_name = md[1]
          counter_name = md[2]
          seed = md[3]?
          val = doc.counter(counter_name, seed)
          if macro_name == "counter2"
            "" # silent counter
          else
            val.to_s
          end
        end
        return text if text.empty?
      end
      # Handle {set:name:value} and {set:name!} macros first
      attribute_undefined = doc.attr("attribute-undefined", "drop-line")
      if text.includes?("{set:")
        if text.includes?('\n')
          # Multi-line: process line by line
          lines = text.split('\n')
          processed_lines = lines.compact_map do |line|
            next line unless line.includes?("{set:")
            has_unset = false
            processed = line.gsub(/\{set:([\p{L}\d_][\p{L}\d_-]*)(!|:[^}]*)?\}/) do |match_str, md|
              attr_name = md[1].downcase
              modifier = md[2]?
              if modifier == "!"
                doc.attributes.delete(attr_name)
                has_unset = true
                ""
              elsif modifier.nil?
                # {set:foo} with no value assigns empty string
                doc.attributes[attr_name] = ""
                ""
              elsif modifier.starts_with?(":")
                doc.attributes[attr_name] = modifier[1..]
                ""
              else
                ""
              end
            end
            # Drop line if it contained an unset macro and attribute-undefined is drop-line
            if has_unset && attribute_undefined == "drop-line"
              nil
            else
              processed.strip.empty? ? nil : processed
            end
          end
          text = processed_lines.join('\n')
        else
          has_unset = false
          text = text.gsub(/\{set:([\p{L}\d_][\p{L}\d_-]*)(!|:[^}]*)?\}/) do |match_str, md|
            attr_name = md[1].downcase
            modifier = md[2]?
            if modifier == "!"
              doc.attributes.delete(attr_name)
              has_unset = true
              ""
            elsif modifier.nil?
              # {set:foo} with no value assigns empty string
              doc.attributes[attr_name] = ""
              ""
            elsif modifier && modifier.starts_with?(":")
              doc.attributes[attr_name] = modifier[1..]
              ""
            else
              ""
            end
          end
          # If the entire line was just a set macro, mark for drop
          if (has_unset && attribute_undefined == "drop-line") || text.strip.empty?
            return ""
          end
        end
      end
      # For drop mode with multi-line text, process line by line
      if attribute_missing == "drop" && text.includes?('\n')
        lines = text.split('\n')
        processed_lines = lines.compact_map do |line|
          next line unless line.includes?(ATTR_REF_HEAD)
          processed = line.gsub(/\{([\p{L}\d_][\p{L}\d_-]*)\}/) do |match_str, md|
            attr_name = md[1].downcase
            if (val = doc.attributes[attr_name]?)
              val
            elsif (val = INTRINSIC_ATTRIBUTES[attr_name]?)
              val
            else
              ""
            end
          end
          processed.strip.empty? ? nil : processed
        end
        return processed_lines.join('\n')
      end
      result = text.gsub(/(\\)?\{([\p{L}\d_][\p{L}\d_-]*)\}/) do |match_str, md|
        escaped = md[1]?
        attr_name = md[2].downcase
        if escaped == "\\"
          # Escaped attribute reference: remove backslash and keep {attr_name}
          "{#{attr_name}}"
        elsif (val = doc.attributes[attr_name]?)
          val
        elsif (val = INTRINSIC_ATTRIBUTES[attr_name]?)
          val
        else
          case attribute_missing
          when "drop"
            ""
          when "drop-line"
            # Single-line drop: return empty string for the whole text
            "\x00DROP_LINE\x00"
          else
            match_str
          end
        end
      end
      # Handle drop-line: if any part of the result contains the drop marker, return empty string
      if result.includes?("\x00DROP_LINE\x00")
        ""
      else
        result
      end
    end

    # Substitute callout markers in source listings.
    def sub_callouts(text : String) : String
      autonum = 0
      text.gsub(CalloutSourceRx) do |match_str, md|
        if md[2]?
          match_str.sub(RS, "")
        else
          num_str = md[4]? || ""
          num = num_str == "." ? (autonum += 1).to_s : num_str
          guard = md[1]?
          Inline.new(self.as(AbstractBlock), :callout, num,
            id: document.callouts.read_next_id.to_s,
            attributes: {"guard" => guard || ""}).convert
        end
      end
    end

    # Substitute inline macros (links, images, footnotes, etc.).
    def sub_macros(text : String) : String
      return text if text.empty?
      result = text

      # Inline image macros: image:target[alt] and icon:name[alt]
      if result.includes?("image:") || result.includes?("icon:")
        result = result.gsub(InlineImageMacroRx) do |match_str, md|
          if match_str.starts_with?(RS)
            match_str[1..]
          else
            target = md[1]? || ""
            attrlist = md[2]? || ""
            attrs = parse_inline_attributes(attrlist, ["alt", "width", "height"])
            attrs["target"] = target
            attrs["alt"] ||= File.basename(target, File.extname(target)).tr("-_", " ")
            Inline.new(self.as(AbstractBlock), :image, nil,
              type: :image,
              target: target,
              attributes: attrs).convert
          end
        end
      end

      # Inline anchor macros: [[id,reftext]] and anchor:id[reftext]
      if result.includes?("[[") || result.includes?("anchor:")
        result = result.gsub(InlineAnchorRx) do |match_str, md|
          if md[1]?
            match_str[1..]
          else
            id = md[2]? || md[4]? || ""
            reftext = md[3]? || md[5]?
            Inline.new(self.as(AbstractBlock), :anchor, reftext,
              type: :ref, id: id).convert
          end
        end
      end

      # Inline xref macros: <<id,text>> and xref:id[text]
      if (result.includes?("&") && result.includes?(";&l")) || result.includes?("xref:")
        result = result.gsub(InlineXrefMacroRx) do |match_str, md|
          if match_str.starts_with?(RS)
            match_str[1..]
          else
            attrs = {} of String => String
            link_text : String? = nil
            if (refid = md[1]?)
              if refid.includes?(",")
                refid, _, lt = refid.partition(",")
                link_text = lt.strip.empty? ? nil : lt.strip
              end
            else
              refid = md[2]? || ""
              link_text = md[3]?
            end
            fragment = refid
            target = "##{fragment}"
            attrs["path"] = ""
            attrs["fragment"] = fragment || ""
            attrs["refid"] = refid || ""
            Inline.new(self.as(AbstractBlock), :anchor, link_text,
              type: :xref, target: target, attributes: attrs).convert
          end
        end
      end

      # Inline link macros: mailto:addr[text] and link:url[text]
      if result.includes?("mailto:") || (result.includes?("link:") && !result.includes?("://"))
        result = result.gsub(InlineLinkMacroRx) do |match_str, md|
          if match_str.starts_with?(RS)
            match_str[1..]
          else
            is_mailto = !md[1]?.nil?
            if is_mailto
              mailto_text = md[2]? || ""
              target = "mailto:" + mailto_text
            else
              target = md[2]? || ""
            end
            link_text = md[3]? || ""
            link_text = is_mailto ? mailto_text : target if link_text.empty?
            Inline.new(self.as(AbstractBlock), :anchor, link_text,
              type: :link, target: target).convert
          end
        end
      end

      # Inline link macros and auto-detected URLs
      if result.includes?("://") || result.includes?("link:")
        result = result.gsub(InlineLinkRx) do |match_str, md|
          if match_str.starts_with?(RS)
            match_str[1..]
          else
            prefix = md[1]? || ""
            scheme = md[3]? || ""
            url_part = md[4]? || ""
            target = scheme + url_part
            link_text = md[5]? || md[7]? || md[8]? || target
            prefix = "" if prefix == "link:"
            Inline.new(self.as(AbstractBlock), :anchor, link_text,
              type: :link, target: target).convert
          end
        end
      end

      # Auto-detected email addresses (bare email without mailto: prefix)
      if result.includes?("@")
        result = result.gsub(InlineEmailRx) do |match_str, md|
          if md[1]?  # preceded by \, >, :, / - leave as-is
            match_str
          else
            address = match_str
            target = "mailto:" + address
            Inline.new(self.as(AbstractBlock), :anchor, address,
              type: :link, target: target).convert
          end
        end
      end

      # Inline footnote macros: footnote:[text] and footnoteref:[id,text]
      if result.includes?("footnote")
        result = result.gsub(InlineFootnoteMacroRx) do |match_str, md|
          if match_str.starts_with?(RS)
            match_str[1..]
          else
            is_footnoteref = !md[1]?.nil?
            id = md[2]? || ""
            content = md[3]? || ""
            if is_footnoteref
              # deprecated footnoteref macro
              if !content.empty?
                parts = content.split(',', 2)
                id = parts[0].strip
                content = parts.size > 1 ? parts[1].strip : ""
              end
            end
            doc = self.responds_to?(:document) ? self.document : nil
            if doc
              index : Int32 = 0
              type : Symbol? = nil
              target : String? = nil
              fn_id : String? = id.empty? ? nil : id
              if !id.empty?
                # reference to existing footnote or new named footnote
                existing = doc.footnotes.find { |fn| fn.id == id }
                if existing
                  index = existing.index
                  content = existing.text || ""
                  type = :xref
                  target = id
                  fn_id = nil
                elsif !content.empty?
                  index = doc.counter("footnote-number").to_i
                  doc.footnotes << Document::Footnote.new(index, id, content)
                  type = :ref
                  target = nil
                else
                  type = :xref
                  target = id
                  fn_id = nil
                end
              elsif !content.empty?
                index = doc.counter("footnote-number").to_i
                doc.footnotes << Document::Footnote.new(index, nil, content)
                type = nil
                target = nil
              else
                next match_str
              end
              Inline.new(self.as(AbstractBlock), :footnote, content,
                attributes: {"index" => index.to_s}, id: fn_id, target: target, type: type).convert
            else
              match_str
            end
          end
        end
      end

      # Inline kbd macro: kbd:[keys]
      if result.includes?("kbd:")
        result = result.gsub(InlineKbdMacroRx) do |match_str, md|
          if match_str.starts_with?(RS)
            match_str[1..]
          else
            keys_str = md[1]? || ""
            Inline.new(self.as(AbstractBlock), :kbd, nil,
              attributes: {"keys" => keys_str}).convert
          end
        end
      end

      # Inline btn macro: btn:[label]
      if result.includes?("btn:")
        result = result.gsub(InlineBtnMacroRx) do |match_str, md|
          if match_str.starts_with?(RS)
            match_str[1..]
          else
            label = md[1]? || ""
            Inline.new(self.as(AbstractBlock), :button, label).convert
          end
        end
      end

      # Inline menu macro: menu:name[items]
      if result.includes?("menu:")
        result = result.gsub(InlineMenuMacroRx) do |match_str, md|
          if match_str.starts_with?(RS)
            match_str[1..]
          else
            menu = md[1]? || ""
            items = md[2]? || ""
            Inline.new(self.as(AbstractBlock), :menu, nil,
              attributes: {"menu" => menu, "submenus" => "", "menuitem" => items}).convert
          end
        end
      end

      result
    end

    # Substitute post replacements (hard line breaks).
    def sub_post_replacements(text : String) : String
      # Check hardbreaks on self, parent chain, or document
      # First check if hardbreaks is explicitly disabled on this block
      hardbreaks_disabled = self.responds_to?(:attributes) &&
        (self.attributes["hardbreaks"]? == "false" || self.attributes["hardbreaks-option"]? == "false")
      has_hardbreaks = false
      unless hardbreaks_disabled
        has_hardbreaks = (self.responds_to?(:attributes) && (self.attributes["hardbreaks-option"]? == "" || self.attributes["hardbreaks"]? == "")) ||
           (self.responds_to?(:document) && (self.document.attributes["hardbreaks-option"]? == "" || self.document.attributes["hardbreaks"]? == ""))
        unless has_hardbreaks
          # Check parent chain for hardbreaks-option
          if self.responds_to?(:parent)
            p = self.parent
            while p
              if p.responds_to?(:attributes) && (p.attributes["hardbreaks-option"]? == "" || p.attributes["hardbreaks"]? == "")
                has_hardbreaks = true
                break
              end
              p = p.responds_to?(:parent) ? p.parent : nil
            end
          end
        end
      end
      if has_hardbreaks
        lines = text.split("\n", remove_empty: false)
        return text if lines.size < 2
        last = lines.pop
        result = lines.map do |line|
          if line.ends_with?(HARD_LINE_BREAK)
            Inline.new(self.as(AbstractBlock), :break, line[0...-2], type: :line).convert
          else
            Inline.new(self.as(AbstractBlock), :break, line, type: :line).convert
          end
        end
        result << last
        result.join("\n")
      elsif !hardbreaks_disabled && text.includes?(PLUS_CHAR) && text.includes?(HARD_LINE_BREAK)
        text.gsub(HardLineBreakRx) do |match_str, md|
          Inline.new(self.as(AbstractBlock), :break, md[1], type: :line).convert
        end
      else
        text
      end
    end

    # Substitute quoted text (bold, italic, monospace, etc.).
    def sub_quotes(text : String) : String
      result = text
      doc = self.is_a?(Document) ? self.as(Document) : (self.responds_to?(:document) ? self.document : nil)
      compat = doc ? doc.compat_mode? : false
      quote_subs = quote_subs_for(compat)
      quote_subs.each do |type, scope, pattern|
        result = result.gsub(pattern) do |match_str, md|
          convert_quoted_text(md, type, scope)
        end
      end
      result
    end

    # Substitute replacement characters.
    def sub_replacements(text : String) : String
      return text unless ReplaceableTextRx.matches?(text)
      result = text
      REPLACEMENTS.each do |pattern, replacement, restore|
        result = result.gsub(pattern) do |match_str, md|
          do_replacement(md, replacement, restore)
        end
      end
      result
    end

    # Substitute special characters (XML entities).
    def sub_specialchars(text : String) : String
      return text if text.empty?
      text.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;")
    end

    # Substitute source code with optional callout processing.
    def sub_source(source : String, process_callouts : Bool) : String
      process_callouts ? sub_callouts(sub_specialchars(source)) : sub_specialchars(source)
    end

    # Extract the callout numbers from the source to prepare it for syntax highlighting.
    def extract_callouts(source : String) : Tuple(String, Hash(Int32, Array(Tuple(String?, String)))?)
      callout_marks = {} of Int32 => Array(Tuple(String?, String))
      autonum = 0
      lineno = 0
      last_lineno : Int32? = nil
      callout_rx = CalloutExtractRx
      lines = source.split(LF, remove_empty: false)
      result_lines = lines.map do |line|
        lineno += 1
        line.gsub(callout_rx) do |match_str, md|
          if md[2]?
            # honor the escape
            match_str.sub(RS, "")
          else
            guard = md[1]?
            comment_type = md[3]?
            guard_pair = comment_type == "--" ? "<!--,-->" : guard
            num_str = md[4]? || ""
            num = num_str == "." ? (autonum += 1).to_s : num_str
            marks = callout_marks[lineno]? || ([] of Tuple(String?, String))
            marks << {guard_pair, num}
            callout_marks[lineno] = marks
            last_lineno = lineno
            ""
          end
        end
      end
      result = result_lines.join(LF)
      if last_lineno
        result = "#{result}#{LF}" if last_lineno == lineno
      else
        return {result, nil}
      end
      {result, callout_marks}
    end

    # Highlight source code using the registered syntax highlighter.
    def highlight_source(source : String, process_callouts : Bool) : String
      # NOTE: syntax highlighting is a stub for now; return sub_source as fallback
      return sub_source(source, process_callouts) unless (syntax_hl = document.syntax_highlighter)
      if process_callouts
        source, callout_marks = extract_callouts(source)
      end
      # For now, just apply special chars since we don't have a full highlighter implementation
      highlighted = sub_specialchars(source)
      if callout_marks
        highlighted = restore_callouts(highlighted, callout_marks)
      end
      highlighted
    end

    # Resolve the line numbers in the specified source to highlight from the provided spec.
    def resolve_lines_to_highlight(source : String, spec : String, start : Int32? = nil) : Array(Int32)
      lines = [] of Int32
      spec = spec.delete(' ') if spec.includes?(' ')
      entries = spec.includes?(',') ? spec.split(',') : spec.split(';')
      entries.each do |entry|
        negate = false
        if entry.starts_with?('!')
          entry = entry[1..]
          negate = true
        end
        delim = entry.includes?("..") ? ".." : (entry.includes?('-') ? "-" : nil)
        if delim
          from_str, _, to_str = entry.partition(delim)
          from = from_str.to_i
          to = (to_str.empty? || to_str.to_i < 0) ? (source.count(LF) + 1) : to_str.to_i
          range = (from..to).to_a
          if negate
            lines = lines - range
          else
            lines = (lines | range)
          end
        elsif negate
          lines.delete(entry.to_i)
        else
          line = entry.to_i
          lines << line unless lines.includes?(line)
        end
      end
      shift = start ? start - 1 : 0
      unless shift == 0
        lines = lines.map { |l| l - shift }
      end
      lines.sort
    end

    # Restore the callout numbers to the highlighted source.
    def restore_callouts(source : String, callout_marks : Hash(Int32, Array(Tuple(String?, String))), source_offset : Int32? = nil) : String
      preamble = ""
      if source_offset
        preamble = source[0, source_offset]
        source = source[source_offset..]
      end
      lineno = 0
      lines = source.split(LF, remove_empty: false)
      result_lines = lines.map do |line|
        lineno += 1
        if (conums = callout_marks[lineno]?)
          callout_marks.delete(lineno)
          callout_strs = conums.map do |guard, numeral|
            Inline.new(self.as(AbstractBlock), :callout, numeral,
              id: document.callouts.read_next_id.to_s,
              attributes: {"guard" => guard || ""}).convert
          end
          "#{line}#{callout_strs.join(' ')}"
        else
          line
        end
      end
      "#{preamble}#{result_lines.join(LF)}"
    end

    # Internal: Convert a quoted text region.
    private def convert_quoted_text(md : Regex::MatchData, type : Symbol, scope : Symbol) : String
      match_str = md[0]
      if match_str.starts_with?(RS)
        if scope == :constrained && md[2]?
          return "[#{md[2]}]#{Inline.new(self.as(AbstractBlock), :quoted, md[3]? || "", type: type).convert}"
        else
          return match_str[1..]
        end
      end

      if scope == :constrained
        if (attrlist = md[2]?)
          id = (attributes = parse_quoted_text_attributes(attrlist))["id"]?
          type = :unquoted if type == :mark
        end
        "#{md[1]?}#{Inline.new(self.as(AbstractBlock), :quoted, md[3]? || "", type: type, id: id, attributes: attributes || {} of String => String).convert}"
      else
        if (attrlist = md[1]?)
          id = (attributes = parse_quoted_text_attributes(attrlist))["id"]?
          type = :unquoted if type == :mark
        end
        Inline.new(self.as(AbstractBlock), :quoted, md[2]? || "", type: type, id: id, attributes: attributes || {} of String => String).convert
      end
    end

    # Internal: Perform replacement substitution.
    private def do_replacement(md : Regex::MatchData, replacement : String, restore : Symbol) : String
      captured = md[0]
      if captured.includes?(RS)
        captured.sub(RS, "")
      else
        case restore
        when :none
          replacement
        when :bounding
          "#{md[1]?}#{replacement}#{md[2]?}"
        else # :leading
          "#{md[1]?}#{replacement}"
        end
      end
    end

    # Build the quote substitution patterns.
    private def quote_subs_for(compat_mode : Bool) : Array(Tuple(Symbol, Symbol, Regex))
      qa = QUOTE_ATTR_LIST_RXT
      subs = [
        {:strong, :unconstrained, /\\?(?:#{qa})?\*\*(.+?)\*\*/m},
        {:strong, :constrained, /(^|[^\p{Xwd};:}])(?:#{qa})?\*(\S|\S.*?\S)\*(?![\p{Xwd}])/m},
        {:double, :constrained, /(^|[^\p{Xwd};:}])(?:#{qa})?"`(\S|\S.*?\S)`"(?![\p{Xwd}])/m},
        {:single, :constrained, /(^|[^\p{Xwd};:`}])(?:#{qa})?'`(\S|\S.*?\S)`'(?![\p{Xwd}])/m},
        {:monospaced, :unconstrained, /\\?(?:#{qa})?``(.+?)``/m},
        {:monospaced, :constrained, /(^|[^\p{Xwd};:"'`}])(?:#{qa})?`(\S|\S.*?\S)`(?![\p{Xwd}"'`])/m},
        {:emphasis, :unconstrained, /\\?(?:#{qa})?__(.+?)__/m},
        {:emphasis, :constrained, /(^|[^\p{Xwd};:}])(?:#{qa})?_(\S|\S.*?\S)_(?![\p{Xwd}])/m},
        {:mark, :unconstrained, /\\?(?:#{qa})?##(.+?)##/m},
        {:mark, :constrained, /(^|[^\p{Xwd}&;:}])(?:#{qa})?#(\S|\S.*?\S)#(?![\p{Xwd}])/m},
        {:superscript, :unconstrained, /\\?(?:#{qa})?\^(\S+?)\^/},
        {:subscript, :unconstrained, /\\?(?:#{qa})?~(\S+?)~/},
      ] of Tuple(Symbol, Symbol, Regex)
      if compat_mode
        # In compat-mode: +text+ is monospaced, 'text' is emphasis
        subs << {:monospaced, :unconstrained, /\\?(?:#{qa})?\+\+(.+?)\+\+/m}
        subs << {:monospaced, :constrained, /(^|[^\p{Xwd};:"'`}])(?:#{qa})?\+(\S|\S.*?\S)\+(?![\p{Xwd}"'`])/m}
        subs << {:emphasis, :constrained, /(^|[^\p{Xwd};:}])(?:#{qa})?'(\S|\S.*?\S)'(?![\p{Xwd}])/m}
      end
      subs
    end

    # Highlight the source code in the given text using the syntax highlighter
    # registered with the document, if available.
    def highlight_source(source : String, process_callouts : Bool) : String
      syntax_hl = document.syntax_highlighter
      return sub_specialchars(source) unless syntax_hl && syntax_hl.highlight?

      # For server-side highlighting, delegate to the syntax highlighter
      lang = attr("language") || ""
      highlighted = syntax_hl.highlight(self.as(AbstractNode), source, lang)
      highlighted
    end

    # Convert a string to a substitution symbol.
    private def string_to_sub_symbol(str : String) : Symbol
      case str
      when "attributes"        then :attributes
      when "callouts"          then :callouts
      when "highlight"         then :highlight
      when "macros"            then :macros
      when "none"              then :none
      when "normal"            then :normal
      when "pass"              then :pass
      when "post_replacements" then :post_replacements
      when "quotes"            then :quotes
      when "replacements"      then :replacements
      when "specialcharacters" then :specialcharacters
      when "specialchars"      then :specialcharacters
      when "verbatim"          then :verbatim
      when "a"                 then :a
      when "c"                 then :c
      when "m"                 then :m
      when "n"                 then :n
      when "p"                 then :p
      when "q"                 then :q
      when "r"                 then :r
      when "v"                 then :v
      else                          :none
      end
    end
  end
end
