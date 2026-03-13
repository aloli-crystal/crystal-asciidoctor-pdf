module Asciidoctor
  # Tracks the file and line number of a node in the AsciiDoc source.
  # Only populated when the sourcemap option is enabled.
  class SourceLocation
    property dir : String?
    property file : String?
    property lineno : Int32
    property path : String?

    def initialize(@file : String? = nil, @lineno : Int32 = 0, @dir : String? = nil, @path : String? = nil)
    end

    def advance(count : Int32 = 1)
      @lineno += count
    end

    def dup : SourceLocation
      SourceLocation.new(@file, @lineno, @dir, @path)
    end

    def to_s(io : IO) : Nil
      if f = @file
        io << f << ": line " << @lineno
      else
        io << "line " << @lineno
      end
    end
  end
end
