module Asciidoctor
  # A utility class for working with the built-in stylesheets.
  #
  # Ported from Ruby Asciidoctor lib/asciidoctor/stylesheets.rb
  class Stylesheets
    DEFAULT_STYLESHEET_NAME = "asciidoctor.css"

    # Singleton instance.
    @@instance : Stylesheets?

    # The cached primary stylesheet data.
    @primary_stylesheet_data : String?

    def initialize
    end

    # Get the singleton instance.
    def self.instance : Stylesheets
      @@instance ||= new
    end

    # Embed the primary stylesheet in a <style> tag.
    def embed_primary_stylesheet : String
      %(<style>\n#{primary_stylesheet_data}\n</style>)
    end

    # Get the primary stylesheet data.
    #
    # The CSS is loaded from the embedded constant or from the data directory.
    def primary_stylesheet_data : String
      @primary_stylesheet_data ||= begin
        # Try to load from the data directory relative to the project
        css_paths = [
          File.join(Dir.current, "data", "stylesheets", "asciidoctor-default.css"),
          File.join(File.dirname(File.dirname(File.dirname(__DIR__))), "data", "stylesheets", "asciidoctor-default.css"),
        ]
        css_content = ""
        css_paths.each do |path|
          if File.exists?(path)
            css_content = File.read(path).rstrip
            break
          end
        end
        css_content.empty? ? DEFAULT_STYLESHEET_DATA : css_content
      end
    end

    # Get the primary stylesheet name.
    def primary_stylesheet_name : String
      DEFAULT_STYLESHEET_NAME
    end

    # Write the primary stylesheet to the specified directory.
    def write_primary_stylesheet(target_dir : String = ".") : Nil
      File.write(File.join(target_dir, primary_stylesheet_name), primary_stylesheet_data)
    end

    # Minimal embedded CSS fallback if the file is not found.
    DEFAULT_STYLESHEET_DATA = <<-CSS
    /* Asciidoctor default stylesheet - minimal fallback */
    body { font-family: "Noto Serif", "DejaVu Serif", serif; font-size: 1em; line-height: 1.6; color: rgba(0,0,0,.8); background: #fff; }
    #content { margin: 0 auto; max-width: 62.5em; padding: 0 1em; }
    h1, h2, h3, h4, h5, h6 { font-family: "Open Sans", "DejaVu Sans", sans-serif; font-weight: 300; color: #ba3925; }
    a { color: #2156a5; text-decoration: underline; }
    pre { background: #f7f7f8; padding: 1em; overflow-x: auto; }
    code { font-family: "Droid Sans Mono", "DejaVu Sans Mono", monospace; }
    .admonitionblock td.icon { font-size: 2.5em; width: 80px; text-align: center; }
    table.tableblock { border-collapse: collapse; width: 100%; }
    table.tableblock td, table.tableblock th { border: 1px solid #dedede; padding: .5em .75em; }
    CSS
  end
end
