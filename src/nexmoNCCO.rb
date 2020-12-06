
class NexmoNCCO

	# NCCO Actions
	def ncco_play_user_num(from_num)
		from_string = "#{from_num[0]},#{from_num[1..3]},#{from_num[4..6]},#{from_num[7..10]}".chars.join(" ")
		return [
			{
				"action": "talk",
				"text": "Thank you, Your Number was: #{from_string}"
			}
		].to_json
	end

	def ncco_play_recording_greeting
		return [
			{
				"action": "talk",
				"text": "We are going to record a new greeting.  Press 1 when you are ready",
				"bargeIn": true
			},
			{
				"action": "input",
				"submitOnHash": true,
				"maxDigits": 1,	
				"timeOut": 10,		
				"eventUrl": ["#{EVENT_URL}/greeting"]
			}
		].to_json
	end

	def ncco_play_recording_prompt
		return [
			{
				"action": "talk",
				"text": "Start recording your greeting at the beep.  Press pound when complete.",

			},
			{
				"action": "record",
				"submitOnHash": true,
				"endOnSilence": 3,	
				"endOnKey": "#",
				"timeOut": "30",
				"beepStart": "true",
				"format": "wav",	
				"eventUrl": ["#{EVENT_URL}/recording"]
			},
			{
				"action": "talk",
				"text": "Thank you.  Press 1 to save your greeting, 2 to listen to your greeting, or 3 to try again.",				
			},
			{
				"action": "input",
				"submitOnHash": true,
				"maxDigits": 1,	
				"timeOut": 5,		
				"eventUrl": ["#{EVENT_URL}/recording/validation"]				
			}
		].to_json
	end

	def ncco_play_recording_back(stream1)
		return [
			{
			"action": "stream",
			"streamUrl": ["#{NEXMO_STREAM_URL}#{stream1}"]				
			},
			{
				"action": "talk",
				"text": "Press 1 to save your greeting, 2 to listen to your greeting, or 3 to try again.",
			},
			{
				"action": "input",
				"submitOnHash": true,
				"maxDigits": 1,	
				"timeOut": 5,		
				"eventUrl": ["#{EVENT_URL}/recording/validation"]				
			}			
		].to_json
	end

	def ncco_play_recording_success(file_name)
		file_parts = file_name.split(/\./)
		return [
			{
				"action": "talk",
				"text": "Your recording, #{file_parts[0]} dot #{file_parts[1]} has been saved and uploaded.  It is now ready to be used.  Goodbye"
			},			
		].to_json		
	end

	def ncco_play_recording_error
		return [
			{
				"action": "talk",
				"text": "There was an error retrieving your greeting.  Please hang up and try recording it again"
			},			
		].to_json

	end
end
