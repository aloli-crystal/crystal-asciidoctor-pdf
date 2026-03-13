require "./abstract_block"

module Asciidoctor
  # Methods for managing AsciiDoc content blocks.
  #
  # Examples
  #
  #   block = Asciidoctor::Block.new(parent, :paragraph, source: "_This_ is a <test>")
  #   block.content
  #   # => "<em>This</em> is a &lt;test&gt;"
  class Block < AbstractBlock
    DEFAULT_CONTENT_MODEL = {
      :audio          => ContentModel::Empty,
      :image          => ContentModel::Empty,
      :listing        => ContentModel::Verbatim,
      :literal        => ContentModel::Verbatim,
      :open           => ContentModel::Compound,
      :page_break     => ContentModel::Empty,
      :pass           => ContentModel::Raw,
      :stem           => ContentModel::Raw,
      :thematic_break => ContentModel::Empty,
      :video          => ContentModel::Empty,
    }

    # The original Array content for this block.
    property lines : Array(String)

    # The parent block.
    getter parent_block : AbstractBlock

    # The document this block belongs to.
    @document : Document

    def initialize(@parent_block : AbstractBlock, @context : Symbol,
                   content_model : ContentModel? = nil,
                   source : String | Array(String) | Nil = nil,
                   attributes : Hash(String, String) = {} of String => String,
                   subs : Substitution? = nil)
      super(@context, attributes)
      @document = @parent_block.document
      @content_model = content_model || DEFAULT_CONTENT_MODEL[@context]? || ContentModel::Simple
      @level = @parent_block.level
      @parent = @parent_block

      if subs
        @subs = subs
      end

      @lines = case source
               when nil
                 [] of String
               when String
                 source.split('\n')
               when Array(String)
                 source.dup
               else
                 [] of String
               end
    end

    # Get the converted result of the child blocks by converting the
    # children appropriate to content model that this block supports.
    def content : String?
      case @content_model
      when ContentModel::Compound
        @blocks.map { |b| b.convert }.join('\n')
      when ContentModel::Simple
        text = @lines.join('\n')
        subs_list.empty? ? text : apply_subs(text, subs_list)
      when ContentModel::Verbatim, ContentModel::Raw
        result = @lines.dup
        joined = if result.size < 2
          result.first? || ""
        else
          while (first = result.first?) && first.strip.empty?
            result.shift
          end
          while (last = result.last?) && last.strip.empty?
            result.pop
          end
          result.join('\n')
        end
        effective_subs = if !subs_list.empty?
          subs_list
        elsif @context == :verse
          [:specialcharacters, :quotes, :attributes, :replacements, :macros, :post_replacements] of Symbol
        else
          [:specialcharacters, :callouts] of Symbol
        end
        effective_subs.empty? ? joined : apply_subs(joined, effective_subs)
      when ContentModel::Empty
        nil
      else
        nil
      end
    end

    def document : Document
      @document
    end

    # Returns the preprocessed source of this block.
    def source : String
      @lines.join('\n')
    end

    def to_s(io : IO) : Nil
      content_summary = @content_model == ContentModel::Compound ? "blocks: #{@blocks.size}" : "lines: #{@lines.size}"
      io << "#<" << self.class.name << " {context: " << @context << ", content_model: " << @content_model << ", style: " << @style.inspect << ", " << content_summary << "}>"
    end
  end
end
