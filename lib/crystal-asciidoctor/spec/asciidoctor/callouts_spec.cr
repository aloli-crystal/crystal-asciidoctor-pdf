require "../spec_helper"

describe Asciidoctor::Callouts do
  describe "#register" do
    it "returns a unique callout id" do
      callouts = Asciidoctor::Callouts.new
      id = callouts.register(1)
      id.should eq("CO1-1")
    end

    it "increments the callout index" do
      callouts = Asciidoctor::Callouts.new
      callouts.register(1).should eq("CO1-1")
      callouts.register(2).should eq("CO1-2")
    end
  end

  describe "#next_list" do
    it "advances to the next callout list" do
      callouts = Asciidoctor::Callouts.new
      callouts.register(1)
      callouts.next_list
      id = callouts.register(1)
      id.should eq("CO2-1")
    end
  end

  describe "#read_next_id" do
    it "reads the next callout id" do
      callouts = Asciidoctor::Callouts.new
      callouts.register(1)
      callouts.register(2)
      callouts.rewind
      callouts.read_next_id.should eq("CO1-1")
      callouts.read_next_id.should eq("CO1-2")
    end

    it "returns nil when no more callouts" do
      callouts = Asciidoctor::Callouts.new
      callouts.register(1)
      callouts.rewind
      callouts.read_next_id.should eq("CO1-1")
      callouts.read_next_id.should be_nil
    end
  end

  describe "#callout_ids" do
    it "returns space-separated callout ids for the specified list item" do
      callouts = Asciidoctor::Callouts.new
      callouts.register(1)
      callouts.register(1)
      callouts.register(2)
      ids = callouts.callout_ids(1)
      ids.should eq("CO1-1 CO1-2")
    end

    it "returns empty string when no callouts match" do
      callouts = Asciidoctor::Callouts.new
      callouts.register(1)
      ids = callouts.callout_ids(99)
      ids.should eq("")
    end
  end

  describe "#rewind" do
    it "resets the list index and callout index" do
      callouts = Asciidoctor::Callouts.new
      callouts.register(1)
      callouts.register(2)
      callouts.next_list
      callouts.register(1)
      callouts.rewind
      callouts.read_next_id.should eq("CO1-1")
    end
  end
end
