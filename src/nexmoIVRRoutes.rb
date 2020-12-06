
class NexmoIVRRoutes < Sinatra::Base

	# AWS Health Check
	get '/' do; 200; end
		
	get '/answer_nexmo_ivr' do 
		root_url = request.base_url
		
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"

		$app_logger.info "#{__method__} | ANSWER Params : #{params}" 

		

		ncco = NCCO.ncco_play_recording_greeting
		content_type :json				
		return ncco		
	end

	post '/event_nexmo_ivr' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"		

		request_payload = JSON.parse(request.body.read, symbolize_names: true)
		$app_logger.info "#{__method__} | EVENT : #{request_payload}"

		call_info = NEXMO_DYNAMO_HELPERS.update_dynamo_event(request_payload)

		return 200
	end	

	post '/event_nexmo_ivr/greeting' do
 		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"

		request_payload = JSON.parse(request.body.read, symbolize_names: true)
		$app_logger.info "EVENT | #{__method__} | #{request_payload}"

		# call_info = NEXMO_DYNAMO_HELPERS.update_dynamo_event(request_payload)
		ncco = ""
		if request_payload.has_key?(:dtmf)
			ncco = $ivr.play_next_ncco(request_payload)
		end

		$app_logger.info "#{__method__} | NCCO : #{ncco}"
		content_type :json		
		return ncco
	end		

	post '/event_nexmo_ivr/recording' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"

		request_payload = JSON.parse(request.body.read, symbolize_names: true)
		$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | EVENT | #{__method__} | #{request_payload}"

		call_info = NEXMO_DYNAMO_HELPERS.update_dynamo_event(request_payload)
		file_name = call_info[:attributes]['file_name'] # || "#{request_payload[:conversation_uuid]}.wav"
		$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | AWS_DB | Filename : #{file_name}"

		$app_logger.debug("#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | CR_DOWNLOAD | Get File : #{request_payload[:recording_url]}")			
		cr_download_result,s3_object = NEXMO_CONTROLLER.nexmo_get_cr(request_payload[:recording_url],file_name,:s3)
		$app_logger.debug("#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | CR_DOWNLOAD | Download Recording Result: #{cr_download_result}")
			

		return 200
	end		
end	