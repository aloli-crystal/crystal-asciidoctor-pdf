module Asciidoctor
  # Extensions provide a way to participate in the parsing and converting
  # phases of the AsciiDoc processor or extend the AsciiDoc syntax.
  #
  # The various extensions participate in AsciiDoc processing as follows:
  #
  # 1. After the source lines are normalized, Preprocessors modify or replace
  #    the source lines before parsing begins. IncludeProcessors are used to
  #    process include directives for targets which they claim to handle.
  # 2. The Parser parses the block-level content into an abstract syntax tree.
  #    Custom blocks and block macros are processed by associated BlockProcessors
  #    and BlockMacroProcessors, respectively.
  # 3. TreeProcessors are run on the abstract syntax tree.
  # 4. Conversion of the document begins, at which point inline markup is processed
  #    and converted. Custom inline macros are processed by associated InlineMacroProcessors.
  # 5. Postprocessors modify or replace the converted document.
  # 6. The output is written to the output stream.
  #
  # Extensions may be registered globally using the Extensions.register method
  # or added to a custom Registry instance and passed as an option to a single
  # Asciidoctor processor.
  module Extensions
    # -------------------------------------------------------------------------
    # Processor — abstract base class for all extension processors
    # -------------------------------------------------------------------------

    # An abstract base class for document and syntax processors.
    #
    # Instances of the Processor class provide convenience methods for creating
    # AST nodes, such as Block and Inline, and for parsing child content.
    abstract class Processor
      # The configuration Hash for this processor instance.
      getter config : Hash(String, String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol)

      def initialize(config : Hash(String, String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol) = {} of String => String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol)
        @config = config
      end

      # Update the configuration of this processor.
      def update_config(config : Hash(String, String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol)) : Nil
        @config.merge!(config)
      end

      # Creates a new Block node and links it to the specified parent.
      def create_block(parent : AbstractBlock, context : Symbol, source : String | Array(String) | Nil, attrs : Hash(String, String), opts : Hash(String, String | Bool | Int32 | ContentModel) = {} of String => String | Bool | Int32 | ContentModel) : Block
        content_model_val = opts["content_model"]?.try { |v| v.as(ContentModel) }
        subs_val = nil
        lines = case source
                when String
                  [source]
                when Array(String)
                  source
                else
                  [] of String
                end
        Block.new(parent, context, content_model: content_model_val, source: lines, attributes: attrs, subs: subs_val)
      end

      # Creates an image block node and links it to the specified parent.
      def create_image_block(parent : AbstractBlock, attrs : Hash(String, String), opts : Hash(String, String | Bool | Int32 | ContentModel) = {} of String => String | Bool | Int32 | ContentModel) : Block
        target = attrs["target"]?
        raise ArgumentError.new("Unable to create an image block, target attribute is required") unless target
        attrs["alt"] ||= File.basename(target, File.extname(target)).tr("_-", " ")
        title = attrs.delete("title")
        block = create_block(parent, :image, nil, attrs, opts)
        if title
          block.title = title
        end
        block
      end

      # Creates an inline node and binds it to the specified parent.
      def create_inline(parent : AbstractBlock, context : Symbol, text : String?, opts : Hash(String, String | Symbol) = {} of String => String | Symbol) : Inline
        type_val = opts["type"]?.try { |v| v.as(Symbol) }
        target_val = opts["target"]?.try { |v| v.as(String) }
        id_val = opts["id"]?.try { |v| v.as(String) }
        Inline.new(parent, context, text, id: id_val, type: type_val, target: target_val)
      end

      # Creates a list node and links it to the specified parent.
      def create_list(parent : AbstractBlock, context : Symbol, attrs : Hash(String, String)? = nil) : List
        list = List.new(parent, context)
        list.update_attributes(attrs) if attrs
        list
      end

      # Creates a list item node and links it to the specified parent.
      def create_list_item(parent : AbstractBlock, text : String? = nil) : ListItem
        ListItem.new(parent, text)
      end

      # Creates a paragraph block.
      def create_paragraph(parent : AbstractBlock, source : String | Array(String), attrs : Hash(String, String)) : Block
        create_block(parent, :paragraph, source, attrs)
      end

      # Creates an open block.
      def create_open_block(parent : AbstractBlock, source : String | Array(String) | Nil, attrs : Hash(String, String)) : Block
        create_block(parent, :open, source, attrs)
      end

      # Creates an example block.
      def create_example_block(parent : AbstractBlock, source : String | Array(String) | Nil, attrs : Hash(String, String)) : Block
        create_block(parent, :example, source, attrs)
      end

      # Creates a pass block.
      def create_pass_block(parent : AbstractBlock, source : String | Array(String) | Nil, attrs : Hash(String, String), opts : Hash(String, String | Bool | Int32 | ContentModel) = {} of String => String | Bool | Int32 | ContentModel) : Block
        opts["content_model"] = ContentModel::Raw unless opts.has_key?("content_model")
        create_block(parent, :pass, source, attrs, opts)
      end

      # Creates a listing block.
      def create_listing_block(parent : AbstractBlock, source : String | Array(String) | Nil, attrs : Hash(String, String)) : Block
        create_block(parent, :listing, source, attrs)
      end

      # Creates a literal block.
      def create_literal_block(parent : AbstractBlock, source : String | Array(String) | Nil, attrs : Hash(String, String)) : Block
        create_block(parent, :literal, source, attrs)
      end

      # Creates a Section node.
      def create_section(parent : AbstractBlock, title : String, attrs : Hash(String, String), opts : Hash(Symbol, Int32 | Bool) = {} of Symbol => Int32 | Bool) : Section
        doc = parent.document
        level = opts[:level]?.try { |v| v.as(Int32) } || parent.level + 1
        numbered = opts[:numbered]?.try { |v| v.as(Bool) } || false
        sect = Section.new(doc, parent, level, numbered)
        sect.title = title
        if (id = attrs["id"]?)
          sect.id = id
        end
        sect.update_attributes(attrs)
        sect
      end

      # Creates an anchor inline node.
      def create_anchor(parent : AbstractBlock, text : String?, opts : Hash(String, String | Symbol) = {} of String => String | Symbol) : Inline
        create_inline(parent, :anchor, text, opts)
      end

      # Creates an inline pass node.
      def create_inline_pass(parent : AbstractBlock, text : String?, opts : Hash(String, String | Symbol) = {} of String => String | Symbol) : Inline
        create_inline(parent, :quoted, text, opts)
      end

      # Parses blocks in the content and attaches them to the parent.
      def parse_content(parent : AbstractBlock, content : String | Array(String)) : AbstractBlock
        lines = content.is_a?(String) ? content.split('\n') : content
        reader = Reader.new(lines)
        Parser.parse_blocks(reader, parent)
        parent
      end
    end

    # -------------------------------------------------------------------------
    # Extension & ProcessorExtension — proxy wrappers
    # -------------------------------------------------------------------------

    # A proxy object for an extension implementation such as a processor.
    # It allows the preparation of the extension instance to be separated from
    # its usage to provide consistency between different interfaces.
    class Extension
      getter kind : Symbol
      getter config : Hash(String, String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol)
      getter instance : Processor

      def initialize(@kind : Symbol, @instance : Processor, @config : Hash(String, String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol))
      end
    end

    # A specialization of the Extension proxy that additionally stores a
    # reference to the process method.
    class ProcessorExtension < Extension
      def initialize(kind : Symbol, instance : Processor)
        super(kind, instance, instance.config)
      end
    end

    # -------------------------------------------------------------------------
    # Group — for grouping extensions
    # -------------------------------------------------------------------------

    # A Group is used to register one or more extensions with the Registry.
    #
    # The Group should be subclassed and registered with the Registry either by
    # invoking the Group.register method or passing the subclass to the
    # Extensions.register method.
    abstract class Group
      # Register this group globally.
      def self.register(name : Symbol? = nil) : Nil
        Extensions.register(name, self)
      end

      # Activate this group by registering extensions with the given registry.
      abstract def activate(registry : Registry) : Nil
    end

    # -------------------------------------------------------------------------
    # Preprocessor — modifies source lines before parsing
    # -------------------------------------------------------------------------

    # Preprocessors are run after the source text is split into lines and
    # normalized, but before parsing begins.
    abstract class Preprocessor < Processor
      abstract def process(document : Document, reader : Reader) : Reader?
    end

    # -------------------------------------------------------------------------
    # TreeProcessor — modifies the AST after parsing
    # -------------------------------------------------------------------------

    # TreeProcessors are run on the Document after the source has been
    # parsed into an abstract syntax tree (AST).
    abstract class TreeProcessor < Processor
      abstract def process(document : Document) : Document?
    end

    # -------------------------------------------------------------------------
    # Postprocessor — modifies the converted output
    # -------------------------------------------------------------------------

    # Postprocessors are run after the document is converted, but before
    # it is written to the output stream.
    abstract class Postprocessor < Processor
      abstract def process(document : Document, output : String) : String
    end

    # -------------------------------------------------------------------------
    # IncludeProcessor — handles custom include directives
    # -------------------------------------------------------------------------

    # IncludeProcessors are used to process include::<target>[] directives
    # in the source document.
    abstract class IncludeProcessor < Processor
      abstract def process(document : Document, reader : Reader, target : String, attributes : Hash(String, String)) : Nil

      # Determine whether this processor handles the given target.
      # Override in subclasses to restrict which targets this processor handles.
      def handles?(target : String) : Bool
        true
      end
    end

    # -------------------------------------------------------------------------
    # DocinfoProcessor — injects content into head/footer HTML
    # -------------------------------------------------------------------------

    # DocinfoProcessors are used to add additional content to the header
    # and/or footer of the generated document.
    abstract class DocinfoProcessor < Processor
      def initialize(config : Hash(String, String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol) = {} of String => String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol)
        super(config)
        @config["location"] = :head unless @config.has_key?("location")
      end

      abstract def process(document : Document) : String

      # Get the location where this docinfo content should be placed.
      def location : Symbol
        @config["location"].as(Symbol)
      end
    end

    # -------------------------------------------------------------------------
    # BlockProcessor — processes custom delimited blocks and paragraphs
    # -------------------------------------------------------------------------

    # BlockProcessors are used to handle delimited blocks and paragraphs
    # that have a custom name.
    #
    # NOTE: In Crystal, the `name` property uses String instead of Symbol
    # because Crystal symbols are compile-time constants and cannot be created
    # dynamically from runtime strings (unlike Ruby symbols).
    abstract class BlockProcessor < Processor
      property name : String?

      def initialize(name : String? = nil, config : Hash(String, String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol) = {} of String => String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol)
        super(config)
        @name = name || @config["name"]?.try { |v| v.as(String) }
        unless @config.has_key?("contexts")
          @config["contexts"] = Set{:open, :paragraph}
        end
        @config["content_model"] = :compound unless @config.has_key?("content_model")
      end

      abstract def process(parent : AbstractBlock, reader : Reader, attributes : Hash(String, String)) : AbstractBlock?

      # Get the contexts on which this block processor can be used.
      def contexts : Set(Symbol)
        @config["contexts"].as(Set(Symbol))
      end
    end

    # -------------------------------------------------------------------------
    # MacroProcessor — base class for macro processors
    # -------------------------------------------------------------------------

    # MacroProcessor is the base class for block and inline macro processors.
    #
    # NOTE: In Crystal, the `name` property uses String instead of Symbol
    # because Crystal symbols are compile-time constants and cannot be created
    # dynamically from runtime strings (unlike Ruby symbols).
    abstract class MacroProcessor < Processor
      property name : String?

      def initialize(name : String? = nil, config : Hash(String, String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol) = {} of String => String | Bool | Int32 | Array(String) | Set(Symbol) | Symbol)
        super(config)
        @name = name || @config["name"]?.try { |v| v.as(String) }
        @config["content_model"] = :attributes unless @config.has_key?("content_model")
      end

      abstract def process(parent : AbstractBlock, target : String, attributes : Hash(String, String)) : AbstractBlock | Inline | Nil
    end

    # -------------------------------------------------------------------------
    # BlockMacroProcessor — processes custom block macros
    # -------------------------------------------------------------------------

    # BlockMacroProcessors are used to handle block macros that have a
    # custom name.
    class BlockMacroProcessor < MacroProcessor
      def name : String?
        if (n = @name)
          unless MacroNameRx.matches?(n)
            raise ArgumentError.new("invalid name for block macro: #{n}")
          end
        end
        @name
      end

      def process(parent : AbstractBlock, target : String, attributes : Hash(String, String)) : AbstractBlock | Inline | Nil
        raise NotImplementedError.new("#{self.class} must implement the #process method")
      end
    end

    # -------------------------------------------------------------------------
    # InlineMacroProcessor — processes custom inline macros
    # -------------------------------------------------------------------------

    # InlineMacroProcessors are used to handle inline macros that have a
    # custom name.
    class InlineMacroProcessor < MacroProcessor
      @@rx_cache = {} of Tuple(String, Symbol?) => Regex

      # Lookup the regexp for this inline macro, resolving it first if necessary.
      def regexp : Regex
        resolve_regexp(@name.not_nil!, @config["format"]?.try { |v| v.as(Symbol) })
      end

      # Resolve the regexp for the given name and format.
      def resolve_regexp(name : String, format : Symbol? = nil) : Regex
        unless MacroNameRx.matches?(name)
          raise ArgumentError.new("invalid name for inline macro: #{name}")
        end
        key = {name, format}
        @@rx_cache[key] ||= if format == :short
                               /\\?#{Regex.escape(name)}:(){0}\[(|.*?[^\\])\]/
                             else
                               /\\?#{Regex.escape(name)}:(\S+?)\[(|.*?[^\\])\]/
                             end
      end

      def process(parent : AbstractBlock, target : String, attributes : Hash(String, String)) : AbstractBlock | Inline | Nil
        raise NotImplementedError.new("#{self.class} must implement the #process method")
      end
    end

    # -------------------------------------------------------------------------
    # Registry — the central registry where extensions are registered
    # -------------------------------------------------------------------------

    # The primary entry point into the extension system.
    #
    # Registry holds the extensions which have been registered and activated,
    # has methods for registering a processor and looks up extensions stored
    # in the registry during parsing.
    #
    # NOTE: In Crystal, the block/macro extension hashes use String keys
    # instead of Symbol keys because Crystal symbols are compile-time constants
    # and cannot be created dynamically from runtime strings.
    class Registry
      # The Document on which the extensions in this registry are being used.
      getter document : Document?

      # The Hash of Group classes or instances that have been registered.
      getter groups : Hash(Symbol, Group.class | Group)

      # Extension stores for each processor type.
      getter preprocessor_extensions : Array(ProcessorExtension)?
      getter tree_processor_extensions : Array(ProcessorExtension)?
      getter postprocessor_extensions : Array(ProcessorExtension)?
      getter include_processor_extensions : Array(ProcessorExtension)?
      getter docinfo_processor_extensions : Array(ProcessorExtension)?
      getter block_extensions : Hash(String, ProcessorExtension)?
      getter block_macro_extensions : Hash(String, ProcessorExtension)?
      getter inline_macro_extensions : Hash(String, ProcessorExtension)?

      def initialize(groups : Hash(Symbol, Group.class | Group) = {} of Symbol => Group.class | Group)
        @groups = groups
        reset
      end

      # Activate all the global extension Groups and the extension Groups
      # associated with this registry.
      def activate(document : Document) : self
        reset if @document
        @document = document
        all_groups = Extensions.groups.values + @groups.values
        unless all_groups.empty?
          all_groups.each do |group|
            case group
            when Group.class
              group.new.activate(self)
            when Group
              group.activate(self)
            end
          end
        end
        self
      end

      # ----- Registration methods (sorted alphabetically) -----

      # Register a BlockProcessor.
      def block(processor : BlockProcessor, name : String? = nil) : ProcessorExtension
        name = name || processor.name
        raise ArgumentError.new("No name specified for block extension: #{processor.class}") unless name
        processor.name = name
        store = @block_extensions ||= {} of String => ProcessorExtension
        ext = ProcessorExtension.new(:block, processor)
        store[name] = ext
        ext
      end

      # Register a BlockMacroProcessor.
      def block_macro(processor : BlockMacroProcessor, name : String? = nil) : ProcessorExtension
        name = name || processor.name
        raise ArgumentError.new("No name specified for block macro extension: #{processor.class}") unless name
        processor.name = name
        store = @block_macro_extensions ||= {} of String => ProcessorExtension
        ext = ProcessorExtension.new(:block_macro, processor)
        store[name] = ext
        ext
      end

      # Register a DocinfoProcessor.
      def docinfo_processor(processor : DocinfoProcessor) : ProcessorExtension
        store = @docinfo_processor_extensions ||= [] of ProcessorExtension
        ext = ProcessorExtension.new(:docinfo_processor, processor)
        if processor.config["position"]? == :>>
          store.unshift(ext)
        else
          store << ext
        end
        ext
      end

      # Register an IncludeProcessor.
      def include_processor(processor : IncludeProcessor) : ProcessorExtension
        store = @include_processor_extensions ||= [] of ProcessorExtension
        ext = ProcessorExtension.new(:include_processor, processor)
        if processor.config["position"]? == :>>
          store.unshift(ext)
        else
          store << ext
        end
        ext
      end

      # Register an InlineMacroProcessor.
      def inline_macro(processor : InlineMacroProcessor, name : String? = nil) : ProcessorExtension
        name = name || processor.name
        raise ArgumentError.new("No name specified for inline macro extension: #{processor.class}") unless name
        processor.name = name
        store = @inline_macro_extensions ||= {} of String => ProcessorExtension
        ext = ProcessorExtension.new(:inline_macro, processor)
        store[name] = ext
        ext
      end

      # Register a Postprocessor.
      def postprocessor(processor : Postprocessor) : ProcessorExtension
        store = @postprocessor_extensions ||= [] of ProcessorExtension
        ext = ProcessorExtension.new(:postprocessor, processor)
        if processor.config["position"]? == :>>
          store.unshift(ext)
        else
          store << ext
        end
        ext
      end

      # Register a Preprocessor.
      def preprocessor(processor : Preprocessor) : ProcessorExtension
        store = @preprocessor_extensions ||= [] of ProcessorExtension
        ext = ProcessorExtension.new(:preprocessor, processor)
        if processor.config["position"]? == :>>
          store.unshift(ext)
        else
          store << ext
        end
        ext
      end

      # Register a TreeProcessor.
      def tree_processor(processor : TreeProcessor) : ProcessorExtension
        store = @tree_processor_extensions ||= [] of ProcessorExtension
        ext = ProcessorExtension.new(:tree_processor, processor)
        if processor.config["position"]? == :>>
          store.unshift(ext)
        else
          store << ext
        end
        ext
      end

      # ----- Query methods (sorted alphabetically) -----

      # Check whether any BlockProcessor extensions have been registered.
      def blocks? : Bool
        !@block_extensions.nil?
      end

      # Check whether any BlockMacroProcessor extensions have been registered.
      def block_macros? : Bool
        !@block_macro_extensions.nil?
      end

      # Check whether any DocinfoProcessor extensions have been registered.
      def docinfo_processors?(location : Symbol? = nil) : Bool
        if (exts = @docinfo_processor_extensions)
          if location
            exts.any? { |ext| ext.instance.as(DocinfoProcessor).location == location }
          else
            true
          end
        else
          false
        end
      end

      # Retrieve DocinfoProcessor extensions, optionally filtered by location.
      def docinfo_processors(location : Symbol? = nil) : Array(ProcessorExtension)
        if (exts = @docinfo_processor_extensions)
          if location
            exts.select { |ext| ext.instance.as(DocinfoProcessor).location == location }
          else
            exts
          end
        else
          [] of ProcessorExtension
        end
      end

      # Check whether any IncludeProcessor extensions have been registered.
      def include_processors? : Bool
        !@include_processor_extensions.nil?
      end

      # Retrieve IncludeProcessor extensions.
      def include_processors : Array(ProcessorExtension)
        @include_processor_extensions || [] of ProcessorExtension
      end

      # Check whether any InlineMacroProcessor extensions have been registered.
      def inline_macros? : Bool
        !@inline_macro_extensions.nil?
      end

      # Retrieve all InlineMacroProcessor extensions.
      def inline_macros : Array(ProcessorExtension)
        (@inline_macro_extensions || {} of String => ProcessorExtension).values
      end

      # Check whether any Postprocessor extensions have been registered.
      def postprocessors? : Bool
        !@postprocessor_extensions.nil?
      end

      # Retrieve Postprocessor extensions.
      def postprocessors : Array(ProcessorExtension)
        @postprocessor_extensions || [] of ProcessorExtension
      end

      # Check whether any Preprocessor extensions have been registered.
      def preprocessors? : Bool
        !@preprocessor_extensions.nil?
      end

      # Retrieve Preprocessor extensions.
      def preprocessors : Array(ProcessorExtension)
        @preprocessor_extensions || [] of ProcessorExtension
      end

      # Check whether any TreeProcessor extensions have been registered.
      def tree_processors? : Bool
        !@tree_processor_extensions.nil?
      end

      # Retrieve TreeProcessor extensions.
      def tree_processors : Array(ProcessorExtension)
        @tree_processor_extensions || [] of ProcessorExtension
      end

      # ----- Lookup methods (sorted alphabetically) -----

      # Find a BlockProcessor extension by name.
      def find_block_extension(name : String) : ProcessorExtension?
        @block_extensions.try(&.[name]?)
      end

      # Find a BlockMacroProcessor extension by name.
      def find_block_macro_extension(name : String) : ProcessorExtension?
        @block_macro_extensions.try(&.[name]?)
      end

      # Find an InlineMacroProcessor extension by name.
      def find_inline_macro_extension(name : String) : ProcessorExtension?
        @inline_macro_extensions.try(&.[name]?)
      end

      # Check whether a BlockProcessor is registered for the given name and context.
      def registered_for_block?(name : String, context : Symbol) : ProcessorExtension | Bool
        if (ext = @block_extensions.try(&.[name]?))
          if ext.instance.as(BlockProcessor).contexts.includes?(context)
            ext
          else
            false
          end
        else
          false
        end
      end

      # Check whether a BlockMacroProcessor is registered for the given name.
      def registered_for_block_macro?(name : String) : ProcessorExtension | Bool
        @block_macro_extensions.try(&.[name]?) || false
      end

      # Check whether an InlineMacroProcessor is registered for the given name.
      def registered_for_inline_macro?(name : String) : ProcessorExtension | Bool
        @inline_macro_extensions.try(&.[name]?) || false
      end

      # Reset all extension stores.
      private def reset : Nil
        @preprocessor_extensions = nil
        @tree_processor_extensions = nil
        @postprocessor_extensions = nil
        @include_processor_extensions = nil
        @docinfo_processor_extensions = nil
        @block_extensions = nil
        @block_macro_extensions = nil
        @inline_macro_extensions = nil
        @document = nil
      end
    end

    # -------------------------------------------------------------------------
    # Module-level methods for global registration
    # -------------------------------------------------------------------------

    @@groups = {} of Symbol => Group.class | Group
    @@auto_id = -1

    # Get all globally registered extension groups.
    def self.groups : Hash(Symbol, Group.class | Group)
      @@groups
    end

    # Create a new Registry, optionally with a block-based group.
    def self.create(name : Symbol? = nil) : Registry
      Registry.new
    end

    # Generate a unique name for an extension group.
    def self.generate_name : Symbol
      @@auto_id += 1
      :"extgrp#{@@auto_id}"
    end

    # Register an extension Group globally.
    #
    # The group can be a Group subclass or an instance of a Group subclass.
    def self.register(name : Symbol?, group : Group.class) : Nil
      actual_name = name || generate_name
      @@groups[actual_name] = group
    end

    # Register an extension Group instance globally.
    def self.register(name : Symbol?, group : Group) : Nil
      actual_name = name || generate_name
      @@groups[actual_name] = group
    end

    # Unregister all statically-registered extension groups.
    def self.unregister_all : Nil
      @@groups = {} of Symbol => Group.class | Group
    end

    # Unregister statically-registered extension groups by name.
    def self.unregister(*names : Symbol) : Nil
      names.each { |name| @@groups.delete(name) }
    end
  end
end
