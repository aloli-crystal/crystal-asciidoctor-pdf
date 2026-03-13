module Asciidoctor
  # Maintains a catalog of callouts and their associations.
  class Callouts
    @lists : Array(Array(NamedTuple(ordinal: Int32, id: String)))
    @list_index : Int32
    @co_index : Int32

    def initialize
      @lists = [] of Array(NamedTuple(ordinal: Int32, id: String))
      @list_index = 0
      @co_index = 1
      next_list
    end

    # Get a space-separated list of callout ids for the specified list item.
    def callout_ids(li_ordinal : Int32) : String
      current_list
        .select { |item| item[:ordinal] == li_ordinal }
        .map { |item| item[:id] }
        .join(' ')
    end

    # The current list for which callouts are being collected.
    def current_list : Array(NamedTuple(ordinal: Int32, id: String))
      @lists[@list_index - 1]
    end

    # Advance to the next callout list in the document.
    def next_list : Nil
      @list_index += 1
      if @lists.size < @list_index
        @lists << [] of NamedTuple(ordinal: Int32, id: String)
      end
      @co_index = 1
    end

    # Get the next callout index in the document.
    # Returns the unique String id of the next callout in the document.
    def read_next_id : String?
      list = current_list
      id = if @co_index <= list.size
             list[@co_index - 1][:id]
           else
             nil
           end
      @co_index += 1
      id
    end

    # Register a new callout for the given list item ordinal.
    # Returns the unique String id of this callout.
    def register(li_ordinal : Int32) : String
      id = generate_next_callout_id
      current_list << {ordinal: li_ordinal, id: id}
      @co_index += 1
      id
    end

    # Rewind the list index pointer (switching from parsing to conversion phase).
    def rewind : Nil
      @list_index = 1
      @co_index = 1
    end

    private def generate_callout_id(list_index : Int32, co_index : Int32) : String
      "CO#{list_index}-#{co_index}"
    end

    private def generate_next_callout_id : String
      generate_callout_id(@list_index, @co_index)
    end
  end
end
