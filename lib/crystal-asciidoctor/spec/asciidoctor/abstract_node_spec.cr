require "../spec_helper"

# We test AbstractNode through Block since AbstractNode is abstract
describe "AbstractNode (via Block)" do
  describe "#add_role" do
    it "adds a new role" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.add_role("center").should be_true
      block.roles.should eq(["lead", "center"])
    end

    it "does not add a duplicate role" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.add_role("lead").should be_false
    end

    it "sets role when none exists" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.add_role("lead").should be_true
      block.role.should eq("lead")
    end
  end

  describe "#attr" do
    it "returns the attribute value" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.attr("role").should eq("lead")
    end

    it "returns default value when attribute is not set" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.attr("missing", "default").should eq("default")
    end

    it "returns nil when attribute is not set and no default" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.attr("missing").should be_nil
    end
  end

  describe "#attr?" do
    it "returns true when attribute is set" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.attr?("role").should be_true
    end

    it "returns false when attribute is not set" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.attr?("missing").should be_false
    end

    it "returns true when attribute matches expected value" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.attr?("role", "lead").should be_true
    end

    it "returns false when attribute does not match expected value" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.attr?("role", "other").should be_false
    end
  end

  describe "#converter" do
    it "delegates to the document converter" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.converter.should be_nil
    end
  end

  describe "#enabled_options" do
    it "returns the set of enabled options" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"autoplay-option" => "", "interactive-option" => ""})
      opts = block.enabled_options
      opts.should contain("autoplay")
      opts.should contain("interactive")
    end
  end

  describe "#has_role?" do
    it "returns true when role is present" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead center"})
      block.has_role?("lead").should be_true
    end

    it "returns false when role is not present" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.has_role?("center").should be_false
    end
  end

  describe "#image_uri" do
    it "returns the target as-is if it is a URI" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.image_uri("https://example.com/image.png").should eq("https://example.com/image.png")
    end

    it "prepends imagesdir from document attributes" do
      doc = Asciidoctor::Document.new
      doc.attributes["imagesdir"] = "images"
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.image_uri("photo.png").should eq("images/photo.png")
    end

    it "returns the target as-is when no imagesdir" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.image_uri("photo.png").should eq("photo.png")
    end
  end

  describe "#is_uri?" do
    it "returns true for a valid URI" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.is_uri?("https://example.com").should be_true
      block.is_uri?("ftp://files.example.com").should be_true
    end

    it "returns false for a non-URI" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.is_uri?("images/photo.png").should be_false
      block.is_uri?("/absolute/path").should be_false
    end
  end

  describe "#normalize_web_path" do
    it "returns the target as-is if it is a URI" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.normalize_web_path("https://example.com/page").should eq("https://example.com/page")
    end

    it "returns the target as-is if it starts with /" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.normalize_web_path("/absolute/path").should eq("/absolute/path")
    end

    it "prepends start path" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.normalize_web_path("page.html", "docs").should eq("docs/page.html")
    end

    it "returns target when start is nil" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.normalize_web_path("page.html").should eq("page.html")
    end
  end

  describe "#option?" do
    it "returns true when option is set" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"interactive-option" => ""})
      block.option?("interactive").should be_true
    end

    it "returns false when option is not set" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.option?("interactive").should be_false
    end
  end

  describe "#parent" do
    it "returns the parent node" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.parent.should eq(doc)
    end
  end

  describe "#reftext" do
    it "returns the reftext attribute" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"reftext" => "My Reference"})
      block.reftext.should eq("My Reference")
    end

    it "returns nil when no reftext" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.reftext.should be_nil
    end
  end

  describe "#reftext?" do
    it "returns true when reftext is set" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"reftext" => "My Reference"})
      block.reftext?.should be_true
    end

    it "returns false when reftext is not set" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.reftext?.should be_false
    end
  end

  describe "#remove_attr" do
    it "removes an existing attribute" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.remove_attr("role").should eq("lead")
      block.attr?("role").should be_false
    end
  end

  describe "#remove_role" do
    it "removes an existing role" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead center"})
      block.remove_role("lead").should be_true
      block.role.should eq("center")
    end

    it "removes the last role and deletes the attribute" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.remove_role("lead").should be_true
      block.role.should be_nil
    end

    it "returns false when role is not present" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.remove_role("center").should be_false
    end
  end

  describe "#role" do
    it "returns the role attribute" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead"})
      block.role.should eq("lead")
    end

    it "returns nil when no role is set" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.role.should be_nil
    end
  end

  describe "#roles" do
    it "returns roles as array" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "lead center"})
      block.roles.should eq(["lead", "center"])
    end

    it "returns empty array when no role" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.roles.should be_empty
    end
  end

  describe "#set_attr" do
    it "sets a new attribute" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.set_attr("role", "lead").should be_true
      block.attr("role").should eq("lead")
    end

    it "overwrites existing attribute by default" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "old"})
      block.set_attr("role", "new").should be_true
      block.attr("role").should eq("new")
    end

    it "does not overwrite when overwrite is false" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph, attributes: {"role" => "old"})
      block.set_attr("role", "new", false).should be_false
      block.attr("role").should eq("old")
    end
  end

  describe "#set_option" do
    it "sets an option" do
      doc = Asciidoctor::Document.new
      block = Asciidoctor::Block.new(doc, :paragraph)
      block.set_option("interactive")
      block.option?("interactive").should be_true
    end
  end
end
