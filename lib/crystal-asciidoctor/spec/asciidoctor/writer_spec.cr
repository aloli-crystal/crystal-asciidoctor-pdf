require "../spec_helper"

# Helper class to test Writer module
class TestWriter
  include Asciidoctor::Writer
end

# Helper class to test VoidWriter module
class TestVoidWriter
  include Asciidoctor::VoidWriter
end

describe Asciidoctor::Writer do
  describe "#write to IO" do
    it "writes output to IO with trailing newline" do
      writer = TestWriter.new
      io = IO::Memory.new
      writer.write("hello", io)
      io.to_s.should eq("hello\n")
    end

    it "does not double trailing newline" do
      writer = TestWriter.new
      io = IO::Memory.new
      writer.write("hello\n", io)
      io.to_s.should eq("hello\n")
    end
  end

  describe "#write to file" do
    it "writes output to a file" do
      writer = TestWriter.new
      path = "/tmp/asciidoctor_writer_test_#{Random.rand(100000)}.txt"
      begin
        writer.write("hello world", path)
        File.read(path).should eq("hello world")
      ensure
        File.delete(path) if File.exists?(path)
      end
    end
  end
end

describe Asciidoctor::VoidWriter do
  describe "#write to IO" do
    it "does not write anything" do
      writer = TestVoidWriter.new
      io = IO::Memory.new
      writer.write("hello", io)
      io.to_s.should eq("")
    end
  end

  describe "#write to file" do
    it "does not write anything" do
      writer = TestVoidWriter.new
      path = "/tmp/asciidoctor_void_writer_test_#{Random.rand(100000)}.txt"
      writer.write("hello", path)
      File.exists?(path).should be_false
    end
  end
end
