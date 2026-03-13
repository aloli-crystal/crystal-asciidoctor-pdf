require "../spec_helper"

describe Asciidoctor::Timings do
  describe "#start and #record" do
    it "records elapsed time for a key" do
      timings = Asciidoctor::Timings.new
      timings.start(:read)
      sleep 0.01
      timings.record(:read)
      result = timings.read
      result.should_not be_nil
      result.not_nil!.should be > 0.0
    end
  end

  describe "#read" do
    it "returns nil if read has not been recorded" do
      timings = Asciidoctor::Timings.new
      timings.read.should be_nil
    end
  end

  describe "#parse" do
    it "returns nil if parse has not been recorded" do
      timings = Asciidoctor::Timings.new
      timings.parse.should be_nil
    end
  end

  describe "#convert" do
    it "returns nil if convert has not been recorded" do
      timings = Asciidoctor::Timings.new
      timings.convert.should be_nil
    end
  end

  describe "#write" do
    it "returns nil if write has not been recorded" do
      timings = Asciidoctor::Timings.new
      timings.write.should be_nil
    end
  end

  describe "#total" do
    it "returns nil if no phases have been recorded" do
      timings = Asciidoctor::Timings.new
      timings.total.should be_nil
    end

    it "returns combined time of all recorded phases" do
      timings = Asciidoctor::Timings.new
      timings.start(:read)
      sleep 0.01
      timings.record(:read)
      timings.start(:parse)
      sleep 0.01
      timings.record(:parse)
      total = timings.read_parse
      total.should_not be_nil
      total.not_nil!.should be > 0.0
    end
  end

  describe "#read_parse" do
    it "returns combined time for read and parse" do
      timings = Asciidoctor::Timings.new
      timings.start(:read)
      sleep 0.01
      timings.record(:read)
      timings.start(:parse)
      sleep 0.01
      timings.record(:parse)
      result = timings.read_parse
      result.should_not be_nil
      read_val = timings.read.not_nil!
      result.not_nil!.should be >= read_val
    end
  end

  describe "#print_report" do
    it "prints timing report to IO" do
      timings = Asciidoctor::Timings.new
      timings.start(:read)
      sleep 0.01
      timings.record(:read)
      timings.start(:parse)
      sleep 0.01
      timings.record(:parse)
      timings.start(:convert)
      sleep 0.01
      timings.record(:convert)

      io = IO::Memory.new
      timings.print_report(io, "test.adoc")
      output = io.to_s
      output.should contain("Input file: test.adoc")
      output.should contain("Time to read and parse source:")
      output.should contain("Time to convert document:")
      output.should contain("Total time (read, parse and convert):")
    end

    it "prints timing report without subject" do
      timings = Asciidoctor::Timings.new
      io = IO::Memory.new
      timings.print_report(io)
      output = io.to_s
      output.should_not contain("Input file:")
      output.should contain("Time to read and parse source:")
    end
  end
end
