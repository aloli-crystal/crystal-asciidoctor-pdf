require "option_parser"

module Asciidoctor
  module Cli
    class Options
      property attributes : Hash(String, String)
      property backend : String
      property base_dir : String?
      property destination_dir : String?
      property doctype : String
      property embedded : Bool
      property input_files : Array(String)
      property output_file : String?
      property safe_mode : Int32
      property section_numbers : Bool
      property sourcemap : Bool
      property standalone : Bool
      property verbose : Int32

      def initialize
        @attributes = {} of String => String
        @backend = "html5"
        @base_dir = nil
        @destination_dir = nil
        @doctype = "article"
        @embedded = false
        @input_files = [] of String
        @output_file = nil
        @safe_mode = SafeMode::UNSAFE
        @section_numbers = false
        @sourcemap = false
        @standalone = true
        @verbose = 1
      end

      def self.parse(args : Array(String)) : Options
        opts = Options.new
        show_version = false

        parser = OptionParser.new do |p|
          p.banner = "Usage: asciidoctor [OPTION]... FILE...\nConvert AsciiDoc input to the backend output format (e.g., HTML 5, DocBook 5, etc.)\n"

          p.on("-b BACKEND", "--backend=BACKEND", "Set backend output format (default: html5)") do |backend|
            opts.backend = backend
          end

          p.on("-d DOCTYPE", "--doctype=DOCTYPE", "Document type: article, book, manpage, inline (default: article)") do |doctype|
            opts.doctype = doctype
          end

          p.on("-e", "--embedded", "Suppress enclosing document structure") do
            opts.embedded = true
            opts.standalone = false
          end

          p.on("-o FILE", "--out-file=FILE", "Output file (default: based on input file); use - for STDOUT") do |file|
            opts.output_file = file
          end

          p.on("-s", "--no-header-footer", "Suppress enclosing document structure") do
            opts.standalone = false
          end

          p.on("-n", "--section-numbers", "Auto-number section titles") do
            opts.section_numbers = true
            opts.attributes["sectnums"] = ""
          end

          p.on("-a ATTRIBUTE", "--attribute=ATTRIBUTE", "Set a document attribute (name=value)") do |attr|
            next if attr.strip.empty?
            name, _, val = attr.partition("=")
            opts.attributes[name.strip] = val.strip
          end

          p.on("-B DIR", "--base-dir=DIR", "Base directory for the document") do |dir|
            opts.base_dir = dir
          end

          p.on("-D DIR", "--destination-dir=DIR", "Destination output directory") do |dir|
            opts.destination_dir = dir
          end

          p.on("-S SAFE_MODE", "--safe-mode=SAFE_MODE", "Set safe mode: unsafe, safe, server, secure (default: unsafe)") do |mode|
            opts.safe_mode = SafeMode.value_for_name(mode) || SafeMode::UNSAFE
          end

          p.on("--sourcemap", "Add source location information to each parsed block") do
            opts.sourcemap = true
          end

          p.on("-q", "--quiet", "Silence application log messages") do
            opts.verbose = 0
          end

          p.on("-v", "--verbose", "Show all log messages") do
            opts.verbose = 2
          end

          p.on("-V", "--version", "Display the version") do
            show_version = true
          end

          p.on("-h", "--help", "Print this help message") do
            STDOUT.puts p
            exit 0
          end
        end

        parser.parse(args)

        if show_version
          STDOUT.puts "Asciidoctor Crystal #{VERSION}"
          exit 0
        end

        # Remaining args are input files
        args.each do |arg|
          unless arg.starts_with?("-")
            if File.file?(arg)
              opts.input_files << arg
            else
              STDERR.puts "asciidoctor: FAILED: input file not found: #{arg}"
            end
          end
        end

        opts
      end

      def to_options_hash : Hash(String, String)
        result = {} of String => String
        result["backend"] = @backend
        result["doctype"] = @doctype
        result["safe"] = @safe_mode.to_s.downcase
        result["standalone"] = @standalone.to_s
        result["sourcemap"] = @sourcemap.to_s
        attrs = @attributes.map { |k, v| "#{k}=#{v}" }.join(",")
        result["attributes"] = attrs unless attrs.empty?
        result
      end
    end
  end
end
