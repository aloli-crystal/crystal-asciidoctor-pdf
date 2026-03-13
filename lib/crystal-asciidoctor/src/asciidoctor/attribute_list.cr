module Asciidoctor
  # Handles parsing AsciiDoc attribute lists into a Hash of key/value pairs.
  class AttributeList
    APOS      = "'"
    BACKSLASH = "\\"
    QUOT      = "\""

    BOUNDARY_RX = {
      QUOT => /.*?[^\\](?=")/,
      APOS => /.*?[^\\](?=')/,
      ","  => /.*?(?=[ \t]*(,|$))/,
    }

    ESCAPED_QUOTES = {
      QUOT => "\\\"",
      APOS => "\\'",
    }

    NAME_RX      = /[\p{L}\d_][\p{L}\d_-]*/
    BLANK_RX     = /[ \t]+/
    SKIP_RX      = {"," => /[ \t]*(,|$)/}

    @scanner_pos : Int32
    @source : String
    @block : AbstractBlock?
    @delimiter : String
    @attributes : Hash(String | Int32, String)?

    def initialize(@source : String, @block : AbstractBlock? = nil, @delimiter : String = ",")
      @scanner_pos = 0
      @attributes = nil
    end

    def parse(positional_attrs : Array(String) = [] of String) : Hash(String | Int32, String)
      return @attributes.not_nil! if @attributes
      @attributes = {} of String | Int32 => String
      @scanner_pos = 0
      index = 0
      while parse_attribute(index, positional_attrs)
        break if eos?
        skip_delimiter
        index += 1
      end
      @attributes.not_nil!
    end

    def parse_into(attributes : Hash(String | Int32, String), positional_attrs : Array(String) = [] of String) : Hash(String | Int32, String)
      attributes.merge!(parse(positional_attrs))
    end

    def rekey(positional_attrs : Array(String)) : Hash(String | Int32, String)
      AttributeList.rekey(@attributes.not_nil!, positional_attrs)
    end

    def self.rekey(attributes : Hash(String | Int32, String), positional_attrs : Array(String)) : Hash(String | Int32, String)
      positional_attrs.each_with_index do |key, index|
        if key && (val = attributes[index + 1]?)
          attributes[key] = val
        end
      end
      attributes
    end

    private def eos? : Bool
      @scanner_pos >= @source.size
    end

    private def get_byte : Char?
      return nil if eos?
      c = @source[@scanner_pos]
      @scanner_pos += 1
      c
    end

    private def parse_attribute(index : Int32, positional_attrs : Array(String)) : Bool?
      continue = true
      skip_blank
      first = peek(1)
      name : String? = nil
      value : String? = nil
      single_quoted = false

      if first && first == QUOT[0]?
        get_byte
        name = parse_attribute_value(QUOT)
      elsif first && first == APOS[0]?
        get_byte
        name = parse_attribute_value(APOS)
        single_quoted = true unless name && name.starts_with?(APOS)
      else
        name = scan_name
        skipped = skip_blank || 0

        if eos?
          return nil unless name || @source.rstrip.ends_with?(@delimiter)
          continue = false
        else
          c = get_byte
          if c && c.to_s == @delimiter
            unscan
          elsif name
            if c == '='
              skip_blank
              c2 = get_byte
              if c2 && c2 == QUOT[0]?
                value = parse_attribute_value(QUOT)
              elsif c2 && c2 == APOS[0]?
                value = parse_attribute_value(APOS)
                single_quoted = true unless value && value.starts_with?(APOS)
              elsif c2 && c2.to_s == @delimiter
                value = ""
                unscan
              elsif c2.nil?
                value = ""
              else
                value = "#{c2}#{scan_to_delimiter}"
                return true if value == "None"
              end
            else
              name = "#{name}#{" " * skipped}#{c}#{scan_to_delimiter}"
            end
          else
            name = "#{c}#{scan_to_delimiter}"
          end
        end
      end

      attrs = @attributes.not_nil!

      if value
        case name
        when "options", "opts"
          if value.includes?(',')
            value = value.delete(' ') if value.includes?(' ')
            value.split(',').each do |opt|
              attrs["#{opt}-option"] = "" unless opt.empty?
            end
          else
            attrs["#{value}-option"] = "" unless value.empty?
          end
        else
          if single_quoted && (block = @block)
            case name
            when "title", "reftext"
              attrs[name.not_nil!] = value
            else
              attrs[name.not_nil!] = block.apply_subs_str(value)
            end
          else
            attrs[name.not_nil!] = value if name
          end
        end
      else
        if single_quoted && (block = @block)
          name = block.apply_subs_str(name.not_nil!) if name
        end
        if (pos_name = positional_attrs[index]?) && name
          attrs[pos_name] = name
        end
        attrs[index + 1] = name || ""
      end

      continue ? true : nil
    end

    private def parse_attribute_value(quote : String) : String
      if peek(1) == quote[0]?
        get_byte
        return ""
      end
      if (value = scan_to_quote(quote))
        get_byte
        escaped = ESCAPED_QUOTES[quote]?
        (value.includes?(BACKSLASH) && escaped) ? value.gsub(escaped, quote) : value
      else
        "#{quote}#{scan_to_delimiter}"
      end
    end

    private def peek(n : Int32) : Char?
      return nil if @scanner_pos >= @source.size
      @source[@scanner_pos]
    end

    private def scan_name : String?
      match = NAME_RX.match(@source, @scanner_pos)
      if match && match.begin == @scanner_pos
        @scanner_pos = match.end
        match[0]
      else
        nil
      end
    end

    private def scan_to_delimiter : String
      pattern = BOUNDARY_RX[@delimiter]?
      return "" unless pattern
      match = pattern.match(@source, @scanner_pos)
      if match && match.begin == @scanner_pos
        @scanner_pos = match.end
        match[0]
      else
        remaining = @source[@scanner_pos..]
        @scanner_pos = @source.size
        remaining
      end
    end

    private def scan_to_quote(quote : String) : String?
      pattern = BOUNDARY_RX[quote]?
      return nil unless pattern
      match = pattern.match(@source, @scanner_pos)
      if match && match.begin == @scanner_pos
        @scanner_pos = match.end
        match[0]
      else
        nil
      end
    end

    private def skip_blank : Int32?
      match = BLANK_RX.match(@source, @scanner_pos)
      if match && match.begin == @scanner_pos
        len = match[0].size
        @scanner_pos += len
        len
      else
        nil
      end
    end

    private def skip_delimiter
      pattern = SKIP_RX[@delimiter]?
      return unless pattern
      match = pattern.match(@source, @scanner_pos)
      if match && match.begin == @scanner_pos
        @scanner_pos = match.end
      end
    end

    private def unscan
      @scanner_pos -= 1 if @scanner_pos > 0
    end
  end
end
