class Array
	BANNED_XNU_MACROS = [ 'API_DEPRECATED', 'API_DEPRECATED_WITH_REPLACEMENT',
			      'API_AVAILABLE' ]

	def push_if_not_empty(*items)
		items.each do |a|
			self.push(a) if not a.empty?
		end
	end

	# remove XNU Availability.h macros
	def remove_xnu_macros
		result = self
		
		BANNED_XNU_MACROS.each do |mc|
			index = result.index(mc)

			if (not index.nil?) and (index + 1) < result.size
				# remove the mention of the macros
				result.delete_at index + 1
				result.delete_at index
			end
		end

		return result
	end
end

class String
	BANALIZE_MAP = { '\r' => '\n',
			 '\t' => ' ' }

	BRACKETS_TYPES = { '(' => :extension, ')' => :extension,
			   '<' => :protocols, '>' => :protocols,
			   ':' => :none, ' ' => :none }


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

	# removes <> and "" from header includes
	def no_ticks
		characters = chars
		endings = [characters.shift, characters.pop]

		return characters.join if ['""', '<>'].include? endings.join
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
		# interfaces and their methods
		attr_reader :interfaces
	
		def initialize(path)
			@path = path
			@metainfo = []
			@interfaces = {}
			scan
		end

		def inspect
			return [@path, "Metainfo:", @metainfo, "Interfaces:", @interfaces].join("\n")
		end

		def to_s
			return inspect
		end

		private
		def scan
			raise("File not found - #{@path}") if not File.exist? @path

			# first read in the file properly
			contents_raw = File.read(@path).no_comments.simplify_parse
			contents = contents_raw.split("\n")

			current_interface_name = nil

			contents.each do |line_raw|
				if not line_raw.start_with? '//'
					line = line_raw.strip.tokenize_objc.remove_xnu_macros
					puts line.inspect
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
						if first_token == '@interface'
							puts("warning! weird collision, new iface block (#{line}) when #{current_interface_name} is unfinished yet") if not current_interface_name.nil?
	
							iface_def = { :type => :interface,
								      :base => nil,
								      :conforms_to => [],
								      :static_methods => [],
								      :methods => []
								    }
 
							# we are inside the interface block
							current_interface_name = line.shift
	
							if line.first == ':'
								basis = line.shift(2).last
								iface_def[:base] = basis
							end

							if not @interfaces.has_key? current_interface_name
								@interfaces[current_interface_name] = iface_def
							end
						elsif first_token == '@end'
							puts("warning! @end specified when not in block") if current_interface_name.nil?
							current_interface_name = nil
						end
					end
				end
			end
		end
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
		puts parser
	end
end

Cak.main if __FILE__ == $0
