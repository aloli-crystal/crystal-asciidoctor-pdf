module Asciidoctor
  class Timings
    @log : Hash(Symbol, Float64)
    @timers : Hash(Symbol, Float64)

    def initialize
      @log = {} of Symbol => Float64
      @timers = {} of Symbol => Float64
    end

    # Public: Return the time recorded for the convert phase.
    def convert : Float64?
      time(:convert)
    end

    # Public: Return the time recorded for the parse phase.
    def parse : Float64?
      time(:parse)
    end

    # Public: Print a timing report to the specified IO.
    def print_report(to : IO = STDOUT, subject : String? = nil) : Nil
      to.puts("Input file: #{subject}") if subject
      to.puts("  Time to read and parse source: #{"%.5f" % (read_parse || 0.0)}")
      to.puts("  Time to convert document: #{"%.5f" % (convert || 0.0)}")
      to.puts("  Total time (read, parse and convert): #{"%.5f" % (read_parse_convert || 0.0)}")
    end

    # Public: Return the time recorded for the read phase.
    def read : Float64?
      time(:read)
    end

    # Public: Return the combined time for read and parse phases.
    def read_parse : Float64?
      time(:read, :parse)
    end

    # Public: Return the combined time for read, parse and convert phases.
    def read_parse_convert : Float64?
      time(:read, :parse, :convert)
    end

    # Public: Record the elapsed time for the specified key since start was called.
    def record(key : Symbol) : Nil
      if start_time = @timers.delete(key)
        @log[key] = now - start_time
      end
    end

    # Public: Start a timer for the specified key.
    def start(key : Symbol) : Nil
      @timers[key] = now
    end

    # Public: Return the combined time for all phases.
    def total : Float64?
      time(:read, :parse, :convert, :write)
    end

    # Public: Return the time recorded for the write phase.
    def write : Float64?
      time(:write)
    end

    private def now : Float64
      Time.monotonic.total_seconds
    end

    private def time(*keys : Symbol) : Float64?
      total = keys.reduce(0.0) { |sum, key| sum + (@log[key]? || 0.0) }
      total > 0 ? total : nil
    end
  end
end
