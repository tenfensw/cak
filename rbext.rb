# various standard Ruby class extensions

class Array
	def push_if_not_empty(*items)
		items.each do |a|
			self.push(a) if not a.empty?
		end
	end

	def push_if_not_duplicate(*items)
		items.each do |item|
			self.push(item) if not self.include? item
		end
	end

	def push_if_hash_is_not_there(item, param)
		if self.select {|s| s.is_a?(Hash) and s[param] == item[param] }.size < 1
			self.push(item)
		end
	end
end

class String
	BANNED_XNU_MACROS = [ 'API_DEPRECATED', 'API_DEPRECATED_WITH_REPLACEMENT',
			      'API_AVAILABLE', 'NS_FORMAT_FUNCTION',
			      'API_UNAVAILABLE', 'NS_SWIFT_NAME', 'NS_NOESCAPE' ]

	BANALIZE_MAP = { '\r' => '\n',
			 '\t' => ' ' }

	BRACKETS_TYPES = { '(' => :extension, ')' => :extension,
			   '<' => :protocols, '>' => :protocols,
			   ':' => :none, ' ' => :none }

	ENCLOSURE_TYPES = { '<' => '>',
			    '[' => ']' }


	def camelize
		return split(':').map { |e| "#{e.chars.first.upcase}#{e[1...]}" }.join
	end

	def remove_all_objc_enclosures
		inside_enclosure = []
		
		result = []

		chars.each do |c|
			if ENCLOSURE_TYPES.has_key? c
				inside_enclosure.push(c)
			elsif inside_enclosure.empty?
				result.push(c)
			elsif c == ENCLOSURE_TYPES[inside_enclosure.last]
				inside_enclosure.pop
			end
		end

		return result.join
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

