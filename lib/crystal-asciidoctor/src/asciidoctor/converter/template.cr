module Asciidoctor
  module Converter
    # A Converter implementation that uses templates to convert AbstractNode objects
    # from a parsed AsciiDoc document tree to the backend format.
    #
    # Crystal uses ECR as its native template engine. This implementation provides
    # the base class and template discovery logic. Specific template engine adapters
    # (Slim, Haml, ERB equivalents) can be added later.
    #
    # Ported from Ruby Asciidoctor lib/asciidoctor/converter/template.rb
    class TemplateConverter < Base
      # The registered templates keyed by transform name.
      getter templates : Hash(String, String)

      # The template directories to scan.
      getter template_dirs : Array(String)

      def initialize(backend : String)
        super(backend)
        @templates = {} of String => String
        @template_dirs = [] of String
      end

      def initialize(backend : String, template_dirs : Array(String), opts : Hash(String, String) = {} of String => String)
        super(backend)
        @templates = {} of String => String
        @template_dirs = template_dirs
        scan
      end

      # Convert an AbstractNode to the backend format using the named template.
      def convert(node : AbstractNode, transform : String? = nil) : String
        template_name = transform || node.node_name
        unless (template_path = @templates[template_name]?)
          raise "Could not find a custom template to handle transform: #{template_name}"
        end
        # In Crystal, ECR templates are compiled at compile time.
        # At runtime, we read the template file and do basic variable substitution.
        render_template(template_path, node)
      end

      # Dispatch conversion (delegates to convert).
      def dispatch(node : AbstractNode, transform : String) : String
        convert(node, transform)
      end

      # Check whether there is a template registered with the specified name.
      def handles?(name : String) : Bool
        @templates.has_key?(name)
      end

      # Register a template with this converter.
      def register(name : String, template_path : String) : String
        @templates[name] = template_path
        template_path
      end

      private def render_template(template_path : String, node : AbstractNode) : String
        # Basic template rendering: read the file and return content.
        # Full ECR integration would require compile-time macros.
        # For now, provide a simple placeholder rendering.
        if File.exists?(template_path)
          content = File.read(template_path).strip
          # Simple variable substitution for basic templates
          content = content.gsub(/\{\{content\}\}/) { node.is_a?(AbstractBlock) ? (node.content || "") : "" }
          content = content.gsub(/\{\{title\}\}/) { node.is_a?(AbstractBlock) ? (node.title || "") : "" }
          content = content.gsub(/\{\{id\}\}/) { node.id || "" }
          content
        else
          ""
        end
      end

      private def scan : Nil
        @template_dirs.each do |template_dir|
          next unless Dir.exists?(template_dir)

          # Check for backend-specific subdirectory
          backend_dir = File.join(template_dir, @backend)
          scan_dir = Dir.exists?(backend_dir) ? backend_dir : template_dir

          # Scan for template files
          Dir.glob(File.join(scan_dir, "*")).each do |file|
            next unless File.file?(file)
            basename = File.basename(file)
            # Skip hidden files and helpers
            next if basename.starts_with?(".")
            next if basename == "helpers.rb" || basename == "helpers.cr"

            # Extract transform name from filename
            # e.g., block_paragraph.html.slim -> paragraph
            # e.g., paragraph.html.ecr -> paragraph
            segments = basename.split(".")
            next if segments.size < 2

            name = segments[0]
            # Normalize block_ prefix (Ruby convention)
            if name == "block_ruler"
              name = "thematic_break"
            elsif name.starts_with?("block_")
              name = name[6..]
            end

            @templates[name] = file
          end
        end
      end
    end
  end
end
