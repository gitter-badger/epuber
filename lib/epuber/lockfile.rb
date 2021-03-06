# encoding: utf-8

require 'yaml'


module Epuber
  class Lockfile
    attr_accessor :defined_from_file

    # @param [Hash] data
    #
    def initialize(data = {})
      @internal_data = data
    end

    # @return [self]
    #
    def self.from_file(file_path)
      if File.exists?(file_path)
        hash = YAML.load(File.read(file_path))
      else
        hash = {}
      end

      inst = self.new(hash)
      inst.defined_from_file = file_path
      inst
    end

    # @return nil
    #
    def write_to_file
      return if defined_from_file.nil?

      File.open(defined_from_file, 'w') do |f|
        f.write(YAML.dump(@internal_data))
      end
    end


    # @return [Epuber::Version]
    #
    def version
      @internal_data['version']
    end

    # @param [Epuber::Version] new_version
    #
    # @return [Epuber::Version]
    #
    def version=(new_version)
      @internal_data['version'] = new_version
    end
  end
end
