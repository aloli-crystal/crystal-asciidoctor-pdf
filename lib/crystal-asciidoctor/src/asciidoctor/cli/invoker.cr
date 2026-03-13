module Asciidoctor
  module Cli
    class Invoker
      property options : Options
      property document : Document?
      property output : String?

      def initialize(@options : Options)
        @document = nil
        @output = nil
      end

      def invoke! : Int32
        if @options.input_files.empty?
          STDERR.puts "asciidoctor: FAILED: input file(s) are required."
          return 1
        end

        @options.input_files.each do |infile|
          begin
            process_file(infile)
          rescue ex
            STDERR.puts "asciidoctor: FAILED: #{infile}: #{ex.message}"
            return 1
          end
        end

        0
      end

      private def process_file(infile : String)
        opts_hash = @options.to_options_hash

        if infile == "-"
          source = STDIN.gets_to_end
        else
          source = File.read(infile)
          opts_hash["docfile"] = File.expand_path(infile)
          opts_hash["docdir"] = File.dirname(File.expand_path(infile))
          opts_hash["docname"] = File.basename(infile, File.extname(infile))
        end

        doc = Asciidoctor.load(source, opts_hash)
        @document = doc

        converter = doc.converter || Asciidoctor.send(:create_converter, doc.backend)
        converted = converter.convert(doc)
        @output = converted

        outfile = determine_output_file(infile, doc)

        if outfile == "-"
          STDOUT.puts converted
        elsif outfile
          dir = File.dirname(outfile)
          Dir.mkdir_p(dir) unless Dir.exists?(dir)
          File.write(outfile, converted)
        else
          STDOUT.puts converted
        end
      end

      private def determine_output_file(infile : String, doc : Document) : String?
        if (explicit = @options.output_file)
          return explicit
        end

        return nil if infile == "-"

        dest_dir = @options.destination_dir
        docname = doc.attributes["docname"]? || File.basename(infile, File.extname(infile))
        ext = doc.outfilesuffix

        if dest_dir
          File.join(dest_dir, "#{docname}#{ext}")
        else
          dir = File.dirname(File.expand_path(infile))
          File.join(dir, "#{docname}#{ext}")
        end
      end
    end
  end
end
