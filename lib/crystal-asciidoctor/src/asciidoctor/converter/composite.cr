module Asciidoctor
  module Converter
    # A Converter implementation that delegates to the chain of Converter objects
    # passed to the constructor. Selects the first Converter that identifies itself
    # as the handler for a given transform.
    #
    # Ported from Ruby Asciidoctor lib/asciidoctor/converter/composite.rb
    class CompositeConverter < Base
      # Get the Array of Converter objects in the chain.
      getter converters : Array(Base)

      @converter_cache : Hash(String, Base)

      def initialize(backend : String)
        super(backend)
        @converters = [] of Base
        @converter_cache = {} of String => Base
      end

      def initialize(backend : String, converters : Array(Base), backend_traits_source : Base | Nil = nil)
        super(backend)
        @converters = converters
        @converter_cache = {} of String => Base
        if backend_traits_source
          init_backend_traits(backend_traits_source.backend_traits)
        end
      end

      # Delegates to the first converter that identifies itself as the handler
      # for the given transform.
      def convert(node : AbstractNode, transform : String? = nil) : String
        transform ||= node.node_name
        (converter_for(transform)).convert(node, transform)
      end

      # Retrieve the converter for the specified transform (with caching).
      def converter_for(transform : String) : Base
        @converter_cache[transform] ||= find_converter(transform)
      end

      # Dispatch conversion to the appropriate method (delegates to convert).
      def dispatch(node : AbstractNode, transform : String) : String
        convert(node, transform)
      end

      # Find the converter for the specified transform.
      # Raises an exception if no converter is found.
      def find_converter(transform : String) : Base
        @converters.each do |candidate|
          return candidate if candidate.handles?(transform)
        end
        raise "Could not find a converter to handle transform: #{transform}"
      end
    end
  end
end
