require "./crystal-asciidoctor"

options = Asciidoctor::Cli::Options.parse(ARGV)
invoker = Asciidoctor::Cli::Invoker.new(options)
exit invoker.invoke!
