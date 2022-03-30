require 'json'

class Array
	def push_if_not_empty(*items)
		items.each do |a|
			self.push(a) if not a.empty?
		end
	end
end

class String
	BANNED_XNU_MACROS = [ 'API_DEPRECATED', 'API_DEPRECATED_WITH_REPLACEMENT',
			      'API_AVAILABLE', 'NS_FORMAT_FUNCTION',
			      'API_UNAVAILABLE' ]

	BANALIZE_MAP = { '\r' => '\n',
			 '\t' => ' ' }

	BRACKETS_TYPES = { '(' => :extension, ')' => :extension,
			   '<' => :protocols, '>' => :protocols,
			   ':' => :none, ' ' => :none }


	def camelize
		return split(':').map { |e| "#{e.chars.first.upcase}#{e[1...]}" }.join
	end

	# yep, it's literally just a thing that trims the semicolon at the end
	def remove_semicolon
		if chars.last == ';'
			return self[0...-1]
		else
			return self
		end
	end

	# remove all Availability.h XNU macros
	def remove_xnu_macros
		result = self
	
		BANNED_XNU_MACROS.each do |mc|
			if result.include? mc
				Cak.nputs "has #{mc}"
				found_occurence = result.index(mc)
				end_of_occurence = found_occurence + result[found_occurence...].index('(').to_i + 1

				# find the actual ending bracket
				brackets_count = 1
				while brackets_count > 0
					end_of_occurence += 1

					case result[end_of_occurence]
					when '('
						brackets_count += 1
					when ')'
						brackets_count -= 1
					when nil
						brackets_count = 0 # for some buggy old non-MRI Rubies
						break
					end
				end

				result = result[0...found_occurence] + result[end_of_occurence + 1...].to_s
			end
		end

		return result
	end

	# remove C '//' comments
	def remove_inline_comments
		# TODO: make it ignore double quotes (rare occurence tho)

		found_ones = self.index('//')
		if not found_ones.nil?
			return self[0...found_ones]
		else
			return self
		end
	end

	def banalize
		# doesn't work for non-chars
		return(self) if self.size < 2
		return BANALIZE_MAP.has_key?(self) ? BANALIZE_MAP[self] : self
	end

	def is_space?
		# there is a built-in method for this, but i forgot its name for now
		# and can't find it :P
		return [' ', '\t'].include? self
	end

	# removes <> and "" from header includes (as well as round brackets from ObjC return type defs)
	def no_ticks
		characters = chars
		endings = [characters.shift, characters.pop]

		return characters.join if ['""', '<>', '()'].include? endings.join
		return self
	end

	# removes multiline C comments (also gets rid of Windows CR-LF)
	def no_comments
		# TODO: optimize if possible
		characters = chars
		previous = nil
		inside_comment = false
		result = []

		characters.each do |c|
			if inside_comment and c == '/' and previous == '*'
				# no longer a comment
				inside_comment = false
			elsif not inside_comment
				if c == '*' and previous == '/'
					# remove the slash from the resulting string first
					result.pop

					inside_comment = true
				else
					result.push(c.banalize)
				end
			end
		
			previous = c
		end

		return result.join
	end

	# splits an ObjC definition line into tokens
	def tokenize_objc
		characters = chars
		
		token = []
		result = []
		inside_brackets = :none

		characters.each do |c|
			token.push(c)

			# TODO: optimize somehow
			case c
			when '<', '(', ' ', ':'
				if inside_brackets == :none
					inside_brackets = BRACKETS_TYPES[c]

					token.pop if c != ':'
					result.push_if_not_empty(token.join)
					token = if inside_brackets == :none # ' ' or ':'
							[]
						else
							[c]
						end
				end
			when '>', ')'				
				if inside_brackets == BRACKETS_TYPES[c]
					result.push(token.join)
					token = []

					inside_brackets = :none
				end
			end
		end

		result.push_if_not_empty(token.join)
		return result
	end

	# removes duplicate spaces + formats C pointers in a more comfy way
	def simplify_parse
		characters = chars
		result = []

		# TODO: optimize and simplify
		characters.each do |c|
			if c.is_space?
				result.push(c) if not result.last.to_s.is_space?
			elsif c == '*' and result.last.to_s.is_space?
				# pointer rearrange
				result.pop
				result.push(c)
				result.push(' ')
			else
				result.push(c)
			end
		end

		return result.join
	end
end

module Cak
	# mini ObjC preprocessor to extract data from Cocoa fw headers
	class ObjCHeaderParser
		# all the neat non-interface info parsed out from the header (includes, etc)
		attr_reader :metainfo
	
		def initialize(path)
			@path = path
			@metainfo = []
			@interfaces = {}
			scan(@path)
		end

		def inspect
			return [@path, "Metainfo:", @metainfo, "Interfaces:", interfaces,
				"Protocols:", protocols].join("\n")
		end

		def to_s
			return inspect
		end

		# interfaces and their methods
		def interfaces
			return filter_ifaces(:interface)
		end
		
		def protocols
			return filter_ifaces(:protocol)
		end

		def everything
			return @interfaces
		end

		# load all potential relative headers
		def load_imports
			own_dirname = File.absolute_path(File.dirname(@path))
		
			@metainfo.select {|e| e[:type] == :import }.each do |imp|
				bn = File.basename(imp[:path])
				potentials = [ File.join(own_dirname, bn),
					       File.join(own_dirname, imp[:path]) ]
				Cak.nputs "attempt to load #{potentials}"

				potentials.each do |fn|
					scan(fn) if File.exist? fn
				end
			end

			# avoid recursion
			@metainfo.reject! {|e| e[:type] == :import }
		end

		private
		def filter_ifaces(typesym)
			return @interfaces.select do |kv, vv|
				vv[:type] == typesym
			end
		end
		
		def make_method_schema(first_token, line)
			result = { :static => (first_token == '+'),
				   :arguments => [],
				   :return_type => line.shift.no_ticks.strip,
				   :combined_name => line.select { |e| e.chars.last == ':' }.join,
				   :c_friendly_name => nil }

			# for non-argumented methods
			if result[:combined_name].empty?
				result[:combined_name] = line.first
			end
			
			# make C-friendly name for prefixing and wrapping
			result[:c_friendly_name] = result[:combined_name].camelize

			argument = nil

			line.each do |item|
				if item.chars.last == ':'
					argument = { :name => item[0...-1],
						     :type => "void" }
				elsif [ item.chars.first, item.chars.last ].join == '()'
					argument[:type] = item.no_ticks.strip
				elsif not argument.nil?
					argument[:name] = item

					# add the argument
					result[:arguments].push(argument)
					argument = nil
				end
			end
			
			return result			
		end
		
		def scan(path)
			raise("File not found - #{path}") if not File.exist? path

			# first read in the file properly
			contents_raw = File.read(path).no_comments.simplify_parse
			contents = contents_raw.split("\n")

			current_interface_name = nil

			contents.each do |line_raw|
				if not line_raw.start_with? '//'
					line_mod = line_raw.remove_xnu_macros.remove_inline_comments.strip
					line = line_mod.remove_semicolon.tokenize_objc
					Cak.nputs line_raw
					Cak.nputs line.inspect
					first_token = line.shift.to_s
	
					case first_token.chars.first
					when '#'
						# preprocessor macro
						if ['#import', '#include'].include? first_token
							@metainfo.push({ :type => :import,
									 :path => line.join(' ').no_ticks })
						end
					when '@'
						# ObjC preprocessor block

						# TODO: remake into case-when
						if ['@interface', '@protocol'].include? first_token
							Cak.nputs("warning! weird collision, new #{first_token} block (#{line}) when #{current_interface_name} is unfinished yet") if not current_interface_name.nil?

							iface_type = if first_token == '@protocol'
									:protocol
								     else
								     	:interface
								     end
							iface_def = { :type => iface_type,
								      :base => nil,
								      :conforms_to => [],
								      :methods => []
								    }
 
							# we are inside the interface block
							current_interface_name = line.shift
	
							if line.first == ':' and iface_type == :interface
								basis = line.shift(2).last
								iface_def[:base] = basis
							end

							if [line.last.to_s.chars.first, line.last.to_s.chars.last].join == '<>'
								# protocol conforms
								iface_def[:conforms_to] = line.last.no_ticks.gsub(' ', '').split(',')
							end

							if not @interfaces.has_key? current_interface_name
								@interfaces[current_interface_name] = iface_def
							end
						elsif first_token == '@end'
							Cak.nputs("warning! @end specified when not in block") if current_interface_name.nil?
							current_interface_name = nil
						end
					when '+', '-'
						# it's a method
						raise("Method outside of interface scope, probably a parser error") if current_interface_name.nil?

						method_schema = make_method_schema first_token, line
						@interfaces[current_interface_name][:methods].push(method_schema)
					end
				end
			end
		end
	end

	def self.nputs(*everything)
		STDERR.puts everything.join(' ')
	end

	def self.usage
		puts "Usage: ruby #{__FILE__} /path/to/Headers/Header.h"
		exit 1
	end

	# main entrypoint when ran as standalone script
	def self.main
		header_path = ARGV.first
		usage if header_path.nil?

		parser = ObjCHeaderParser.new(header_path)
		parser.load_imports
		puts JSON.pretty_generate(parser.everything)
	end
end

Cak.main if __FILE__ == $0
