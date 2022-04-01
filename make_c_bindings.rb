require_relative 'objcheaderparser'

require 'optparse'
require 'json'

module Cak
	CLI_OPTIONS = { :verbose => false,
			:framework_path => nil,
			:headers_processed => [],
			:output_metainfo => nil }

	OBJC_IFACETYPE_BINDING = 'CakOID'

	KNOWN_INTERFACES = {}
	
	# turn it into a pure C type definition	
	def self.make_c_type(arg)
		
	end

	# parses the method metadata hash from ObjCHeaderParser and turns it into a proper
	# C method more or less
	def self.make_c_method(iface_name, method_meta)
		# result = { :static => (first_token == '+'),
		#            :arguments => [],
		#            :return_type => line.shift.no_ticks.strip,
		#            :combined_name => line.select { |e| e.chars.last == ':' }.join,
		#            :c_friendly_name => nil }

		
	end

	def self.sync_interface_base_methods
		KNOWN_INTERFACES.keys.each do |base|
			herritage = KNOWN_INTERFACES.keys.select { |k| KNOWN_INTERFACES[k][:base] == base }

			herritage.each do |iface_name|
				KNOWN_INTERFACES[base][:methods].each do |mtd|
					KNOWN_INTERFACES[iface_name][:methods].push_if_not_duplicate_map_param(mtd, :combined_name)
				end
			end
		end
	end

	def self.pretty_print_metainfo(info)
		result = []
		
		info.each do |iface_name, iface|
			title = "@interface " + iface_name
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
		end

		return result.join("\n")
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
			CLI_OPTIONS[:headers_processed].push(File.join(headers_path, "#{framework_name}.h"))
		end

		known_protos = []

		CLI_OPTIONS[:headers_processed].each do |pr|
			# use the parser
			hps = ObjCHeaderParser.new(pr)
			hps.load_imports
			KNOWN_INTERFACES.merge! hps.interfaces
			known_protos.push(*hps.protocols)
		end

		# now sync up so that all the interfaces would have protocol/base interface methods
		# for each other

		sync_interface_base_methods

		File.write(CLI_OPTIONS[:output_metainfo], pretty_print_metainfo(KNOWN_INTERFACES)) if not CLI_OPTIONS[:output_metainfo].nil?
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

		op.on('--output-metainfo=PATH', 'Dump detected ObjC interface metainfo into a JSON file') do |pt|
			Cak::CLI_OPTIONS[:output_metainfo] = pt
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
