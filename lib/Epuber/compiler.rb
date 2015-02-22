# encoding: utf-8

require 'bundler/setup'
Bundler.setup

require 'English'

require 'pathname'
require 'fileutils'

require 'stylus'
require 'bade'

require 'RMagick'

require_relative 'compiler/opf_generator'
require_relative 'compiler/nav_generator'
require_relative 'compiler/meta_inf_generator'

require_relative 'book'


module Epuber
  class Compiler
    EPUB_CONTENT_FOLDER = 'OEBPS'

    GROUP_EXTENSIONS = {
      text:  %w(.xhtml .html .md .bade .rxhtml),
      image: %w(.png .jpg .jpeg),
      font:  %w(.otf .ttf),
      style: %w(.css .styl),
    }.freeze

    STATIC_EXTENSIONS = %w(.xhtml .html .png .jpg .jpeg .otf .ttf .css).freeze

    EXTENSIONS_RENAME = {
      '.styl'   => '.css',

      '.bade'   => '.xhtml',
      '.rxhtml' => '.xhtml',
      '.md'     => '.xhtml',
    }.freeze

    # @return [Array<Epuber::Book::File>]
    #
    def spine
      @spine.dup
    end

    # @param book [Epuber::Book::Book]
    # @param target [Epuber::Book::Target]
    #
    def initialize(book, target)
      @book = book
      @target = target
      @spine = []
    end

    # Compile target to build folder
    #
    # @param build_folder [String] path to folder, where will be stored all compiled files
    #
    # @return [void]
    #
    def compile(build_folder, check: false)
      @all_files    = []
      @should_check = check

      FileUtils.mkdir_p(build_folder)

      @output_dir = File.expand_path(build_folder)

      puts "  handling target #{@target.name.inspect} in build dir `#{build_folder}`"

      process_toc_item(@target.root_toc)
      process_target_files
      generate_other_files

      # build folder cleanup
      remove_unnecessary_files
      remove_empty_folders
    end

    # Archives current target files to epub
    #
    # @param path [String] path to created archive
    #
    # @return [String] path
    #
    def archive(path = epub_name)
      epub_path = File.expand_path(path)

      Dir.chdir(@output_dir) do
        all_files = Dir.glob('**/*')

        run_command(%(zip -q0X "#{epub_path}" mimetype))
        run_command(%(zip -qXr9D "#{epub_path}" "#{all_files.join('" "')}" --exclude \\*.DS_Store))
      end

      path
    end

    # Creates name of epub file for current book and current target
    #
    # @return [String] name of result epub file
    #
    def epub_name
      epub_name = if !@book.output_base_name.nil?
                    @book.output_base_name
                  elsif @book.from_file?
                    File.basename(@book.file_path, File.extname(@book.file_path))
                  else
                    @book.title
                  end

      epub_name += @book.build_version.to_s unless @book.build_version.nil?
      epub_name += "-#{@target.name}" if @target != @book.default_target
      epub_name + '.epub'
    end


    private

    def remove_empty_folders
      Dir.chdir(@output_dir) do
        Dir.glob('**/*')
          .select { |d| File.directory?(d) }
          .select { |d| (Dir.entries(d) - %w(. ..)).empty? }
          .each do |d|
          puts "removing empty folder `#{d}`"
          Dir.rmdir(d)
        end
      end
    end

    def remove_unnecessary_files
      requested_paths = @all_files.map do |file|
        # files have paths from EPUB_CONTENT_FOLDER
        abs_path = File.expand_path(file.destination_path, File.join(@output_dir, EPUB_CONTENT_FOLDER))
        abs_path.sub(File.join(@output_dir, ''), '')
      end

      existing_paths = nil

      Dir.chdir(@output_dir) do
        existing_paths = Dir.glob('**/*')
      end

      unnecessary_paths = existing_paths - requested_paths

      # absolute path
      unnecessary_paths.map! do |path|
        File.join(@output_dir, path)
      end

      # remove directories
      unnecessary_paths.select! do |path|
        !File.directory?(path)
      end

      unnecessary_paths.each do |path|
        puts "removing unnecessary file: `#{path}`"
        File.delete(path)
      end
    end

    def generate_other_files
      # generate nav file (nav.xhtml or nav.ncx)
      nav_file = NavGenerator.new(@book, @target).generate_nav_file
      @target.add_to_all_files(nav_file)
      process_file(nav_file)

      # generate .opf file
      opf_file = OPFGenerator.new(@book, @target).generate_opf_file
      process_file(opf_file)

      # generate mimetype file
      mimetype_file                  = Epuber::Book::File.new(nil)
      mimetype_file.destination_path = '../mimetype'
      mimetype_file.content          = 'application/epub+zip'
      process_file(mimetype_file)

      # generate META-INF files
      opf_path = File.join(EPUB_CONTENT_FOLDER, opf_file.destination_path)
      meta_inf_files = MetaInfGenerator.new(@book, @target, opf_path).generate_all_files
      meta_inf_files.each do |meta_file|
        process_file(meta_file)
      end
    end

    def process_target_files
      @target.files
        .select { |file| !file.only_one }
        .each do |file|
        files = find_files(file).map { |path| Epuber::Book::File.new(path) }
        @target.replace_file_with_files(file, files)
      end

      @target.files.each { |file| process_file(file) }

      cover_image = @target.cover_image
      return if cover_image.nil?

      # resolve destination path
      destination_path_of_file(cover_image)

      index = @target.all_files.index(cover_image)
      if index.nil?
        @target.add_to_all_files(cover_image)
      else
        file = @target.all_files[index]
        file.merge_with(cover_image)
      end
    end

    # @param toc_item [Epuber::Book::TocItem]
    #
    def process_toc_item(toc_item)
      unless toc_item.file_obj.nil?
        file = toc_item.file_obj

        puts "    processing toc item #{file.source_path_pattern}"

        @target.add_to_all_files(file)
        @spine << file
        process_file(file)
      end

      # process recursively other files
      toc_item.child_items.each { |child| process_toc_item(child) }
    end

    # @param file [Epuber::Book::File]
    #
    def process_file(file)
      dest_path = destination_path_of_file(file)
      FileUtils.mkdir_p(File.dirname(dest_path))

      if !file.content.nil?
        from_source_and_old = !file.real_source_path.nil? && !FileUtils.uptodate?(dest_path, [file.real_source_path])
        if from_source_and_old
          # invalidate old content
          file.content = nil

          return process_file(file)
        end

        file_write(file)
      elsif !file.real_source_path.nil?
        file_source_path = file.real_source_path
        file_extname = File.extname(file_source_path)

        case file_extname
        when *GROUP_EXTENSIONS[:text]
          process_text_file(file)
        when *GROUP_EXTENSIONS[:image]
          process_image_file(file)
        when *STATIC_EXTENSIONS
          file_copy(file)
        when '.styl'
          file.content = Stylus.compile(::File.new(file_source_path))
          file_write(file)
        else
          raise "unknown file extension #{file_extname} for file #{file.inspect}"
        end
      else
        raise "don't know what to do with file #{file.inspect} at path #{file.real_source_path}"
      end

      @all_files << file
    end

    # @param file [Epuber::Book::File]
    #
    def process_text_file(file)
      source_path = file.real_source_path
      source_extname = File.extname(source_path)

      xhtml_content   = case source_extname
                        when '.xhtml'
                          ::File.read(source_path)
                        when '.rxhtml'
                          RubyTemplater.render_file(source_path)
                        when '.bade'
                          parsed = Bade::Parser.new(file: source_path).parse(::File.read(source_path))
                          lam    = Bade::RubyGenerator.node_to_lambda(parsed, new_line: '\n', indent: '  ')
                          lam.call
                        else
                          raise "Unknown text file extension #{source_extname}"
                        end

      # TODO: perform text transform
      # TODO: perform analysis

      file.content = xhtml_content
      file_write(file)
    end

    # @param file [Epuber::Book::File]
    #
    def process_image_file(file)
      dest_path = destination_path_of_file(file)
      source_path = file.real_source_path

      return if FileUtils.uptodate?(dest_path, [source_path])

      img = Magick::Image::read(source_path).first

      resolution = img.columns * img.rows
      max_resolution = 2_000_000
      if resolution > max_resolution
        scale = max_resolution.to_f / resolution.to_f
        puts "DEBUG: downscaling image #{source_path} with scale #{scale}"
        img.scale!(scale)
        img.write(dest_path)
      else
        file_copy(file)
      end
    end

    # @param file [Epuber::Book::File]
    #
    def file_write(file)
      dest_path = destination_path_of_file(file)

      original_content = if ::File.exists?(dest_path)
                           ::File.read(dest_path)
                         end

      return if original_content == file.content || original_content == file.content.to_s

      puts "DEBUG: writing to file #{dest_path}"

      ::File.open(dest_path, 'w') do |file_handle|
        file_handle.write(file.content)
      end
    end

    # @param file [Epuber::Book::File]
    #
    def file_copy(file)
      dest_path = destination_path_of_file(file)
      source_path = file.real_source_path

      return if FileUtils.uptodate?(dest_path, [source_path])
      return if File.exists?(dest_path) && FileUtils.compare_file(dest_path, source_path)

      puts "DEBUG: copying file from #{source_path} to #{dest_path}"
      FileUtils.cp(source_path, dest_path)
    end

    # @param file [Epuber::Book::File]
    # @return [String]
    #
    def destination_path_of_file(file)
      if file.destination_path.nil?
        real_source_path = find_file(file)

        extname = Pathname.new(real_source_path).extname
        new_extname = EXTENSIONS_RENAME[extname]

        dest_path = if new_extname.nil?
                      real_source_path
                    else
                      real_source_path.sub(/#{extname}$/, new_extname)
                    end

        file.destination_path = dest_path
        file.real_source_path = real_source_path

        File.join(@output_dir, EPUB_CONTENT_FOLDER, dest_path)
      else
        File.join(@output_dir, EPUB_CONTENT_FOLDER, file.destination_path)
      end
    end

    # @param pattern [String]
    # @param group [Symbol]
    # @return [Array<String>]
    #
    def file_paths_with_pattern(pattern, group = nil)
      file_paths = Dir.glob(pattern)

      file_paths.select! do |file_path|
        !file_path.include?(Config::WORKING_PATH)
      end

      # filter depend on group
      unless group.nil?
        file_paths.select! do |file_path|
          extname     = Pathname.new(file_path).extname
          group_array = GROUP_EXTENSIONS[group]

          raise "Uknown file group #{group.inspect}" if group_array.nil?

          group_array.include?(extname)
        end
      end

      file_paths
    end

    # @param file_or_pattern [String, Epuber::Book::File]
    # @return [String] only pattern
    #
    def pattern_from(file_or_pattern)
      if file_or_pattern.is_a?(Epuber::Book::File)
        file_or_pattern.source_path_pattern
      else
        file_or_pattern
      end
    end

    # @param file_or_pattern [String, Epuber::Book::File]
    # @param group [Symbol]
    # @return [Array<String>]
    #
    def find_files(file_or_pattern, group = nil)
      pattern = pattern_from(file_or_pattern)

      group = file_or_pattern.group if group.nil? && file_or_pattern.is_a?(Epuber::Book::File)

      file_paths = file_paths_with_pattern("**/#{pattern}", group)
      file_paths = file_paths_with_pattern("**/#{pattern}.*", group) if file_paths.empty?

      file_paths
    end

    # @param file_or_pattern [String, Epuber::Book::File]
    # @param group [Symbol]
    # @return [String]
    #
    def find_file(file_or_pattern, group = nil)
      pattern = pattern_from(file_or_pattern)
      file_paths = find_files(file_or_pattern, group)

      raise "not found file matching pattern `#{pattern}`" if file_paths.empty?
      raise "found too many files for pattern `#{pattern}`" if file_paths.count >= 2

      file_paths.first
    end

    # @param cmd [String]
    #
    # @return [void]
    #
    # @raise if the return value is not 0
    #
    def run_command(cmd)
      system(cmd)

      $stdout.flush
      $stderr.flush

      code = $CHILD_STATUS
      raise 'wrong return value' if code != 0
    end
  end
end
