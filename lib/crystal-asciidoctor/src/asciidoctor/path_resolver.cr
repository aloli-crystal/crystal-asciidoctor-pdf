require "log"

module Asciidoctor
  # Public: Handles all operations for resolving, cleaning and joining paths.
  # This class includes operations for handling both web paths (request URIs) and
  # system paths.
  #
  # The main emphasis of the class is on creating clean and secure paths. Clean
  # paths are void of duplicate parent and current directory references in the
  # path name. Secure paths are paths which are restricted from accessing
  # directories outside of a jail path, if specified.
  #
  # Since joining two paths can result in an insecure path, this class also
  # handles the task of joining a parent (start) and child (target) path.
  class PathResolver
    include Logging

    DOT       = "."
    DOT_DOT   = ".."
    DOT_SLASH = "./"
    SLASH     = "/"
    BACKSLASH = "\\"
    DOUBLE_SLASH = "//"

    WindowsRootRx = /^(?:[a-zA-Z]:)?[\\\/]/

    property file_separator : String
    property working_dir : String

    # Cache for partition_path results
    @_partition_path_sys = {} of String => Tuple(Array(String), String?)
    @_partition_path_web = {} of String => Tuple(Array(String), String?)

    def initialize(file_separator : String? = nil, working_dir : String? = nil)
      @file_separator = file_separator || File::SEPARATOR.to_s
      if wd = working_dir
        @working_dir = root?(wd) ? posixify(wd) : File.expand_path(wd)
      else
        @working_dir = Dir.current
      end
    end

    # Public: Check whether the specified path is an absolute path.
    def absolute_path?(path : String) : Bool
      path.starts_with?(SLASH) || (@file_separator == BACKSLASH && !!(WindowsRootRx.match(path)))
    end

    # Public: Determine whether path descends from base.
    # Returns the offset if it descends, otherwise nil.
    def descends_from?(path : String, base : String) : Int32?
      if base == path
        0
      elsif base == SLASH
        path.starts_with?(SLASH) ? 1 : nil
      else
        path.starts_with?(base + SLASH) ? (base.size + 1) : nil
      end
    end

    # Public: Expand the specified path by resolving parent references (..)
    # and removing self references (.).
    def expand_path(path : String) : String
      path_segments, path_root = partition_path(path)
      if path.includes?(DOT_DOT)
        resolved_segments = [] of String
        path_segments.each do |segment|
          if segment == DOT_DOT
            resolved_segments.pop? || nil
          else
            resolved_segments << segment
          end
        end
        join_path(resolved_segments, path_root)
      else
        join_path(path_segments, path_root)
      end
    end

    # Public: Join the segments using the posix file separator.
    def join_path(segments : Array(String), root : String? = nil) : String
      root ? "#{root}#{segments.join(SLASH)}" : segments.join(SLASH)
    end

    # Public: Partition the path into path segments and remove self references (.)
    # and the trailing slash, if present.
    def partition_path(path : String, web : Bool = false) : Tuple(Array(String), String?)
      cache = web ? @_partition_path_web : @_partition_path_sys
      if (result = cache[path]?)
        return result
      end

      posix_path = posixify(path)
      root : String? = nil

      if web
        if web_root?(posix_path)
          root = SLASH
        elsif posix_path.starts_with?(DOT_SLASH)
          root = DOT_SLASH
        end
      elsif root?(posix_path)
        if unc?(posix_path)
          root = DOUBLE_SLASH
        elsif posix_path.starts_with?(SLASH)
          root = SLASH
        else
          idx = posix_path.index(SLASH)
          root = idx ? posix_path[0..idx] : posix_path
        end
      elsif posix_path.starts_with?(DOT_SLASH)
        root = DOT_SLASH
      end

      remainder = root ? posix_path[root.size..] : posix_path
      path_segments = remainder.split(SLASH)
      path_segments.reject! { |s| s.empty? || s == DOT }

      result = {path_segments, root}
      cache[path] = result
      result
    end

    # Public: Normalize path by converting any backslashes to forward slashes.
    def posixify(path : String?) : String
      return "" if path.nil?
      if @file_separator == BACKSLASH && path.includes?(BACKSLASH)
        path.tr(BACKSLASH, SLASH)
      else
        path
      end
    end

    # Public: Calculate the relative path to this absolute path from the
    # specified base directory.
    def relative_path(path : String, base : String) : String
      if root?(path)
        if (offset = descends_from?(path, base))
          path[offset..]
        else
          begin
            Path.new(path).relative_to(Path.new(base)).to_s
          rescue
            path
          end
        end
      else
        path
      end
    end

    # Public: Check if the specified path is an absolute root path.
    # In Crystal, we don't have Opal or JRuby, so root? is the same as absolute_path?.
    def root?(path : String) : Bool
      absolute_path?(path)
    end

    # Public: Securely resolve a system path.
    def system_path(target : String?, start : String? = nil, jail : String? = nil, opts = {} of Symbol => String | Bool) : String
      recover = opts.fetch(:recover, true)
      target_name = opts.fetch(:target_name, "path")

      jail_str : String? = nil
      if j = jail
        raise SecurityError.new("Jail is not an absolute path: #{j}") unless root?(j)
        jail_str = posixify(j)
      end

      target_segments : Array(String)? = nil
      jail_segments : Array(String)? = nil
      jail_root : String? = nil

      if t = target
        if root?(t)
          target_path = expand_path(t)
          if jail_str && !descends_from?(target_path, jail_str)
            unless recover
              raise SecurityError.new("#{target_name} #{t} is outside of jail: #{jail_str} (disallowed in safe mode)")
            end
            logger.warn { "#{target_name} is outside of jail; recovering automatically" }
            t_segs, _ = partition_path(target_path)
            j_segs, j_root = partition_path(jail_str)
            jail_segments = j_segs
            jail_root = j_root
            return join_path(j_segs + t_segs, j_root)
          end
          return target_path
        else
          target_segments, _ = partition_path(t)
        end
      else
        target_segments = [] of String
      end

      start_str = start

      if target_segments.empty?
        if start_str.nil? || start_str.empty?
          return jail_str || @working_dir
        elsif root?(start_str)
          return expand_path(start_str) unless jail_str
          start_str = posixify(start_str)
        else
          target_segments, _ = partition_path(start_str)
          start_str = jail_str || @working_dir
        end
      elsif start_str.nil? || start_str.empty?
        start_str = jail_str || @working_dir
      elsif root?(start_str)
        start_str = posixify(start_str) if jail_str
      else
        start_str = "#{(jail_str || @working_dir).chomp("/")}/#{start_str}"
      end

      recheck = false
      start_segments : Array(String)? = nil

      if jail_str
        if !(descends_from?(start_str, jail_str))
          recheck = true
          if @file_separator == BACKSLASH
            s_segs, s_root = partition_path(start_str)
            j_segs, j_root = partition_path(jail_str)
            jail_segments = j_segs
            jail_root = j_root
            unless s_root == j_root
              unless recover
                raise SecurityError.new("start path for #{target_name} #{start_str} refers to location outside jail root: #{jail_str} (disallowed in safe mode)")
              end
              logger.warn { "start path for #{target_name} is outside of jail root; recovering automatically" }
              start_segments = j_segs
              recheck = false
            else
              start_segments = s_segs
            end
          end
        end
      end

      if start_segments.nil?
        start_segments, jail_root = partition_path(start_str)
      end

      resolved_segments = start_segments + target_segments

      if resolved_segments.includes?(DOT_DOT)
        unresolved_segments = resolved_segments
        resolved_segments = [] of String
        if jail_str
          jail_segments = partition_path(jail_str)[0] if jail_segments.nil?
          warned = false
          unresolved_segments.each do |segment|
            if segment == DOT_DOT
              if resolved_segments.size > jail_segments.not_nil!.size
                resolved_segments.pop
              elsif recover
                unless warned
                  logger.warn { "#{target_name} has illegal reference to ancestor of jail; recovering automatically" }
                  warned = true
                end
              else
                raise SecurityError.new("#{target_name} #{target} refers to location outside jail: #{jail_str} (disallowed in safe mode)")
              end
            else
              resolved_segments << segment
            end
          end
        else
          unresolved_segments.each do |segment|
            if segment == DOT_DOT
              resolved_segments.pop?
            else
              resolved_segments << segment
            end
          end
        end
      end

      if recheck
        target_path = join_path(resolved_segments, jail_root)
        if descends_from?(target_path, jail_str.not_nil!)
          target_path
        elsif recover
          logger.warn { "#{target_name} is outside of jail; recovering automatically" }
          jail_segments = partition_path(jail_str.not_nil!)[0] if jail_segments.nil?
          join_path(jail_segments.not_nil! + target_segments, jail_root)
        else
          raise SecurityError.new("#{target_name} #{target} is outside of jail: #{jail_str} (disallowed in safe mode)")
        end
      else
        join_path(resolved_segments, jail_root)
      end
    end

    # Public: Determine if the path is a UNC (root) path.
    def unc?(path : String) : Bool
      path.starts_with?(DOUBLE_SLASH)
    end

    # Public: Resolve a web path from the target and start paths.
    def web_path(target : String?, start : String? = nil) : String
      target = posixify(target)
      start = posixify(start)

      uri_prefix : String? = nil

      unless start.empty? || web_root?(target)
        combined = "#{start}#{start.ends_with?(SLASH) ? "" : SLASH}#{target}"
        target, uri_prefix = extract_uri_prefix(combined)
      end

      target_segments, target_root = partition_path(target, web: true)
      resolved_segments = [] of String
      target_segments.each do |segment|
        if segment == DOT_DOT
          if resolved_segments.empty?
            resolved_segments << segment unless target_root && target_root != DOT_SLASH
          elsif resolved_segments[-1] == DOT_DOT
            resolved_segments << segment
          else
            resolved_segments.pop
          end
        else
          resolved_segments << segment
        end
      end

      resolved_path = join_path(resolved_segments, target_root)
      if resolved_path.includes?(" ")
        resolved_path = resolved_path.gsub(" ", "%20")
      end

      uri_prefix ? "#{uri_prefix}#{resolved_path}" : resolved_path
    end

    # Public: Determine if the path is an absolute (root) web path.
    def web_root?(path : String) : Bool
      path.starts_with?(SLASH)
    end

    private def extract_uri_prefix(str : String) : Tuple(String, String?)
      if str.includes?(':') && (m = UriSniffRx.match(str))
        prefix = m[0]
        {str[prefix.size..], prefix}
      else
        {str, nil}
      end
    end
  end
end
