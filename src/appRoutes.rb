
class AppRoutes < Sinatra::Base
	set :root, $root_dir
	set :views, $views_dir

	get '/error' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"
		@error_msg = "Something really bad has happened that we didn't expect. Stay calm and try again.  If it happens again please ask for help"
		@warning,@error,@succuss = $ivr.get_prompts(params)

		erb :error
	end

	get '/stores' do 		
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params IN: #{params} | Params is a Hash? #{params.is_a?(Hash)}"		
		@warning,@error,@succuss = $ivr.get_prompts(params)
		@stores = Array.new
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params OUT: #{params} | Params is a Hash? #{params.is_a?(Hash)}"

		begin
			if params.has_key?('search')
				puts "looking at search: #{params['search']}"
				if params.has_key?('value')
					puts "looking at value: #{params['value']}"
					@stores = $ivr.get_scan_filtered_results(params['search'],params['value'])[:items]
					$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"AWS_DB")} SCAN FILTER Result : #{@stores}"
					if @stores.empty?
						redirect "/stores?warning=search_not_found&key=#{params['search']}&value=#{params['value']}"
					end
				end
			else
				@stores = AWS_DB.scan_table(AWS_IVR_TABLE)[:items]
				$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"AWS_DB")} SCAN: #{AWS_IVR_TABLE} | Results : Count = #{@stores.length} Headers = #{@stores[0].keys}"
			end
			@stores_count = @stores.length
			@stores_names = @stores[0].keys
		rescue => e
			$app_logger.error "#{$ivr.html_logging_prefix(__method__,request,"ERROR")} #{e} | Redirecting to /error"
			redirect '/error?error=render_stores'	
		else
			$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"RENDOR")} stores.erb"		
			erb :stores
		end
	end

	get '/stores/bulk' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"

		# Create array of DNIS values and filter SCAN results
		@stores,@stores_count,@stores_names,@media_types,@request_id = $ivr.get_filtered_store_list(params.values)

		files = S3_CLIENT.list_objects({bucket: S3_BUCKET, max_keys: 50})[:contents]
		@existing_files = Array.new
		files.each do |file|
			@existing_files.push(file['key'])
		end
		@existing_files.push("Add New File")
		$app_logger.debug "#{__method__} | Files : #{files} | Filtered List : #{@existing_files}"

		erb :bulk_edit
	end

# update_item(table_name,key,update_expression,expression_attribute_values,return_values,expression_attribute_names=nil)
	post '/stores/edit' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"
		db_result = EditStoresDB.get_edit_request(params['request_id'])
		$app_logger.info "#{__method__} | DB_RESULT : #{db_result.inspect}"

		dnis_list = db_result[:dnis_list].split(",")
		dnis_list.each do |dnis|
			item = AWS_DB.get_item(AWS_IVR_TABLE,{dnis: dnis})[:item]
			media_files = item['media_files']
			media_files["#{params['search']}"] = params['file_name']
			result = AWS_DB.update_item(
				AWS_IVR_TABLE,
				{dnis: dnis},
				"Set #r = :r, #m = :m",
				{':r' => params['search'], ':m' => media_files},
				"ALL_NEW",
				{'#r' => 'closed_for_reason', '#m' => 'media_files'}
			)
			$app_logger.info "#{__method__} | AWS_DB | Update Result for #{dnis}: '#{result}' | Media Files: #{media_files}"
		end

		redirect "/stores/results?request_id=#{params['request_id']}"
	end

	get '/stores/results' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"
		200
	end

	get '/recordings' do 
		@recordings = AWS_DB.scan_table(AWS_REC_TABLE)[:items]
		@recordings_count = @recordings.length
		@recordings_names = @recordings[0].keys

		$app_logger.info "#{__method__} | AWS_DB | recordings #{@recordings}"
		$app_logger.info "#{__method__} | AWS_DB | recordings_names #{@recordings_names}"
		erb :recordings				
	end



end
