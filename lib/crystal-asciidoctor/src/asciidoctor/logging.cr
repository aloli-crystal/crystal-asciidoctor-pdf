require "log"

module Asciidoctor
  # Severity levels matching Ruby's Logger severity constants.
  enum Severity
    DEBUG
    INFO
    WARN
    ERROR
    FATAL
    UNKNOWN
  end

  # A log message with context information.
  record LogMessage, text : String, source_location : String? = nil do
    def inspect : String
      if sl = source_location
        "#{sl}: #{text}"
      else
        text
      end
    end

    def to_s : String
      inspect
    end
  end

  # Logger that writes formatted messages to an IO (typically STDERR).
  # Tracks the maximum severity level encountered.
  class Logger
    property max_severity : Severity?

    @io : IO
    @level : Severity
    @progname : String
    @formatter : Proc(Severity, String, String, String)

    def initialize(@io : IO = STDERR, level : Severity = Severity::WARN, progname : String = "asciidoctor",
                   formatter : Proc(Severity, String, String, String)? = nil)
      @level = level
      @progname = progname
      fmt = BasicFormatter.new
      @formatter = formatter || ->(s : Severity, p : String, m : String) { fmt.call(s, p, m) }
    end

    def add(severity : Severity, message : String, progname : String? = nil) : Nil
      sev = severity
      if (ms = @max_severity)
        @max_severity = sev if sev > ms
      else
        @max_severity = sev
      end
      return if sev < @level
      @io.print @formatter.call(sev, progname || @progname, message)
    end

    def debug(message : String) : Nil
      add(Severity::DEBUG, message)
    end

    def error(message : String) : Nil
      add(Severity::ERROR, message)
    end

    def error(&block : -> String) : Nil
      add(Severity::ERROR, block.call)
    end

    def fatal(message : String) : Nil
      add(Severity::FATAL, message)
    end

    def info(message : String) : Nil
      add(Severity::INFO, message)
    end

    def warn(message : String) : Nil
      add(Severity::WARN, message)
    end

    def warn(&block : -> String) : Nil
      add(Severity::WARN, block.call)
    end

    # Basic formatter that outputs messages in the format:
    # progname: SEVERITY: message
    class BasicFormatter
      SEVERITY_LABEL_SUBSTITUTES = {
        "WARN"  => "WARNING",
        "FATAL" => "FAILED",
      }

      def call(severity : Severity, progname : String, message : String) : String
        label = SEVERITY_LABEL_SUBSTITUTES[severity.to_s]? || severity.to_s
        "#{progname}: #{label}: #{message}\n"
      end
    end
  end

  # A logger that stores messages in memory for later retrieval.
  class MemoryLogger
    record MemoryMessage, severity : Severity, message : String

    getter messages : Array(MemoryMessage)

    def initialize
      @messages = [] of MemoryMessage
    end

    def add(severity : Severity, message : String, progname : String? = nil) : Bool
      @messages << MemoryMessage.new(severity: severity, message: message)
      true
    end

    def clear : Nil
      @messages.clear
    end

    def debug(message : String) : Bool
      add(Severity::DEBUG, message)
    end

    def empty? : Bool
      @messages.empty?
    end

    def error(message : String) : Bool
      add(Severity::ERROR, message)
    end

    def error(&block : -> String) : Bool
      add(Severity::ERROR, block.call)
    end

    def fatal(message : String) : Bool
      add(Severity::FATAL, message)
    end

    def info(message : String) : Bool
      add(Severity::INFO, message)
    end

    def max_severity : Severity?
      return nil if empty?
      @messages.max_of(&.severity)
    end

    def warn(message : String) : Bool
      add(Severity::WARN, message)
    end

    def warn(&block : -> String) : Bool
      add(Severity::WARN, block.call)
    end
  end

  # A logger that discards all messages but tracks the maximum severity.
  class NullLogger
    property max_severity : Severity?

    def initialize
      @max_severity = nil
    end

    def add(severity : Severity, message : String, progname : String? = nil) : Bool
      sev = severity
      if (ms = @max_severity)
        @max_severity = sev if sev > ms
      else
        @max_severity = sev
      end
      true
    end

    def debug(message : String) : Bool
      add(Severity::DEBUG, message)
    end

    def error(message : String) : Bool
      add(Severity::ERROR, message)
    end

    def error(&block : -> String) : Bool
      add(Severity::ERROR, block.call)
    end

    def fatal(message : String) : Bool
      add(Severity::FATAL, message)
    end

    def info(message : String) : Bool
      add(Severity::INFO, message)
    end

    def warn(message : String) : Bool
      add(Severity::WARN, message)
    end

    def warn(&block : -> String) : Bool
      add(Severity::WARN, block.call)
    end
  end

  # Manages the global logger instance.
  module LoggerManager
    @@logger : Logger | MemoryLogger | NullLogger | Nil = nil

    def self.logger : Logger | MemoryLogger | NullLogger
      @@logger ||= Logger.new(STDERR)
    end

    def self.logger=(new_logger : Logger | MemoryLogger | NullLogger | Nil)
      @@logger = new_logger || Logger.new(STDERR)
    end
  end

  # Module to be included in classes that need logging support.
  # Provides a `logger` method that delegates to LoggerManager.
  module Logging
    def logger
      LoggerManager.logger
    end

    def message_with_context(text : String, source_location : String? = nil) : LogMessage
      LogMessage.new(text: text, source_location: source_location)
    end
  end
end
