require "../spec_helper"

JAIL = "/home/doctor/docs"

describe Asciidoctor::PathResolver do
  describe "Web Paths" do
    it "should return target with absolute path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("/images").should eq("/images")
      resolver.web_path("/images", "").should eq("/images")
      resolver.web_path("/images", nil).should eq("/images")
    end

    it "should return target with relative path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("images").should eq("images")
      resolver.web_path("images", "").should eq("images")
      resolver.web_path("images", nil).should eq("images")
    end

    it "should return target with hidden relative path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path(".images").should eq(".images")
      resolver.web_path(".images", "").should eq(".images")
      resolver.web_path(".images", nil).should eq(".images")
    end

    it "should return target with path relative to current directory" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("./images").should eq("./images")
      resolver.web_path("./images", "").should eq("./images")
      resolver.web_path("./images", nil).should eq("./images")
    end

    it "should ignore start path when target is an absolute path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("/images", "foo").should eq("/images")
      resolver.web_path("/images", "/foo").should eq("/images")
      resolver.web_path("/images", "./foo").should eq("/images")
    end

    it "should append target to start path when target is a relative path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("images", "assets").should eq("assets/images")
      resolver.web_path("images", "/assets").should eq("/assets/images")
      resolver.web_path("images", "./assets").should eq("./assets/images")
      resolver.web_path("theme.css", "/").should eq("/theme.css")
      resolver.web_path("theme.css", "/css/").should eq("/css/theme.css")
    end

    it "should append target with path relative to current directory to start path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("./images", "assets").should eq("assets/images")
      resolver.web_path("./images", "/assets").should eq("/assets/images")
      resolver.web_path("./images", "./assets").should eq("./assets/images")
    end

    it "should append relative target path to URL start path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("images", "http://www.example.com/assets").should eq("http://www.example.com/assets/images")
    end

    it "should normalize target" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("../images/../images").should eq("../images")
    end

    it "should append target to start path and normalize" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("../images/../images", "../images").should eq("../images")
      resolver.web_path("../images", "..").should eq("../../images")
    end

    it "should normalize parent directory that follows root" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("/../tiger.png").should eq("/tiger.png")
      resolver.web_path("/../../tiger.png").should eq("/tiger.png")
    end

    it "should use start when target is empty" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("", "assets/images").should eq("assets/images")
      resolver.web_path(nil, "assets/images").should eq("assets/images")
    end

    it "should posixify windows paths" do
      resolver = Asciidoctor::PathResolver.new
      resolver.file_separator = "\\"
      resolver.web_path("\\images").should eq("/images")
      resolver.web_path("..\\images").should eq("../images")
      resolver.web_path("\\..\\images").should eq("/images")
      resolver.web_path("assets\\images").should eq("assets/images")
      resolver.web_path("assets\\images", "..\\images\\..").should eq("../assets/images")
    end

    it "should URL encode spaces in path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_path("lots of images", "assets and stuff").should eq("assets%20and%20stuff/lots%20of%20images")
    end
  end

  describe "System Paths" do
    it "should raise security error if jail is not an absolute path" do
      resolver = Asciidoctor::PathResolver.new
      expect_raises(SecurityError) do
        resolver.system_path("images/tiger.png", "/etc", "foo")
      end
    end

    it "should prevent access to paths outside of jail" do
      old_logger = Asciidoctor::LoggerManager.logger
      logger = Asciidoctor::MemoryLogger.new
      Asciidoctor::LoggerManager.logger = logger
      begin
        resolver = Asciidoctor::PathResolver.new
        resolver.system_path("../../../../../css", "#{JAIL}/assets/stylesheets", JAIL).should eq("#{JAIL}/css")
        logger.messages.first.message.should contain("illegal reference to ancestor of jail")

        logger.clear
        resolver.system_path("/../../../../../css", "#{JAIL}/assets/stylesheets", JAIL).should eq("#{JAIL}/css")
        logger.messages.first.message.should contain("outside of jail")

        logger.clear
        resolver.system_path("../../../css", "../../..", JAIL).should eq("#{JAIL}/css")
        logger.messages.first.message.should contain("illegal reference to ancestor of jail")
      ensure
        Asciidoctor::LoggerManager.logger = old_logger
      end
    end

    it "should throw exception for illegal path access if recover is false" do
      resolver = Asciidoctor::PathResolver.new
      expect_raises(SecurityError) do
        resolver.system_path("../../../../../css", "#{JAIL}/assets/stylesheets", JAIL, {:recover => false})
      end
    end

    it "should resolve start path if target is empty" do
      resolver = Asciidoctor::PathResolver.new
      resolver.system_path("", "#{JAIL}/assets/stylesheets", JAIL).should eq("#{JAIL}/assets/stylesheets")
      resolver.system_path(nil, "#{JAIL}/assets/stylesheets", JAIL).should eq("#{JAIL}/assets/stylesheets")
    end

    it "should expand parent references in start path if target is empty" do
      resolver = Asciidoctor::PathResolver.new
      resolver.system_path("", "#{JAIL}/assets/../stylesheets", JAIL).should eq("#{JAIL}/stylesheets")
    end

    it "should expand parent references in start path if target is not empty" do
      resolver = Asciidoctor::PathResolver.new
      resolver.system_path("site.css", "#{JAIL}/assets/../stylesheets", JAIL).should eq("#{JAIL}/stylesheets/site.css")
    end

    it "should resolve start path if target is dot" do
      resolver = Asciidoctor::PathResolver.new
      resolver.system_path(".", "#{JAIL}/assets/stylesheets", JAIL).should eq("#{JAIL}/assets/stylesheets")
      resolver.system_path("./", "#{JAIL}/assets/stylesheets", JAIL).should eq("#{JAIL}/assets/stylesheets")
    end

    it "should treat absolute target outside of jail as relative when jail is specified" do
      old_logger = Asciidoctor::LoggerManager.logger
      logger = Asciidoctor::MemoryLogger.new
      Asciidoctor::LoggerManager.logger = logger
      begin
        resolver = Asciidoctor::PathResolver.new
        resolver.system_path("/", "#{JAIL}/assets/stylesheets", JAIL).should eq(JAIL)
        logger.messages.first.message.should contain("outside of jail")

        logger.clear
        resolver.system_path("/foo", "#{JAIL}/assets/stylesheets", JAIL).should eq("#{JAIL}/foo")
        logger.messages.first.message.should contain("outside of jail")

        logger.clear
        resolver.system_path("/../foo", "#{JAIL}/assets/stylesheets", JAIL).should eq("#{JAIL}/foo")
        logger.messages.first.message.should contain("outside of jail")
      ensure
        Asciidoctor::LoggerManager.logger = old_logger
      end
    end

    it "should allow use of absolute target or start if resolved path is sub-path of jail" do
      resolver = Asciidoctor::PathResolver.new
      resolver.system_path("#{JAIL}/my/path", "", JAIL).should eq("#{JAIL}/my/path")
      resolver.system_path("#{JAIL}/my/path", nil, JAIL).should eq("#{JAIL}/my/path")
      resolver.system_path("", "#{JAIL}/my/path", JAIL).should eq("#{JAIL}/my/path")
      resolver.system_path(nil, "#{JAIL}/my/path", JAIL).should eq("#{JAIL}/my/path")
      resolver.system_path("path", "#{JAIL}/my", JAIL).should eq("#{JAIL}/my/path")
      resolver.system_path("/foo/bar/baz.adoc", nil, "/").should eq("/foo/bar/baz.adoc")
      resolver.system_path("baz.adoc", "/foo/bar", "/").should eq("/foo/bar/baz.adoc")
      resolver.system_path("baz.adoc", "foo/bar", "/").should eq("/foo/bar/baz.adoc")
    end

    it "should use jail path if start path is empty" do
      resolver = Asciidoctor::PathResolver.new
      resolver.system_path("images/tiger.png", "", JAIL).should eq("#{JAIL}/images/tiger.png")
      resolver.system_path("images/tiger.png", nil, JAIL).should eq("#{JAIL}/images/tiger.png")
    end

    it "should warn if start is not contained within jail" do
      old_logger = Asciidoctor::LoggerManager.logger
      logger = Asciidoctor::MemoryLogger.new
      Asciidoctor::LoggerManager.logger = logger
      begin
        resolver = Asciidoctor::PathResolver.new
        resolver.system_path("images/tiger.png", "/etc", JAIL).should eq("#{JAIL}/images/tiger.png")
        logger.messages.first.message.should contain("outside of jail")

        logger.clear
        resolver.system_path(".", "/etc", JAIL).should eq(JAIL)
        logger.messages.first.message.should contain("outside of jail")
      ensure
        Asciidoctor::LoggerManager.logger = old_logger
      end
    end

    it "should allow start path to be parent of jail if resolved target is inside jail" do
      resolver = Asciidoctor::PathResolver.new
      resolver.system_path("foo/path", JAIL, "#{JAIL}/foo").should eq("#{JAIL}/foo/path")
    end

    it "should raise security error if start is not contained within jail and recover is disabled" do
      resolver = Asciidoctor::PathResolver.new
      expect_raises(SecurityError) do
        resolver.system_path("images/tiger.png", "/etc", JAIL, {:recover => false})
      end
      expect_raises(SecurityError) do
        resolver.system_path(".", "/etc", JAIL, {:recover => false})
      end
    end

    it "should expand parent references in absolute path if jail is not specified" do
      resolver = Asciidoctor::PathResolver.new
      resolver.system_path("/usr/share/../../etc/stylesheet.css").should eq("/etc/stylesheet.css")
    end
  end

  describe "Utility methods" do
    it "should detect absolute paths" do
      resolver = Asciidoctor::PathResolver.new
      resolver.absolute_path?("/foo/bar").should be_true
      resolver.absolute_path?("foo/bar").should be_false
    end

    it "should detect root paths" do
      resolver = Asciidoctor::PathResolver.new
      resolver.root?("/foo/bar").should be_true
      resolver.root?("foo/bar").should be_false
    end

    it "should detect web root paths" do
      resolver = Asciidoctor::PathResolver.new
      resolver.web_root?("/foo/bar").should be_true
      resolver.web_root?("foo/bar").should be_false
    end

    it "should detect UNC paths" do
      resolver = Asciidoctor::PathResolver.new
      resolver.unc?("//server/share").should be_true
      resolver.unc?("/foo/bar").should be_false
    end

    it "should posixify paths" do
      resolver = Asciidoctor::PathResolver.new
      resolver.file_separator = "\\"
      resolver.posixify("foo\\bar\\baz").should eq("foo/bar/baz")
      resolver.posixify(nil).should eq("")
    end

    it "should detect descends_from?" do
      resolver = Asciidoctor::PathResolver.new
      resolver.descends_from?("/foo/bar", "/foo").should eq(5)
      resolver.descends_from?("/foo", "/foo").should eq(0)
      resolver.descends_from?("/foo/bar", "/baz").should be_nil
    end

    it "should expand path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.expand_path("/foo/bar/../baz").should eq("/foo/baz")
      resolver.expand_path("/foo/./bar").should eq("/foo/bar")
    end

    it "should join path segments" do
      resolver = Asciidoctor::PathResolver.new
      resolver.join_path(["foo", "bar", "baz"]).should eq("foo/bar/baz")
      resolver.join_path(["foo", "bar"], "/").should eq("/foo/bar")
    end

    it "should partition path" do
      resolver = Asciidoctor::PathResolver.new
      segments, root = resolver.partition_path("/foo/bar/baz")
      segments.should eq(["foo", "bar", "baz"])
      root.should eq("/")
    end

    it "should partition relative path" do
      resolver = Asciidoctor::PathResolver.new
      segments, root = resolver.partition_path("foo/bar/baz")
      segments.should eq(["foo", "bar", "baz"])
      root.should be_nil
    end

    it "should compute relative path" do
      resolver = Asciidoctor::PathResolver.new
      resolver.relative_path("/foo/bar/baz", "/foo").should eq("bar/baz")
      resolver.relative_path("bar/baz", "/foo").should eq("bar/baz")
    end

    it "should detect Windows root paths" do
      resolver = Asciidoctor::PathResolver.new
      resolver.file_separator = "\\"
      resolver.root?("C:\\foo\\bar").should be_true
      resolver.root?("C:/foo/bar").should be_true
      resolver.root?("foo\\bar").should be_false
    end
  end
end
