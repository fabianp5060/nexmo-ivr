
class NexmoIVRRoutes < Sinatra::Base

	# AWS Health Check
	get '/' do; 200; end
		
	get '/answer_nexmo_ivr' do 
		$app_logger.info "ANSWER | #{__method__} | My Params : #{params}" 
		root_url = request.base_url

		ncco = NCCO.ncco_play_user_num(params['from'])
		content_type :json				
		return ncco		
	end

	post '/event_nexmo_ivr' do 
		request_payload = JSON.parse(request.body.read, symbolize_names: true)
		$app_logger.info "EVENT | #{__method__} | #{request_payload}"

		return 200
	end	
end	