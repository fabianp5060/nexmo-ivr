
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

end
