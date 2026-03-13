require "../spec_helper"

# Helper methods
def convert_string_to_embedded(input : String, options : Hash(String, String) = {} of String => String) : String
  options["standalone"] = "false"
  Asciidoctor.convert(input, options)
end

describe Asciidoctor::Logger do
  describe "initialization" do
    it "should configure logger with level set to WARN by default" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      # Default level is WARN, so debug/info should not be logged
      logger.debug("debug message")
      logger.info("info message")
      io.to_s.should be_empty
    end

    it "should log WARN messages by default" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.warn("warning message")
      io.to_s.should contain("warning message")
    end

    it "should log FATAL messages" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.fatal("fatal message")
      io.to_s.should contain("fatal message")
    end

    it "should log ERROR messages" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.error("error message")
      io.to_s.should contain("error message")
    end

    it "should not log DEBUG messages at default level" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.debug("debug message")
      io.to_s.should be_empty
    end

    it "should not log INFO messages at default level" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.info("info message")
      io.to_s.should be_empty
    end
  end

  describe "BasicFormatter" do
    it "should format WARN as WARNING" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.warn("this is a call")
      io.to_s.should contain("asciidoctor: WARNING: this is a call")
    end

    it "should format FATAL as FAILED" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.fatal("it cannot be done")
      io.to_s.should contain("asciidoctor: FAILED: it cannot be done")
    end

    it "should format ERROR as ERROR" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.error("something went wrong")
      io.to_s.should contain("asciidoctor: ERROR: something went wrong")
    end
  end

  describe "max_severity tracking" do
    it "should track max severity" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.max_severity.should be_nil
      logger.warn("warn")
      logger.max_severity.should eq(Asciidoctor::Severity::WARN)
      logger.error("error")
      logger.max_severity.should eq(Asciidoctor::Severity::ERROR)
    end

    it "should not decrease max severity" do
      io = IO::Memory.new
      logger = Asciidoctor::Logger.new(io)
      logger.error("error")
      logger.warn("warn")
      logger.max_severity.should eq(Asciidoctor::Severity::ERROR)
    end
  end
end

describe Asciidoctor::MemoryLogger do
  it "should store messages in memory" do
    logger = Asciidoctor::MemoryLogger.new
    logger.warn("warning 1")
    logger.error("error 1")
    logger.messages.size.should eq(2)
  end

  it "should store message severity" do
    logger = Asciidoctor::MemoryLogger.new
    logger.warn("warning 1")
    logger.messages.first.severity.should eq(Asciidoctor::Severity::WARN)
  end

  it "should store message text" do
    logger = Asciidoctor::MemoryLogger.new
    logger.warn("warning 1")
    logger.messages.first.message.should eq("warning 1")
  end

  it "should clear messages" do
    logger = Asciidoctor::MemoryLogger.new
    logger.warn("warning 1")
    logger.clear
    logger.messages.should be_empty
  end

  it "should report empty? correctly" do
    logger = Asciidoctor::MemoryLogger.new
    logger.empty?.should be_true
    logger.warn("warning 1")
    logger.empty?.should be_false
  end

  it "should compute max_severity" do
    logger = Asciidoctor::MemoryLogger.new
    logger.max_severity.should be_nil
    logger.warn("warning 1")
    logger.max_severity.should eq(Asciidoctor::Severity::WARN)
    logger.error("error 1")
    logger.max_severity.should eq(Asciidoctor::Severity::ERROR)
  end

  it "should support error with block" do
    logger = Asciidoctor::MemoryLogger.new
    logger.error { "lazy error" }
    logger.messages.first.message.should eq("lazy error")
    logger.messages.first.severity.should eq(Asciidoctor::Severity::ERROR)
  end

  it "should support warn with block" do
    logger = Asciidoctor::MemoryLogger.new
    logger.warn { "lazy warn" }
    logger.messages.first.message.should eq("lazy warn")
    logger.messages.first.severity.should eq(Asciidoctor::Severity::WARN)
  end
end

describe Asciidoctor::NullLogger do
  it "should discard all messages" do
    logger = Asciidoctor::NullLogger.new
    logger.warn("warning 1")
    logger.error("error 1")
    logger.fatal("fatal 1")
    # NullLogger has no messages accessor, it just tracks max_severity
    logger.max_severity.should eq(Asciidoctor::Severity::FATAL)
  end

  it "should track max severity" do
    logger = Asciidoctor::NullLogger.new
    logger.max_severity.should be_nil
    logger.warn("warn")
    logger.max_severity.should eq(Asciidoctor::Severity::WARN)
    logger.error("error")
    logger.max_severity.should eq(Asciidoctor::Severity::ERROR)
  end

  it "should not decrease max severity" do
    logger = Asciidoctor::NullLogger.new
    logger.fatal("fatal")
    logger.warn("warn")
    logger.max_severity.should eq(Asciidoctor::Severity::FATAL)
  end
end

describe Asciidoctor::LoggerManager do
  it "should provide access to logger via static logger method" do
    logger = Asciidoctor::LoggerManager.logger
    logger.should_not be_nil
    logger.should be_a(Asciidoctor::Logger)
  end

  it "should allow logger instance to be changed" do
    old_logger = Asciidoctor::LoggerManager.logger
    begin
      new_logger = Asciidoctor::MemoryLogger.new
      Asciidoctor::LoggerManager.logger = new_logger
      Asciidoctor::LoggerManager.logger.should be(new_logger)
    ensure
      Asciidoctor::LoggerManager.logger = old_logger
    end
  end

  it "should reset to default logger when set to nil" do
    old_logger = Asciidoctor::LoggerManager.logger
    begin
      Asciidoctor::LoggerManager.logger = Asciidoctor::MemoryLogger.new
      Asciidoctor::LoggerManager.logger = nil
      Asciidoctor::LoggerManager.logger.should_not be_nil
      Asciidoctor::LoggerManager.logger.should be_a(Asciidoctor::Logger)
    ensure
      Asciidoctor::LoggerManager.logger = old_logger
    end
  end
end

describe Asciidoctor::LogMessage do
  it "should create a log message with text" do
    msg = Asciidoctor::LogMessage.new(text: "test message")
    msg.text.should eq("test message")
    msg.source_location.should be_nil
  end

  it "should create a log message with text and source location" do
    msg = Asciidoctor::LogMessage.new(text: "test message", source_location: "file.adoc: line 5")
    msg.text.should eq("test message")
    msg.source_location.should eq("file.adoc: line 5")
  end

  it "should format message with source location in inspect" do
    msg = Asciidoctor::LogMessage.new(text: "test message", source_location: "file.adoc: line 5")
    msg.inspect.should eq("file.adoc: line 5: test message")
  end

  it "should format message without source location in inspect" do
    msg = Asciidoctor::LogMessage.new(text: "test message")
    msg.inspect.should eq("test message")
  end
end

describe Asciidoctor::Logging do
  it "should provide logger access through Logging module" do
    # Test that a class including Logging can access the logger
    obj = Asciidoctor::PathResolver.new # PathResolver includes Logging
    obj.logger.should_not be_nil
    obj.logger.should be(Asciidoctor::LoggerManager.logger)
  end

  it "should provide message_with_context method" do
    obj = Asciidoctor::PathResolver.new
    msg = obj.message_with_context("test message", source_location: "file.adoc: line 5")
    msg.text.should eq("test message")
    msg.source_location.should eq("file.adoc: line 5")
  end
end
