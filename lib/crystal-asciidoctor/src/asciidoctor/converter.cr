require "./converter/base"

module Asciidoctor
  # A module for defining converters that are used to convert AbstractNode objects
  # in a parsed AsciiDoc document to an output (aka backend) format such as HTML or DocBook.
  #
  # Ported from Ruby Asciidoctor lib/asciidoctor/converter.rb
  module Converter
    # Derive backend traits (basebackend, filetype, outfilesuffix, htmlsyntax) from the given backend.
    def self.derive_backend_traits(backend : String, basebackend : String? = nil) : BackendTraits
      Base.derive_backend_traits(backend, basebackend)
    end

    # The default (global) registry of converters that are registered statically.
    # This registry includes built-in converters for HTML5, DocBook5 and ManPage.
    module DefaultRegistry
      @@registry = {} of String => Base.class
      @@catch_all = "" # empty string means no catch-all

      BUILT_IN_BACKENDS = Set{"html5", "docbook5", "manpage"}

      # Lookup a converter by backend name.
      def self.converter_for(backend : String) : Base.class | Nil
        @@registry[backend]?
      end

      # Get all registered converters.
      def self.converters : Hash(String, Base.class)
        @@registry.dup
      end

      # Create a converter instance for the given backend.
      def self.create(backend : String, opts : Hash(String, String) = {} of String => String) : Base | Nil
        if (converter_class = converter_for(backend))
          converter_class.new(backend)
        else
          nil
        end
      end

      # Register a converter for one or more backends.
      def self.register(converter : Base.class, *backends : String) : Nil
        backends.each do |backend|
          @@registry[backend] = converter
        end
      end

      # Unregister all custom converters (keep built-in ones).
      def self.unregister_all : Nil
        @@registry.select! { |backend, _| BUILT_IN_BACKENDS.includes?(backend) }
      end
    end

    # A custom factory that stores converters in a local registry.
    class CustomFactory
      @registry : Hash(String, Base.class)

      def initialize(seed_registry = nil)
        if sr = seed_registry
          @registry = {} of String => Base.class
          sr.each { |k, v| @registry[k] = v }
        else
          @registry = {} of String => Base.class
        end
      end

      # Lookup a converter by backend name.
      def converter_for(backend : String) : Base.class | Nil
        @registry[backend]?
      end

      # Get all registered converters.
      def converters : Hash(String, Base.class)
        @registry.dup
      end

      # Create a converter instance for the given backend.
      def create(backend : String, opts : Hash(String, String) = {} of String => String) : Base | Nil
        if (converter_class = converter_for(backend))
          converter_class.new(backend)
        else
          nil
        end
      end

      # Register a custom converter with this factory.
      def register(converter : Base.class, *backends : String) : Nil
        backends.each do |backend|
          @registry[backend] = converter
        end
      end

      # Unregister all Converter classes that are registered with this factory.
      def unregister_all : Nil
        @registry.clear
      end
    end
  end
end
