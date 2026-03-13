require "../spec_helper"

describe Asciidoctor::ContentModel do
  it "defines Compound" do
    Asciidoctor::ContentModel::Compound.should_not be_nil
  end

  it "defines Simple" do
    Asciidoctor::ContentModel::Simple.should_not be_nil
  end

  it "defines Verbatim" do
    Asciidoctor::ContentModel::Verbatim.should_not be_nil
  end

  it "defines Raw" do
    Asciidoctor::ContentModel::Raw.should_not be_nil
  end

  it "defines Empty" do
    Asciidoctor::ContentModel::Empty.should_not be_nil
  end
end
