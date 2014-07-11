require_relative 'dsl/dsl_object'

require_relative 'book/vendor/contributor'
require_relative 'target'
require_relative 'toc_item'


module Epuber

	class StandardError < ::StandardError; end

	class Book < DSLObject

		def initialize
			super

			@default_target = Target.new(nil)
			@root_toc = TocItem.new

			yield self if block_given?

			# convert attributes to corresponding classes
			__finish_parsing
		end


		def self.from_string(string, file_path = nil)
			if file_path
				eval(string, nil, file_path)
			else
				eval(string)
			end
		end



		private

		def __finish_parsing
			if self.author
				self.author = Contributor.from_ruby(self.author, 'aut')
			end
		end

		# Defines setter and getter for default target attribute
		#
		# @param [Symbol] sym  attribute name
		#
		# @return [Void]
		#
		def self.default_target_attribute(sym, readonly: false)

			# getter
			define_method(sym) do
				@default_target.send(sym)
			end

			unless readonly
				# setter
				setter_method = sym.to_s + '='
				define_method(setter_method) do |newValue|
					@default_target.send(setter_method, newValue)
				end
			end
		end

		#-------------- Targets ----------------------------------
		public

		# All targets
		#
		# @return [Array<Target>]
		#
		def targets
			if @default_target.sub_targets.length == 0
				[ @default_target ]
			else
				@default_target.sub_targets
			end
		end

		# Defines new target
		#
		# @return [Target] result target
		#
		def target(name)
			@default_target.sub_target(name) do |target|
				yield target if block_given?
			end
		end

		# @return [TocItem]
		#
		attr_reader :root_toc

		def toc(&block)
			@root_toc.create_child_items(&block)
		end

		#------------- DSL attributes ----------------------------------------------------------------------------------

		# @return [String] title of book
		#
		attribute :title,
				  :required => true

		# @return [String] subtitle of book
		#
		attribute :subtitle

		# @return [Array{Contributor}] authors of book
		#
		attribute :authors,
				  :types       => [ Contributor, NormalContributor ],
				  :container   => Array,
				  :required    => true,
				  :singularize => true


		# @return [String] publisher name
		#
		attribute :publisher

		# @return [String] language of this book
		#
		attribute :language

		# @return [String] isbn of this book
		#
		default_target_attribute :isbn

		# @return [String] isbn of printed book
		#
		attribute :print_isbn


		# TODO toc
		# TODO landmarks
		# TODO cover page
		# TODO other files
		# TODO footnotes customization
		# TODO custom metadata
		# TODO build version
		# TODO version
		# TODO custom user informations (just global available Hash<String, Any>)
		# TODO url (book url) // http://melvil.cz/kniha-prace-na-dalku
	end
end
