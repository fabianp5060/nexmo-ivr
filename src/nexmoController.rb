# Vonage General Demo Environment
KEY = ENV['NEXMO_API_KEY']
SEC = ENV['NEXMO_API_SECRET']
APP_KEY = ENV['NEXMO_APPLICATION_PRIVATE_KEY_PATH']
WEB_SERVER = ENV['LB_WEB_SERVER2'] || JSON.parse(Net::HTTP.get(URI('http://127.0.0.1:4040/api/tunnels')))['tunnels'][0]['public_url']
# WEB_SERVER = ENV['AWS_WEB_SERVER']
# NEXMO_STREAM_URL = "#{WEB_SERVER}/stream/poly/"
# NEXMO_STREAM_URL2 = "#{WEB_SERVER}/stream/cr/"

# Vonage Specific Demo Environment
APP_NAME = ENV["#{'nexmo_ivr'.upcase}_APP_NAME"]
APP_ID = ENV["#{'nexmo_ivr'.upcase}_APP_ID"]
APP_DID = ENV["#{'nexmo_ivr'.upcase}_DID"]
EVENT_URL = "#{WEB_SERVER}/event_nexmo_ivr"
ANSWER_URL = "#{WEB_SERVER}/answer_nexmo_ivr"

# Create Vonage Object
NEXMO_LOGGER = Logger.new(STDOUT)


class NexmoBasicController

	def initialize
		@client = Vonage::Client.new(
		  logger: NEXMO_LOGGER,	
		  api_key: KEY,
		  api_secret: SEC,
		  application_id: APP_ID,
		  private_key: File.read("#{APP_KEY}")
		)
	end

	def update_webserver
		puts "My vars: ID: #{APP_ID}, WS: #{WEB_SERVER}, NAME: #{APP_NAME}"
		application = @client.applications.update(
			APP_ID,
			{
				name: APP_NAME,
				capabilities: {
					voice: {
						webhooks: {							
							answer_url: {
								address: ANSWER_URL,
								http_method: "GET"
							},
							event_url: {
								address: EVENT_URL,
								http_method: "POST"
							}
						}
					}
				}
			}				
		)
		puts "My application #{application.inspect}"
		puts "Updated nexmo application name:\n  #{application.name}\nwith webhooks:\n  #{application.capabilities.voice.webhooks.event_url.http_method} #{application.capabilities.voice.webhooks.event_url.address}\n  #{application.capabilities.voice.webhooks.answer_url.http_method} #{application.capabilities.voice.webhooks.answer_url.address}"
		return application
	end

	def update_number(country,msisdn,update_params)
		update_params.merge!({country: country, msisdn: msisdn, voice_callback_type: 'app', voice_callback_value: APP_ID})
		puts "#{__method__} | My vars: Country Code: #{country}, Number: #{msisdn}, Params: #{update_params}"

		number = @client.numbers.update(update_params)
	end


	def send_sms(msg,to=nil,from=nil)
		from = $did unless from
		puts "#{__method__}; SMS from: #{from} to: #{to} msg: #{msg}"
		return @client.sms.send(from: from, to: to, text: msg)
	end	

	def normalize_numbers(num)
		if num.to_s =~ /^\d{10}$/
			puts "#{__method__} | Normalizing number: #{num}"
			num = "1#{num}"
		end	
		return num	
	end	

	def validate(input)
		alpha_nums = ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a + ("0".."9").to_a
		return true if input.chars.all? {|ch| alpha_nums.include?(ch)}
	end

	def sanitize(input)
		input.to_s.gsub!(/\s/,"")
		input.to_s.gsub!(/\+/,"")

		is_valid = validate(input)

		return normalize_numbers(input) #if is_valid
	end

	def save_recording(recording_url,local_path)
		@client.files.save(recording_url,local_path)
	end

	def nexmo_get_cr(recording_url,file_name)
		claims = {
		  application_id: APP_ID,
		  private_key: APP_KEY,
		  nbf: 1483315200,
		  ttl: 800
		}

		token = Vonage::JWT.generate(claims)
		url = URI(recording_url)

		https = Net::HTTP.new(url.host, url.port);
		https.use_ssl = true	
		# https.set_debug_output(STDOUT)

		request = Net::HTTP::Get.new(url)
		request["Content-Type"] = "application/json"
		request["Authorization"] = "Bearer #{token}"

		file = open(file_name, 'wb')
		response_code = nil
		begin
			https.request(request) do |response|
				response_code = response.code
				response.read_body do |chunk|
					file.write(chunk)
				end
			end
		ensure
			file.close
		end
		
		return response_code
	end	

end