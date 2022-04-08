require_relative 'objcheaderparser'

require 'optparse'

module Cak
	CLI_OPTIONS = { :verbose => false,
			:framework_path => nil,
			:headers_processed => [],
			:output_metainfo => nil,
			:output_imp => nil,
			:oid_definition => true }

	ALLOW_PROPERTIES = false # experimental

	OBJC_IFACETYPE_BINDING = 'CakOID'
	OBJC_IFACETYPE_BINDING_REF = "#{OBJC_IFACETYPE_BINDING}Ref"
	OBJC_IFACETYPE_BINDING_ARGN = 'oidObjPInstance'
	OBJC_IFACETYPE_BINDING_PARAM = 'rth'
	
	OBJC_COMMON_TYPE_BINDINGS = { 'ObjectType' => 'void*',
				      'id' => OBJC_IFACETYPE_BINDING_REF,
				      'instancetype' => OBJC_IFACETYPE_BINDING_REF,
				      'BOOL' => 'bool', # stdbool.h
				      'SEL' => 'void*',
				      'IBAction' => 'void',
				      'Class' => 'void*',
				      'KeyType' => 'void*',
				      'ValueType' => 'void*',
				      'unichar' => 'uint16_t',
				      'UTF32Char' => 'uint32_t',
				      'UTF16Char' => 'uint16_t',
				      'UTF8Char' => 'uint8_t',
				      'CGFloat' => 'double',
				      # some common types
				      'NSInteger' => 'long',
				      'NSUInteger' => 'unsigned long',
				      'K' => 'void*',
				      # TODO: handle double ptrs correctly
				      # TODO 2: handle function ptr typedefs correctly
				      'NSError**' => 'void*',
				      'NSZone*' => 'void*',
				      'NSFastEnumerationState*' => 'void*',
				      'NSItemProviderLoadHandler' => 'void*',
				      'NSItemProviderCompletionHandler' => 'void*'
				    }

	OBJC_KEYWORD_BLACKLIST = [ '_Nonnull', '__unsafe_unretained', '_Nullable',
				   'nullable', 'inout', 'out', 'null_unspecified',
				   'nonnull' ]

	KNOWN_INTERFACES = {}

	# TODO: eliminate the need for this by improving the parser
	BLACKLISTED_METHOD_PARAMS = []
	BLACKLISTED_METHODS = []
	
	# turn it into a pure C type definition	
	def self.make_c_type(arg)
		# first remove all the <> and []s
		arg_mod = arg.remove_all_objc_enclosures

		result = []
		arg_mod.split(' ').each do |item|
			blacklisted = false
			OBJC_KEYWORD_BLACKLIST.each do |bl|
				if item.start_with? bl
					blacklisted = true
					break
				end
			end
		
			if not blacklisted
				trimmed = item[0...-1]
			
				if OBJC_COMMON_TYPE_BINDINGS.has_key? item
					result.push OBJC_COMMON_TYPE_BINDINGS[item]
				elsif KNOWN_INTERFACES.has_key? trimmed
					# replace with the OID wrapper
					result.push(OBJC_IFACETYPE_BINDING_REF)
				elsif item.chars.last == '*' and OBJC_COMMON_TYPE_BINDINGS.has_key? trimmed
					result.push(OBJC_COMMON_TYPE_BINDINGS[trimmed] + '*')
				else
					result.push(item)
				end
			end
		end

		return result.join(' ')
	end

	# converts preprocessed arguments into valid C ones
	def self.convert_to_c_args(method_meta)
		result = []

		# self-ref in case of a non-static method
		if not method_meta[:static]
			result.push({ :name => OBJC_IFACETYPE_BINDING_ARGN, :type => OBJC_IFACETYPE_BINDING_REF,
				      :c_pair => "#{OBJC_IFACETYPE_BINDING_REF} #{OBJC_IFACETYPE_BINDING_ARGN}" })
		end

		method_meta[:arguments].each do |arg_raw|
			# TODO: optimize
			arg = { :name => arg_raw[:name], :type => make_c_type(arg_raw[:type]),
				:c_pair => nil }

			arg[:c_pair] = "#{arg[:type]} #{arg[:name]}"

			if arg[:c_pair].include? '('
				# TODO: fix incorrect block handling the other way
				arg[:name] = arg[:name].chars.reject { |c| ['(', ')'].include? c }.join
				arg[:type] = 'void*'
				arg[:c_pair] = [ arg[:type], arg[:name] ].join(' ')
			end

			result.push(arg) if not arg.empty?
		end

		return result
	end

	# parses the method metadata hash from ObjCHeaderParser and turns it into a proper
	# C method more or less
	def self.make_c_method(iface_name, method_meta, semicolon_at_the_end=true)
		# result = { :static => (first_token == '+'),
		#            :arguments => [],
		#            :return_type => line.shift.no_ticks.strip,
		#            :combined_name => line.select { |e| e.chars.last == ':' }.join,
		#            :c_friendly_name => nil }

		nputs "converting #{method_meta}"
		result = make_c_type(method_meta[:return_type])
		result += ' ' + OBJC_IFACETYPE_BINDING + iface_name + method_meta[:c_friendly_name] + '('

		args_converted = convert_to_c_args(method_meta).map { |i| i[:c_pair] }

		# C99 compliance
		args_converted = ['void'] if args_converted.empty? and method_meta[:static]

		result += args_converted.join(', ') + ')'
		result += ';' if semicolon_at_the_end
		return result
	end

	# creates a proper C bindings
	def self.make_c_implementation(iface_name, method_meta)
		# first C-ify all the meta info
		args = convert_to_c_args method_meta
		heading = make_c_method(iface_name, method_meta, false)

		# prepare to map ObjC params <-> C ones
		params_mapped = method_meta[:combined_name].split(':')

		# additional checks like no NULL instance, etc
		fun_body = []
		fun_id_arg = (method_meta[:static] ? nil : args.shift[:name])
		fun_return_type = make_c_type(method_meta[:return_type])

		# whose method shall be called underneath
		fun_objectee = (method_meta[:static] ? iface_name : "(#{iface_name}*)(#{fun_id_arg}->#{OBJC_IFACETYPE_BINDING_PARAM})")

		if not method_meta[:static]
			# TODO: very absurd workaround, needs to be fixed ASAP
			fun_body.push("if (!#{fun_id_arg}) { return 0; }") if fun_return_type != 'NSRange'
		end
		
		fun_result = "[#{fun_objectee}"

		if not args.empty?
			count = -1 # for the mapped params
			args.each do |arg|
				count += 1
				matching_param = params_mapped[count]
	
				# merge param with casted arg name
				to_add = [ matching_param, arg[:name] ]

				if arg[:type] == OBJC_IFACETYPE_BINDING_REF
					# access the underlying ObjC class instance in this case
					to_add.pop
					to_add.push("(#{arg[:name]} ? #{arg[:name]}->#{OBJC_IFACETYPE_BINDING_PARAM} : nil)")
				end
				fun_result += ' ' + to_add.join(':')
			end
		else
			# just call the message instead
			fun_result += ' ' + method_meta[:combined_name]
			fun_result += 'nil' if fun_result.chars.last == ':'
		end

		fun_result += ']'

		# in this case, we need to wrap the thing around
		if fun_return_type == OBJC_IFACETYPE_BINDING_REF
			# TODO: refactor
			fun_body.push("void* #{OBJC_IFACETYPE_BINDING_PARAM}ToReturn = #{fun_result};")
			if not method_meta[:static]
				fun_body.push("if (#{OBJC_IFACETYPE_BINDING_PARAM}ToReturn == #{fun_id_arg}->#{OBJC_IFACETYPE_BINDING_PARAM}) {")
				fun_body.push("\treturn #{fun_id_arg};")
				fun_body.push("}")
			end
			fun_body.push("#{OBJC_IFACETYPE_BINDING_REF} #{OBJC_IFACETYPE_BINDING_PARAM}Wrapper = malloc(sizeof(struct #{OBJC_IFACETYPE_BINDING}));")
			fun_body.push("#{OBJC_IFACETYPE_BINDING_PARAM}Wrapper->#{OBJC_IFACETYPE_BINDING_PARAM} = #{OBJC_IFACETYPE_BINDING_PARAM}ToReturn;")
			fun_body.push("return #{OBJC_IFACETYPE_BINDING_PARAM}Wrapper;")
		else
			fun_body.push("return #{fun_result};")
		end

		result = "#{heading} {\n"
		result += fun_body.map { |i| "\t#{i}" }.join("\n")
		result += "\n}\n"
		return result
	end

	def self.sync_interface_base_methods
		KNOWN_INTERFACES.keys.each do |base|
			herritage = KNOWN_INTERFACES.keys.select { |k| (not KNOWN_INTERFACES[k].nil?) and KNOWN_INTERFACES[k][:base] == base }

			# only sync if the interface was defined in any of the headers
			if not KNOWN_INTERFACES[base].nil?
				herritage.each do |iface_name|
					KNOWN_INTERFACES[base][:methods].each do |mtd|
						KNOWN_INTERFACES[iface_name][:methods].push_if_hash_is_not_there(mtd, :combined_name)
					end
				end
			end
		end
	end

	# idk, fswr .merge! doesn't really replace all the nil items properly
	def self.properly_push_interfaces(ifaces)
		ifaces.each do |inn, inv|
			KNOWN_INTERFACES[inn] = inv if KNOWN_INTERFACES[inn].nil?
		end
	end

	def self.pretty_print_metainfo(info)
		result = []
		
		info.each do |iface_name, iface|
			title = "@interface " + iface_name
			if not iface.nil?
				title += " : #{iface[:base]}" if not iface[:base].nil?

				result.push(title)

				if not iface[:conforms_to].empty?
					result.push("\t<conforms to #{iface[:conforms_to].join(', ')}>")
				end

				iface[:methods].each do |mtd|
					prefix = mtd[:static] ? '+' : '-'
					result.push("\t" + prefix + ' (' + mtd[:return_type] + ')' + mtd[:c_friendly_name])
					result.push("\t" + mtd[:arguments].to_s)
				end
			else
				result.push(title)
				result.push("\t<referenced interface, definition unknown>")
			end
		end

		return result.join("\n")
	end

	def self.sync_interface_protocol_methods(known_protos)
		# TODO
	end

	def self.import_typedefs(typedefs)
		nputs "available typedefs to import: #{typedefs}"

		typedefs.each do |td|
			name = td[:name]
			replacement = make_c_type td[:replacement]

			nputs "typedef: #{name} = #{replacement}"
			OBJC_COMMON_TYPE_BINDINGS[name] = replacement if not OBJC_COMMON_TYPE_BINDINGS.has_key? name
		end
	end

	def self.main
		headers_path = File.join(CLI_OPTIONS[:framework_path], 'Headers')
		if not File.directory?(CLI_OPTIONS[:framework_path]) or not File.directory?(headers_path)
			raise("Not a valid framework path - #{headers_path}")
		end

		# first find out the FW name
		framework_name = File.basename(CLI_OPTIONS[:framework_path], '.*')

		if CLI_OPTIONS[:headers_processed].size < 1
			# by default we need the main FW header which is usually synonymous with its 
			# name
			CLI_OPTIONS[:headers_processed].push("#{framework_name}.h")
		end

		CLI_OPTIONS[:headers_processed].map! { |item| File.join(headers_path, item) }

		known_protos = []
		# C binding implementations
		implementations = []

		CLI_OPTIONS[:headers_processed].each do |pr|
			implementations.push("#import <#{framework_name}/#{File.basename pr}>")
		
			# use the parser
			hps = ObjCHeaderParser.new(pr)
			hps.load_imports
			properly_push_interfaces hps.interfaces

			known_protos.push(*hps.protocols)
			import_typedefs hps.typedefs
		end

		implementations.push("#include \"#{File.basename CLI_OPTIONS[:output_imp], '.*'}.h\"", "") if not CLI_OPTIONS[:output_imp].nil?
		implementations.push("#include <stdlib.h>")

		# now sync up so that all the interfaces would have protocol/base interface methods
		# for each other

		sync_interface_base_methods
		sync_interface_protocol_methods known_protos

		File.write(CLI_OPTIONS[:output_metainfo], pretty_print_metainfo(KNOWN_INTERFACES)) if not CLI_OPTIONS[:output_metainfo].nil?


		if CLI_OPTIONS[:oid_definition]
			# include all the headers & structure declaration
			puts "#pragma once\n"
			['arg', 'int', 'bool'].each do |fg|
				puts "#include <std#{fg}.h>"
			end
			puts "\n"
			
			puts "typedef struct #{OBJC_IFACETYPE_BINDING}* #{OBJC_IFACETYPE_BINDING_REF};\n"
		end

		implementations.push("struct #{OBJC_IFACETYPE_BINDING} { id #{OBJC_IFACETYPE_BINDING_PARAM}; };", "")
		#implementations += (KNOWN_INTERFACES.keys.map { |k| "@class #{k};" })

		KNOWN_INTERFACES.each do |iface_name, iface_vl|
			# some interfaces could be not defined yet
			if not iface_vl.nil?
				puts "//\n// #{iface_name}\n//\n"

				iface_vl[:methods].each do |mtd|
					banned = BLACKLISTED_METHODS.include?("#{iface_name}@#{mtd[:combined_name]}")

					# check if there aren't any blacklisted args
					BLACKLISTED_METHOD_PARAMS.each do |param|
						if mtd[:combined_name].downcase.include? param.downcase
							nputs "banned kw #{mtd[:combined_name]}, skipping"
							banned = true
							break
						end
					end
				
					if not banned
						puts make_c_method(iface_name, mtd)
						implementations.push make_c_implementation(iface_name, mtd)
					end
				end

				# also make these crucial bindings
				if not iface_vl[:methods].empty?
					['alloc', 'release', 'retain'].each do |subf|
						mtd_template = { :static => (subf == 'alloc'),
								 :arguments => [],
								 :c_friendly_name => subf.camelize,
								 :return_type => (subf == 'release') ? 'void' : 'id',
								 :combined_name => subf }

						puts make_c_method(iface_name, mtd_template)
						implementations.push make_c_implementation(iface_name, mtd_template)
					end
				end

				puts nil
			end
		end

		File.write(CLI_OPTIONS[:output_imp], implementations.join("\n")) if not CLI_OPTIONS[:output_imp].nil?
	end
end

if __FILE__ == $0
	OptionParser.new do |op|
		op.banner = "Usage: ruby #{__FILE__} [options]"

		op.on('-fFRAMEWORK', '--framework=FRAMEWORK', 'ObjC framework to make bindings for') do |fw|
			Cak::CLI_OPTIONS[:framework_path] = fw
		end
		
		op.on('-hHEADER', '--header=HEADER', 'Process specifically this header from the framework') do |hd|
			Cak::CLI_OPTIONS[:headers_processed].push_if_not_duplicate(hd)
		end

		op.on('--output-metainfo=PATH', 'Dump detected ObjC interface metainfo into a TXT file') do |pt|
			Cak::CLI_OPTIONS[:output_metainfo] = pt
		end

		op.on('--class=CLASSES', 'Predefine these ObjC interfaces as existing classes') do |pt|
			pt.split(',').each do |cl|
				Cak::KNOWN_INTERFACES[cl] = { :base => nil,
							 :conforms_to => [],
							 :methods => [],
							 :origin => '<CLI parameters>',
							 :type => :interface }
			end
		end

		op.on('--blacklist-methods=METHODS', 'Blacklist ObjC inferface methods matching these definitions') do |mtds|
			mtds.split(',').each do |mtd|
				raise("Method format for blacklisting: CLASS@METHOD") if not mtd.include? '@'
				Cak::BLACKLISTED_METHODS.push_if_not_duplicate(mtd)
			end 
		end

		op.on('--blacklist-arguments=ARGUMENTS', 'Blacklist ObjC interface methods that have these arguments (do not make bindings for them)') do |pt|
			pt.split(',').each do |nm|
				if nm.chars.last == ':'
					Cak::BLACKLISTED_METHOD_PARAMS.push(nm)
				else
					raise("--blacklist-arguments only accepts ObjC argument definitions (NAME:)")
				end
			end

			Cak.nputs Cak::BLACKLISTED_METHOD_PARAMS, "blacklisted"
		end

		op.on('--output-implementation=PATH', 'Generate implementation for the bindings into a C source file') do |pt|
			Cak::CLI_OPTIONS[:output_imp] = pt
		end

		op.on('--no-oid-definition', 'Do not include stdbool.h or define the ObjC wrapper ID structure') do
			Cak::CLI_OPTIONS[:oid_definition] = false
		end

		op.on('-v', '--verbose', 'Be verbose') do
			Cak::CLI_OPTIONS[:verbose] = true
		end

		op.on('-h', '--help', 'Prints this help message') do
			puts op
			exit 1
		end
	end.parse!

	raise(OptionParser::MissingArgument.new('-f')) if Cak::CLI_OPTIONS[:framework_path].nil?
	Cak.main
end
