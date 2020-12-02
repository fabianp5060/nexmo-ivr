#!/usr/bin/env ruby
#
STDOUT.sync = true

require 'securerandom'
require 'dm-core'
require 'dm-migrations'
require 'logger'
require 'sinatra'
require 'vonage'
require 'aws-sdk-s3'
require 'aws-sdk-dynamodb'
require_relative 'src/aws_dynamo'
require_relative 'src/nexmoController'
require_relative 'src/nexmoNCCO'
require_relative 'src/nexmoIVRRoutes'
require_relative 'src/appRoutes'
	
AWS_DB = AwsDB.new
AWS_IVR_TABLE = ENV['NEXMO_IVR_TABLE']	

S3_CLIENT = Aws::S3::Client.new
S3_BUCKET = ENV['NEXMO_KRISPYKREME_BUCKET_NAME']

NEXMO_CONTROLLER = NexmoBasicController.new
NCCO = NexmoNCCO.new




class NexmoIVRController

	def logging_setup
		t = Time.now
		t_string = "#{t.year}#{t.mon}#{t.day}-#{t.hour}#{t.min}#{t.sec}"

		::Logger.class_eval { alias :write :'<<' }

		# # access_log = "logs/access_log_#{t_string}"		
		# $access_logger = Logger.new('logs/access_log', 'weekly')
		# $access_logger.info "\n==============================================\nStarting Access Log: #{t}\n=============================================="

		# original_formatter = Logger::Formatter.new
		# $access_logger.formatter = proc {|severity,datetime,progname,msg|
		# 	"#{severity}: [#{datetime}] #{msg}\n---\n"
		# }

		# log_name = "logs/app_log_#{t_string}"
		$app_logger = Logger.new('logs/app_log', 10, 30000000)
		$app_logger.info "\n==============================================\nStarting App Log: #{t}\n=============================================="

		original_formatter = Logger::Formatter.new
		$app_logger.formatter = proc {|severity,datetime,progname,msg|
			"#{severity}: [#{datetime}] #{msg}\n---\n"
		}
	end

	def html_logging_prefix(meth,request,type)
		return "#{meth} | #{request.ip} : #{request.user_agent} | #{type} |"
	end

    def error_responses(error,data=Hash.new)
    	dnis = data[:dnis] || nil
    	key = data[:key] || nil
    	value = data[:value] || nil
    	errors = {
    		'search_not_found': "No results found for '#{key}' = '#{value}'",
    		'render_stores': "Unable to display list of stores.  This most likely means that we couldn't access any data from the database but honestly if you're seeing this we haven't accounted for this error.",
    		# 'login_error': "Invalid Login Credentials.  Please try again.  Error: '#{err_msg}'",
    		# 'unauthorized': "You have been logged out of your session.  Please login again.",
    		# 'not_registered': "Your client_id is not registered to access this application.  Please contact your administrator to provision your client_id",
    		# 'session_expired': "Your session has expired.  Please login again",
    		# 'update_all_fields': "Make sure every field is populated.  Submitting with blank fields will cause data to be erased",
    		# 'delete_ok': "'#{dnis}' successfully deleted",
    		# 'edit_ok': "'#{dnis}' successfully edited",
    		# 'delete_failed': "'#{dnis}' could not be deleted.  Request failed with error: '#{err_msg}'",
    		# 'edit_failed': "'#{dnis}' could not be edited.  Request failed with error: '#{err_msg}'",
    		# 'unknown_request': "An unknown error has occurred.  Please try your request again or contact your administrator",
    		# 'query_not_found': "Unable to find requested DNIS of '#{dnis}' with trigger_pop '#{trigger_pop}'",
    	}  	

    	return errors[error.to_sym]
    end

    def get_prompts(params)
    	$app_logger.debug "#{__method__} | Params In : #{params}"
		warning = nil
		error = nil
		success = nil
		# params = Hash.new if params.nil?

		if params.is_a?(Hash)
			if params.has_key?('warning')
				warning = error_responses(params['warning'],{key: params['key'], value: params['value']})
				params.delete('key')
				params.delete('value')
			elsif params.has_key?('error')
			elsif params.has_key?('success')
			end
		end
		$app_logger.debug "#{__method__} | Params Out: #{params}"

		return warning,error,success
    end	
	

	def get_scan_filtered_results(filter_name,filter_value)
    	scan_params = {
			table_name: AWS_IVR_TABLE,
			expression_attribute_values: {":v" => "#{filter_value}"},
			filter_expression: "contains(#{filter_name}, :v)",
    	}
    	return AWS_DB.scan_table_with_filters(scan_params)		
	end

	def get_filtered_store_list(dnis_array)
		request_id = EditStoresDB.add_new_edit_request(dnis_array)
		$app_logger.info "#{__method__} | DNIS ARRAY: #{dnis_array} | Request ID : #{@request_id}"

		stores = AWS_DB.scan_table(AWS_IVR_TABLE)[:items]		
		store_list = Array.new
		stores.each do |store|
			store_list.push(store) if dnis_array.include?(store['dnis'])
		end
		stores_count = stores.length
		stores_names = stores[0].keys
		media_types = stores[0]['media_files'].keys

		return stores,stores_count,stores_names,media_types,request_id
	end
end

class EditStoresDB
	include DataMapper::Resource
	property :id, Serial
	property :request_id, String
	property :dnis_list, String	

	def self.add_new_edit_request(dnis_list)
		request_id = SecureRandom.hex 
		first_or_create(
			 request_id: request_id,
			 dnis_list: dnis_list.join(",")
			)
		return request_id
	end

	def self.get_edit_request(request_id)
		first(request_id: request_id)
	end

	def self.delete_edit_request(request_id)
		first(request_id: request_id).destroy!
	end
end

class MyApp < Sinatra::Base
	
	# configure do 
 	# 	enable :sessions
 	# end	

	use AppRoutes
	use NexmoIVRRoutes

    # Set Root Directories
    $root_dir = File.dirname(__FILE__)
    $views_dir = Proc.new { File.join(root, "views") } 
	set :root, $root_dir
	set :views, $views_dir
	
	$ivr = NexmoIVRController.new
	$ivr.logging_setup

	# Configure Nexmo Application
	$app = NEXMO_CONTROLLER.update_webserver

	# Configure in-memory DB
	DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/auth.db")

	EditStoresDB.auto_migrate!
	$app_logger.debug "Cleard DB on start: #{EditStoresDB.destroy}"
end