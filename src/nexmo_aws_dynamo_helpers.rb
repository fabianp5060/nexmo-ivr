
class NexmoDynamoHelpers
	def make_hoh(x=0)
	    hoh = Hash.new do |k1,v1|
	        k1[v1] = Hash.new(x)
	    end
	end

	def make_expression_key(key,type=nil)
		k = nil
		prefix = ':'
		prefix = '#' if type == 'names'

		case key
		when :conversation_uuid; k = "#{prefix}c"
		when :direction; k = "#{prefix}d"
		when :dtmf; k = "#{prefix}dt"
		when :duration; k = "#{prefix}du"
		when :end_time; k = "#{prefix}e"
		when :from; k = "#{prefix}f"		
		when :network; k = "#{prefix}n"
		when :price; k = "#{prefix}p"		
		when :rate; k = "#{prefix}r"	
		when :reason; k = "#{prefix}re"	
		when :start_time; k = "#{prefix}s"
		when :status; k = "#{prefix}st"
		when :timed_out; k = "#{prefix}ti"			
		when :timestamp; k = "#{prefix}t"
		when :to; k = "#{prefix}to"
		when :uuid; k = "#{prefix}u"
		when :recording_url; k = "#{prefix}ru"
		when :size; k = "#{prefix}si"
		else
			puts "#{__method__} : Found unknown key in Nexmo Event: #{key}"
		end
		return k
	end

	# Returns Hash of Hash
	# attr_values["attr_name"][":<attr_short_name>"] = attr_value
	def make_expression_attribute_values(event)
		attr_values = make_hoh

		event.each do |k,v| 
			if k == "start_time"
				puts "Found start time: methods: #{v.methods}, methods contain strftime? #{v.methods.include?(:strftime)}"
			end
			attr_values[k][make_expression_key(k,)] = v 
		end
		return attr_values
	end

	# Returns Hash
	# attr_names["#<attr_short_name"] = <attr_name>.to_s
	def make_expression_attribute_names(event)
		attr_names = Hash.new

		event.each {|k,v| attr_names[make_expression_key(k,"names")] = k.to_s}
		return attr_names
	end

	# Remove the first hash ["attr_name"] from make_expression_attribute_values
	def clean_up(attr_values_hash_of_hash)
		attr_values = Hash.new
		attr_values_hash_of_hash.each do |bad_key,good_hash|
			attr_values.merge!(good_hash)
		end
		return attr_values
	end

	#Make Update expression
	# 'SET <attribute_name> = :<attribute_short_name>'
	# :<attribute_short_name> points to a value from the expression_attribute_value
	def make_update_expression_values(event,attr_values)
		update_string = 'SET '
		event.each do |k,v|
			update_string += "#{make_expression_key(k,"names")} = #{attr_values[k].key(v)}, "
		end
		return update_string[0...-2]
	end

	def update_dynamo_event(e)
		item = AWS_DB.get_item(AWS_CALLS_TABLE,{conversation_uuid: e[:conversation_uuid]})[:item]
		$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | CALL_AWS_QUERY | Result : '#{item}'"
		e.delete(:headers)
		e.delete(:recording_uuid)
		db_result = nil
		if item		
			e.delete(:conversation_uuid)
			e.delete(:uuid)
			e[:dtmf] = "NULL" if e[:dtmf] == ""

			key = {conversation_uuid: item["conversation_uuid"]}

			expression_attribute_values = make_expression_attribute_values(e)
			expression_attribute_names = make_expression_attribute_names(e)
			update_expression = make_update_expression_values(e,expression_attribute_values)

			db_result = AWS_DB.update_item(
				AWS_CALLS_TABLE,
				key,
				update_expression,
				clean_up(expression_attribute_values),
				"ALL_NEW",
				expression_attribute_names
			)
			$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | CALL_AWS_UPDATE | Result : '#{db_result}'"
		else
			db_result = AWS_DB.put_item(AWS_CALLS_TABLE,nil,e)
			$app_logger.info "#{__FILE__.split('/')[-1]}.#{__method__}:#{__LINE__} | CALL_AWS_PUT | Result : '#{db_result}'"
		end

		return db_result
	end	
end