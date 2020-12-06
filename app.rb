#!/usr/bin/env ruby
#
STDOUT.sync = true

require 'json'
require 'securerandom'
require 'dm-core'
require 'dm-migrations'
require 'logger'
require 'sinatra'
require 'vonage'
require 'aws-sdk-s3'
require 'aws-sdk-dynamodb'
require_relative 'src/aws_dynamo'
require_relative 'src/nexmo_aws_dynamo_helpers'
require_relative 'src/nexmoController'
require_relative 'src/nexmoNCCO'
require_relative 'src/nexmoIVRRoutes'
require_relative 'src/appRoutes'
	
AWS_DB = AwsDB.new
AWS_IVR_TABLE = ENV['NEXMO_IVR_TABLE']	
AWS_CALLS_TABLE = ENV['NEXMO_KRISTPYKREME_CALLS_TABLE']

S3_CLIENT = Aws::S3::Client.new
S3_BUCKET = ENV['NEXMO_KRISPYKREME_BUCKET_NAME']

NEXMO_CONTROLLER = NexmoBasicController.new
NCCO = NexmoNCCO.new
NEXMO_DYNAMO_HELPERS = NexmoDynamoHelpers.new
NEXMO_TMP_DIR = 'public/wav/'

STORE_HEADER_ORDER = [
	'name',
	'dnis',
	'closed_for_reason',
	'division',
	'district',
	'commisary',
	'depot',
	'kiosk',
	'retail',
	'addr_street',
	'addr_city',
	'addr_state',
	'addr_zip',
	'timezone'
]


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
    		'no_stores_selected': "No stores selected.  Please select one or more stores to edit",
    		'search_not_found': "No results found for '#{key}' = '#{value}'",
    		'render_stores': "Unable to display list of stores.  This most likely means that we couldn't access any data from the database but honestly if you're seeing this we haven't accounted for this error.",
    		'post_edit': "Something went wrong trying to submit your changes.  Please contact your Administrator if the problem continues\nError: #{value}",
    		'stores_results': "Something went wrong trying to view /stores/results.  Please contact your Administrator if the problem continues\nError: #{value}",
    		'post_stores_recording_call': "Something went wrong trying to make a call.  Please contact your Administrator if the problem continues\nError: #{value}",
    		'unable_to_connect': "Unable to connect to phone #{key}.  Error: #{value}",
    		'failed_to_get_recording': "Failed to save new greeting or greeting length was too short.  Please try recording your greeting again.",
    		'rendor_recording_new': "Well this is an unexpected error.  The error was: #{value} and we were not prepared to handle this.  Please try your request again",
    		'post_stores_recording_upload': "Error uploading File: #{value}",
    		'file_upload_success': "Successfully Updates Stores",
    		'WRONG_FILE_TYPE': "Error Uploading File.  Unsupported file type of '#{value}'.  Please upload only wav or mp3 files",
    		# 'login_error': "Invalid Login Credentials.  Please try again.  Error: '#{err_msg}'",
    		# 'unauthorized': "You have been logged out of your session.  Please login again.",
    		# 'not_registered': "Your client_id is not registered to access this application.  Please contact your administrator to provision your client_id",
    		# 'session_expired': "Your session has expired.  Please login again",
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
				error = error_responses(params['error'],{key: params['key'], value: params['value']})				
			elsif params.has_key?('success')
				success = error_responses(params['success'],{key: params['key'], value: params['value']})
			end
		end
		$app_logger.debug "#{__method__} | Params Out: Warning: #{warning}, Error: #{error}, Success: #{success}"

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

	def filtered_store_list(action, data)

		# If creating new DB entry, return request_id for future reference
		# Otherwise return empty string and remember to ignore it 
		dnis_array = data[:dnis_array] || Array.new
		request_id = "NOT_USED_FOR_GET"
		request_id = EditStoresDB.add_new_edit_request(dnis_array) if action == :create		
		dnis_array = EditStoresDB.get_edit_request(data[:request_id])[:dnis_list].split(",") if action == :get
		
		$app_logger.info "#{__method__} | FILTER_STORES : Action: #{action.to_s} | DNIS ARRAY: #{dnis_array} |  | Request ID : #{@request_id}"

		# Regardless of :get or :create query dnis's from AWS
		stores = AWS_DB.scan_table(AWS_IVR_TABLE)[:items]		
		store_list = Array.new
		stores.each do |store|
			store_list.push(store) if dnis_array.include?(store['dnis'])
		end

		stores_count = store_list.length
		stores_names = stores[0].keys
		media_types = stores[0]['media_files'].keys
		media_types.push('open')

		return store_list,stores_count,stores_names,media_types,request_id
	end

	def get_store_headers(store_list,neat=true)
		# Order headers for views
		# Add any headers that we don't care about to end of the list
		ordered_store_headers = STORE_HEADER_ORDER
		store_list.each do |k|
			next if neat && k == 'open_hours' || k == 'media_files'
			ordered_store_headers.push(k) unless STORE_HEADER_ORDER.include?(k)
		end
		$app_logger.info "#{__method__} | ORDERED HEADERS: #{ordered_store_headers}"
		return ordered_store_headers
	end

	def stores_edit(params)
		db_result = EditStoresDB.get_edit_request(params['request_id'])
		$app_logger.info "#{__method__} | DB_RESULT : #{db_result.inspect}"

		dnis_list = db_result[:dnis_list].split(",")
		dnis_list.each do |dnis|
			item = AWS_DB.get_item(AWS_IVR_TABLE,{dnis: dnis})[:item]
			media_files = item['media_files']

			if params['search'] == 'open' || params.has_key?('file_name') == false
				# I don't think we want to reset the assigned media file but not sure it matters either way
				# media_files[item['closed_for_reason']] = "_NIL_"
				closed_for_reason = params['search'] == 'open' ? "_NIL_" : params['search']
				result = AWS_DB.update_item(
					AWS_IVR_TABLE,
					{dnis: dnis},
					"Set #r = :r",
					{':r' => closed_for_reason},
					"ALL_NEW",
					{'#r' => 'closed_for_reason'}
				)
				$app_logger.info "#{__method__} | AWS_DB | Update Closed for Reason Result for #{dnis}: '#{result}' | Media Files: #{media_files}"				
			else
				media_files["#{params['search']}"] = params['file_name']
				result = AWS_DB.update_item(
					AWS_IVR_TABLE,
					{dnis: dnis},
					"Set #r = :r, #m = :m",
					{':r' => params['search'], ':m' => media_files},
					"ALL_NEW",
					{'#r' => 'closed_for_reason', '#m' => 'media_files'}
				)
				$app_logger.info "#{__method__} | AWS_DB | Update CoR and Media File Result for #{dnis}: '#{result}' | Media Files: #{media_files}"
			end

		end	
		store_or_stores = dnis_list.length > 1 ? 'Stores' : 'Store'
		return {stores_updated: "#{dnis_list.length}", store_or_stores: store_or_stores}
	end

	def recording_greeting(phone_number,file_name)

		begin
			$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | NEXMO | Make Call To: #{phone_number} with file: #{file_name}"
			response_code,response_body = NEXMO_CONTROLLER.make_call(phone_number)
			request_payload = JSON.parse(response_body, symbolize_names: true)
			$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | NEXMO | Make Call To: #{phone_number} | Result : #{request_payload}"

			db_result = NEXMO_DYNAMO_HELPERS.update_dynamo_event(request_payload)
			$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | AWS | Add New Call  | Result : #{db_result}"

			result = AWS_DB.update_item(
				AWS_CALLS_TABLE,
				{conversation_uuid: request_payload[:conversation_uuid]},
				"Set #f = :f",
				{':f' => file_name},
				"ALL_NEW",
				{'#f' => 'file_name'}
			)
			$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | AWS | Update Call with File: #{file_name}  | Result : #{db_result}"

			item = Hash.new
			status = request_payload[:status]
			count = 0
			until status =~ /completed/ || status =~ /busy/ || count > 10 do 
				sleep(10)
				item = AWS_DB.get_item(AWS_CALLS_TABLE,{conversation_uuid: request_payload[:conversation_uuid]})[:item]
				status = item['status']
				count += 1
				$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | AWS | Waiting for Status completed or busy : #{status} | Count : #{count}"
			end

		rescue => e
			return {error: e}
		else
			if item.has_key?('size') && item['size'] > 150000
				return {conversation_uuid: result[:conversation_uuid], status: status}
			else
				result = AWS_DB.update_item(
					AWS_CALLS_TABLE,
					{conversation_uuid: request_payload[:conversation_uuid]},
					"Set #f = :f",
					{':f' => ''},
					"ALL_NEW",
					{'#f' => 'file_name'}
				)	
				$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | AWS | No Recording found or Recording too short | Deleted filename: #{result}"
				return {conversation_uuid: result[:conversation_uuid], status: 'failed_to_get_recording'}
			end
		end
	end	

	def upload_greeting(params)
		$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | FILE UPLOAD : #{params['file_data'].inspect}"
		result = Hash.new
		if (tmpfile = params['file_data']['tempfile']) && (file_data = params['file_data']['filename'])
			# Only upload if file is of type mp3: audio/mpeg or wav: audio/wav	
			if params['file_data']['type'] == 'audio/mpeg' || params['file_data']['type'] == 'audio/wav'
				$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | FILE UPLOAD START"
				my_file = File.open("public/wav/#{params['file_name']}", 'wb')
				while blk = tmpfile.read(65536)
					my_file.write blk
				end

				$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | FILE UPLOAD | AWS_S3 START"			
				upload_file = File.open("public/wav/#{params['file_name']}", 'rb')
				s3_object = S3_CLIENT.put_object(
					{
						body: upload_file,
						bucket: S3_BUCKET,
						key: params['file_name']
					}
				)
				$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | FILE UPLOAD | AWS_S3 : #{s3_object}"			

				File.delete(upload_file)
				result = {status: s3_object}
			else
				result = {error: "WRONG_FILE_TYPE", value: params['file_data']['type']}
			end
		else
			result = {error: "NO_FILE_SELECTED"}
			$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | FILE UPLOAD ERROR: #{result}"
		end

		return result

	end

	def play_next_ncco(request_payload)
		$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__}  | NEXMO | Getting Next NCCO"
		dtmf_num = request_payload[:dtmf].to_i
		ncco = ""

		case dtmf_num
		when 1
			ncco = NCCO.ncco_play_recording_prompt		
		end

		return ncco
	end

	def validate_recording(request_payload)
		dtmf_num = request_payload[:dtmf].to_i

		ncco = ""
		begin 
			item = AWS_DB.get_item(AWS_CALLS_TABLE,{conversation_uuid: request_payload[:conversation_uuid]})[:item]
			file = S3_CLIENT.get_object({bucket: S3_BUCKET, key: item['file_name']})
			$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__}  | NEXMO AWS | item : #{item} | file : #{file}"

			if item.has_key?('file_name')
				case dtmf_num
				when 1
					if file['content_length'] > 0
						ncco = NCCO.ncco_play_recording_success(item['file_name'])
					else
						$app_logger.debug "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__}  | NEXMO AWS | File length less then 0"
						ncco = NCCO.ncco_play_recording_error
					end
				when 2
					ncco = NCCO.ncco_play_recording_back(item['file_name'])
				when 3
					file = S3_CLIENT.delete_object({bucket: S3_BUCKET, key: item['file_name']})
					$app_logger.debug "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__}  | NEXMO AWS | Delete object and rerecord result : #{file}"
					ncco = NCCO.ncco_play_recording_prompt
				end
			else
				$app_logger.debug "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__}  | NEXMO AWS | File Name Not Found with conversation_uuid; #{request_payload[:conversation_uuid]}"
				ncco = NCCO.ncco_play_recording_error
			end

		rescue => e
			$app_logger.debug "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__}  | NEXMO AWS | Unhandled Error : #{e}"
			ncco = NCCO.ncco_play_recording_error			
		end	

		return ncco		
	end

	def post_call_cleanup(conversation_uuid)
		$app_logger.debug "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__}  | request_payload : #{conversation_uuid}"

		item = AWS_DB.get_item(AWS_CALLS_TABLE,{conversation_uuid: conversation_uuid})[:item]
		File.delete("#{NEXMO_TMP_DIR}#{item['file_name']}")
		$app_logger.debug "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__}  | Delete Temp File: #{NEXMO_TMP_DIR}#{item['file_name']}"
		return 1
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
    $public_dir = File.join($root_dir,"public")
	set :root, $root_dir
	set :views, $views_dir

	$ivr = NexmoIVRController.new
	$ivr.logging_setup

	# Configure Nexmo Application
	NEXMO_CONTROLLER.update_webserver

	# Configure in-memory DB
	DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/auth.db")

	EditStoresDB.auto_migrate!
	$app_logger.debug "Cleard DB on start: #{EditStoresDB.destroy}"
end