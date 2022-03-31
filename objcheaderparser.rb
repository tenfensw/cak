require_relative 'rbext'

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
				elsif not argument.nil?
					if [ item.chars.first, item.chars.last ].join == '()'
						argument[:type] = item.no_ticks.strip
					else
						argument[:name] = item

						# add the argument
						result[:arguments].push(argument)
						argument = nil
					end
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
								      :methods => [],
								      :origin => path
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
		STDERR.puts(everything.join(' ')) if CLI_OPTIONS[:verbose]
	end
end

