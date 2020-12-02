#!/usr/bin/env ruby
#

class AwsDB
	def initialize
		$dynamodb = Aws::DynamoDB::Client.new
		return true
	end

	def db_request(cmd,query=nil)
		response = nil
		# puts "#{__method__} | Query Params : #{query}"
		begin
			response = $dynamodb.send(cmd,query)
		rescue => e
			# puts "Error Loading Data: #{e}"
			return e #{Aws::DynamoDB::Errors::ServiceError => error}
			
		else
			# puts "#{__method__} | DB Response : #{response.to_h}"
			return response.to_h
		end
	end

	def delete_item(table_name,key)
		cmd = :delete_item
		request = params = {
		    table_name: table_name,
		    key: key
		}

		# puts "#{__method__} : request : #{request}"		
		return db_request(cmd,request)
	end

	def get_item(table_name,key_hash)
		cmd = :get_item
		request = {
			table_name: table_name,
			key: key_hash
		}
		# puts "#{__method__} : My request: #{request}"

		return db_request(cmd,request)
	end

	def item_exists?(result=nil,attribute=nil,search_param)

		item = attribute 		
		item = send(:get_item,attribute[0],email_address: attribute[1][:email_address])	if attribute.is_a?(Array)

		item_exists = false			
		item_exists = true if item.has_key?(search_param) && !(item[search_param].eql?("null"))
			
		# puts "#{__method__} : Item Exists: #{item_exists} : item[search_param] = #{item[search_param]} | Equals 'null'? #{item[search_param].eql?("null")}"

		return item_exists,item
	end

	def put_item(table_name,return_values,item_hash,condition_expression=nil)
		cmd = :put_item
		request = {
			table_name: table_name,
			return_values: return_values,
			condition_expression: condition_expression,
			item: item_hash
		}		

		# puts "#{__method__} : request : #{request}"
		request.delete(:condition_expression) if condition_expression == nil

		return db_request(cmd,request)
	end

	def update_item(table_name,key,update_expression,expression_attribute_values,return_values,expression_attribute_names=nil)
		cmd = :update_item
		request = {
			table_name: table_name,
			key: key,
			update_expression: update_expression,
			expression_attribute_values: expression_attribute_values,
			return_values: return_values
		}
		request[:expression_attribute_names] = expression_attribute_names if expression_attribute_names
		return db_request(cmd,request)
	end

	def scan_table(table_name)
		cmd = :scan
		return db_request(cmd,{table_name: table_name})
	end

	def scan_table_with_filters(params)
		cmd = :scan
		request = {
			table_name: params[:table_name],
			expression_attribute_names: params[:expression_attribute_names],
			expression_attribute_values: params[:expression_attribute_values],
			filter_expression: params[:filter_expression]
		}
		return db_request(cmd,request)
	end

	def query(params)
		cmd = :query
		request = {
			table_name: params[:table_name],
			key_condition_expression: params[:key_condition_expression],
			expression_attribute_values: params[:expression_attribute_values]
		}
		request[:index_name] = params[:index_name] if params[:index_name]
		request[:expression_attribute_names] = params[:expression_attribute_names] if params[:expression_attribute_names]
		request[:filter_expression] = params[:filter_expression] if params[:filter_expression]
		return db_request(cmd,request)
	end

end
