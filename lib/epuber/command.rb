# encoding: utf-8

require 'claide'

module Epuber
  class PlainInformative < StandardError
    include CLAide::InformativeError

    def message
      "[!] #{super}".ansi.red
    end
  end

  class Command < CLAide::Command
    require_relative 'command/build'
    require_relative 'command/compile'
    require_relative 'command/init'
    require_relative 'command/server'

    self.abstract_command = true
    self.command = 'epuber'
    self.version = VERSION
    self.description = 'Epuber, easy creating and maintaining e-book.'
    self.plugin_prefixes = plugin_prefixes + %w(epuber)

    def self.run(argv = [])
      begin
        UI.current_command = self
        super
        UI.current_command = nil

      rescue Interrupt
        UI.error('[!] Cancelled')
      rescue => e
        UI.error!(e)

        UI.current_command = nil
      end
    end

    def validate!
      super
      UI.current_command = self
    end

    def run
      UI.current_command = self
    end

    protected

    # @return [Epuber::Book::Book]
    #
    def book
      Config.instance.bookspec
    end

    # @return [void]
    #
    # @raise PlainInformative if no .bookspec file don't exists or there are too many
    #
    def verify_one_bookspec_exists!
      bookspec_files = Config.instance.find_all_bookspecs
      raise PlainInformative, "No `.bookspec' found in the project directory." if bookspec_files.empty?
      raise PlainInformative, "Multiple `.bookspec' found in current directory" if bookspec_files.count > 1
    end

    def write_lockfile
      unless Epuber::Config.test?
        Epuber::Config.instance.save_lockfile
      end
    end
  end
end
