require_relative 'objcheaderparser'

require 'optparse'
require 'json'

module Cak
	CLI_OPTIONS = { :verbose => false,
			:framework_path => nil,
			:headers_processed => [],
			:output_metainfo => nil }

	OBJC_IFACETYPE_BINDING = 'CakOID'

	KNOWN_INTERFACES = []
	
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
end
