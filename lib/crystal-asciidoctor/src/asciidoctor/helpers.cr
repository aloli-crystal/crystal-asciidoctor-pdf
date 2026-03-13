require "uri"

module Asciidoctor
  module Helpers
    extend self

    ROMAN_NUMERALS_WITH_REDUCERS = [
      {"M", 1000}, {"CM", 900}, {"D", 500}, {"CD", 400}, {"C", 100}, {"XC", 90},
      {"L", 50}, {"XL", 40}, {"X", 10}, {"IX", 9}, {"V", 5}, {"IV", 4}, {"I", 1},
    ]

    ROMAN_NUMERALS = {
      'I' => 1, 'V' => 5, 'X' => 10, 'L' => 50, 'C' => 100, 'D' => 500, 'M' => 1000,
    }

    # Public: Retrieves the basename of the filename, optionally removing the extension.
    def basename(filename : String, drop_ext : String | Bool | Nil = nil) : String
      if drop_ext
        ext = drop_ext.is_a?(Bool) ? extname(filename) : drop_ext.as(String)
        File.basename(filename, ext)
      else
        File.basename(filename)
      end
    end

    # Internal: Encode a URI component String for safe inclusion in a URI.
    def encode_uri_component(str : String) : String
      URI.encode_www_form(str).gsub("+", "%20")
    end

    # Internal: Apply URI path encoding to spaces in the specified string.
    def encode_spaces_in_uri(str : String) : String
      str.includes?(' ') ? str.gsub(' ', "%20") : str
    end

    # Public: Retrieves the file extension of the specified path.
    def extname(path : String, fallback : String = "") : String
      if (last_dot_idx = path.rindex('.'))
        if path.index('/', last_dot_idx)
          fallback
        else
          path[last_dot_idx..]
        end
      else
        fallback
      end
    end

    # Public: Returns whether this path has a file extension.
    def extname?(path : String) : Bool
      if (last_dot_idx = path.rindex('.'))
        !path.index('/', last_dot_idx)
      else
        false
      end
    end

    # Internal: Converts an integer to a Roman numeral.
    def int_to_roman(val : Int32) : String
      result = String::Builder.new
      remaining = val
      ROMAN_NUMERALS_WITH_REDUCERS.each do |letters, value|
        repeat, remaining = remaining.divmod(value)
        repeat.times { result << letters }
      end
      result.to_s
    end

    # Internal: Make a directory, ensuring all parent directories exist.
    def mkdir_p(dir : String) : Nil
      return if File.directory?(dir)
      parent_dir = File.dirname(dir)
      mkdir_p(parent_dir) unless parent_dir == "."
      begin
        Dir.mkdir(dir)
      rescue ex : File::Error
        raise ex unless File.directory?(dir)
      end
    end

    # Internal: Get the next value in the sequence.
    def nextval(current : Int32) : Int32
      current + 1
    end

    # Internal: Get the next value in the sequence.
    def nextval(current : String) : String | Int32
      int_val = current.to_i?(strict: true)
      if int_val
        int_val + 1
      else
        current.succ
      end
    end

    # Internal: Prepare the source data Array for parsing.
    def prepare_source_array(data : Array(String), trim_end : Bool = true) : Array(String)
      return [] of String if data.empty?
      first = data[0]
      if first.starts_with?("\u{FEFF}")
        data = data.dup
        data[0] = first[1..]
      end
      if trim_end
        data.map(&.rstrip)
      else
        data.map(&.chomp)
      end
    end

    # Internal: Prepare the source data String for parsing.
    def prepare_source_string(data : String, trim_end : Bool = true) : Array(String)
      return [] of String if data.empty?
      data = data[1..] if data.starts_with?("\u{FEFF}")
      if trim_end
        data.each_line.map(&.rstrip).to_a
      else
        data.each_line.map(&.chomp).to_a
      end
    end

    # Internal: Resolve a system path from the target and start values.
    def resolve(target : String, start : String? = nil) : String
      if target.starts_with?("/") || target.starts_with?("~")
        File.expand_path(target)
      elsif start
        File.expand_path(target, start)
      else
        File.expand_path(target)
      end
    end

    # Internal: Converts an uppercase Roman numeral to an integer.
    def roman_to_int(val : String) : Int32
      result = 0
      values = val.each_char.map { |c| ROMAN_NUMERALS[c]? || 0 }.to_a
      values.each_with_index do |v, idx|
        succ = values[idx + 1]?
        if succ && succ > v
          result -= v
        else
          result += v
        end
      end
      result
    end

    # Public: Removes the file extension from filename and returns the result.
    def rootname(filename : String) : String
      if (last_dot_idx = filename.rindex('.'))
        if filename.index('/', last_dot_idx)
          filename
        else
          filename[0...last_dot_idx]
        end
      else
        filename
      end
    end

    # Internal: Efficiently checks whether the specified String resembles a URI.
    def uriish?(str : String) : Bool
      str.includes?(':') && !!(UriSniffRx.match(str))
    end
  end
end
