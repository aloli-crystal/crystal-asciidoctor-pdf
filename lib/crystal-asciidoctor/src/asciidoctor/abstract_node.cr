require "./logging"

module Asciidoctor
  # An abstract base class that provides state and methods for managing a
  # node of AsciiDoc content. The state and methods on this class are common to
  # all content segments in an AsciiDoc document.
  abstract class AbstractNode
    include Logging

    # The Hash of attributes for this node.
    getter attributes : Hash(String, String)

    # The Symbol context for this node.
    getter context : Symbol

    # The String id of this node.
    property id : String?

    # The String name of this node.
    getter node_name : String

    # The parent AbstractNode of this node.
    property parent : AbstractNode?

    abstract def block? : Bool
    abstract def inline? : Bool
    abstract def document : Document

    def initialize(@context : Symbol, attributes : Hash(String, String) = {} of String => String)
      @attributes = attributes.dup
      @node_name = @context.to_s
      @parent = nil
    end

    # Adds the given role directly to this node.
    def add_role(name : String) : Bool
      if val = @attributes["role"]?
        if " #{val} ".includes?(" #{name} ")
          false
        else
          @attributes["role"] = "#{val} #{name}"
          true
        end
      else
        @attributes["role"] = name
        true
      end
    end

    # Get the value of the specified attribute.
    # If the attribute is not found on this node, fallback_name is set,
    # and this node is not the Document node, get the value from the Document node.
    def attr(name : String, default_value : String? = nil, fallback_name : String | Bool | Nil = nil) : String?
      # Positional attributes (numeric keys like "1", "2") are not accessible via attr()
      return default_value if name =~ /^\d+$/
      @attributes[name]? || begin
        if fallback_name
          lookup = fallback_name.is_a?(Bool) ? name : fallback_name.as(String)
          document.attributes[lookup]? || default_value
        else
          default_value
        end
      end
    end

    # Check if the specified attribute is defined, optionally performing a
    # comparison with the expected value.
    def attr?(name : String, expected_value : String? = nil, fallback_name : String | Bool | Nil = nil) : Bool
      # Positional attributes (numeric keys like "1", "2") are not accessible via attr?()
      return false if name =~ /^\d+$/
      if expected_value
        expected_value == (@attributes[name]? || begin
          if fallback_name
            lookup = fallback_name.is_a?(Bool) ? name : fallback_name.as(String)
            document.attributes[lookup]?
          end
        end)
      else
        @attributes.has_key?(name) || begin
          if fallback_name
            lookup = fallback_name.is_a?(Bool) ? name : fallback_name.as(String)
            document.attributes.has_key?(lookup)
          else
            false
          end
        end
      end
    end

    # Get the Converter instance associated with this node.
    def converter : Converter::Base?
      document.converter
    end

    # Retrieve the Set of option names that are enabled on this node.
    def enabled_options : Set(String)
      result = Set(String).new
      @attributes.each_key do |k|
        if k.ends_with?("-option")
          result << k[0...(k.size - 7)]
        end
      end
      result
    end

    # Checks if the specified role is present in the list of roles for this node.
    def has_role?(name : String) : Bool
      if val = @attributes["role"]?
        " #{val} ".includes?(" #{name} ")
      else
        false
      end
    end

    # Construct a URI reference to the target icon.
    def icon_uri(name : String) : String
      if (icon_dir = @attributes["iconsdir"]?) || (icon_dir = document.attributes["iconsdir"]?)
        icon_type = @attributes["icontype"]? || document.attributes["icontype"]? || "png"
        normalize_web_path("#{name}.#{icon_type}", icon_dir)
      else
        icon_type = @attributes["icontype"]? || document.attributes["icontype"]? || "png"
        normalize_web_path("#{name}.#{icon_type}", "./images/icons")
      end
    end

    # Construct a URI reference to the target image.
    def image_uri(target_image : String, asset_dir_key : String = "imagesdir") : String
      if is_uri?(target_image)
        target_image
      elsif (dir = @attributes[asset_dir_key]?) || (dir = document.attributes[asset_dir_key]?)
        normalize_web_path(target_image, dir)
      else
        normalize_web_path(target_image)
      end
    end

    # Check if the specified string is a URI by checking for a URI scheme.
    def is_uri?(str : String) : Bool
      str.matches?(/\A[a-zA-Z][a-zA-Z0-9.+-]*:\/\//)
    end

    # Construct a URI reference to the target media.
    def media_uri(target : String, asset_dir_key : String = "imagesdir") : String
      image_uri(target, asset_dir_key)
    end

    # Resolve and normalize a system path from the target and start paths.
    def normalize_system_path(target : String, start : String? = nil, jail : String? = nil) : String
      raw = if target.starts_with?('/')
        target
      elsif start
        File.join(start, target)
      else
        File.join(document.base_dir, target)
      end
      # Normalize the path to resolve .. and . components
      Path.new(raw).normalize.to_s
    end

    # Resolve and normalize a web path from the target and start paths.
    def normalize_web_path(target : String, start : String? = nil) : String
      if is_uri?(target) || target.starts_with?('/')
        target
      elsif start && !start.empty?
        "#{start}/#{target}"
      else
        target
      end
    end

    # Check if the specified option attribute is enabled on the current node.
    def option?(name : String) : Bool
      @attributes.has_key?("#{name}-option")
    end

    # A convenience method that checks if the reftext attribute is defined.
    def reftext? : Bool
      @attributes.has_key?("reftext")
    end

    # A convenience method that returns the value of the reftext attribute.
    def reftext : String?
      @attributes["reftext"]?
    end

    # Remove the attribute from the current node.
    def remove_attr(name : String) : String?
      @attributes.delete(name)
    end

    # Removes the given role directly from this node.
    def remove_role(name : String) : Bool
      if val = @attributes["role"]?
        arr = val.split
        if arr.delete(name)
          if arr.empty?
            @attributes.delete("role")
          else
            @attributes["role"] = arr.join(' ')
          end
          true
        else
          false
        end
      else
        false
      end
    end

    # Retrieves the space-separated String role for this node.
    def role : String?
      @attributes["role"]?
    end

    # Sets the value of the role attribute on this node.
    def role=(names : String | Array(String))
      @attributes["role"] = names.is_a?(Array) ? names.join(' ') : names
    end

    # Checks if the role attribute is set on this node and, if an expected value
    # is given, whether the space-separated role matches that value.
    def role?(expected_value : String? = nil) : Bool
      if expected_value
        expected_value == @attributes["role"]?
      else
        @attributes.has_key?("role")
      end
    end

    # Retrieves the String role names for this node as an Array.
    def roles : Array(String)
      if val = @attributes["role"]?
        val.split
      else
        [] of String
      end
    end

    # Assign the value to the attribute name for the current node.
    def set_attr(name : String, value : String = "", overwrite : Bool = true) : Bool
      if !overwrite && @attributes.has_key?(name)
        false
      else
        @attributes[name] = value
        true
      end
    end

    # Set the specified option on this node.
    def set_option(name : String) : Nil
      @attributes["#{name}-option"] = ""
    end

    # Update the attributes of this node with the new values.
    def update_attributes(new_attributes : Hash(String, String)) : Hash(String, String)
      @attributes.merge!(new_attributes)
    end
  end
end
