module Asciidoctor
  # A module that can be used to mix the `write` method into a Converter
  # implementation to allow the converter to control how the output is written to disk.
  module Writer
    # Public: Writes the output to the specified target file name or stream.
    #
    # output - The output String to write
    # target - The String file name or IO object to which the output should be written.
    def write(output : String, target : IO) : Nil
      # Ensure there's a trailing newline to be nice to terminals
      target.print(output.chomp + LF)
    end

    # Public: Writes the output to the specified target file path.
    #
    # output - The output String to write
    # target - The String file path to which the output should be written.
    def write(output : String, target : String) : Nil
      File.write(target, output)
    end
  end

  # A module that suppresses output writing.
  module VoidWriter
    include Writer

    # Public: Does not write output.
    def write(output : String, target : IO) : Nil
    end

    # Public: Does not write output.
    def write(output : String, target : String) : Nil
    end
  end
end
