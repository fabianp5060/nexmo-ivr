
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
		@stores_count = Array.new
		@stores_names = Array.new
		@stores_action = ""
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
			elsif params.has_key?('select-all')
				params.delete('select-all')
				@stores = $ivr.get_scan_filtered_results(params['search'],params['value'])[:items]
				@stores_action = "Editing"
				$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"AWS_DB")} SCAN FILTER Result : #{@stores}"
				if @stores.empty?
					redirect "/stores?warning=search_not_found&key=#{params['search']}&value=#{params['value']}"
				end
			else
				@stores = AWS_DB.scan_table(AWS_IVR_TABLE)[:items]
				$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"AWS_DB")} SCAN: #{AWS_IVR_TABLE} | Results : Count = #{@stores.length} Headers = #{@stores[0].keys}"
			end
			@stores_count = @stores.length
			@stores_names = $ivr.get_store_headers(@stores[0].keys)
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
		@warning,@error,@succuss = $ivr.get_prompts(params)

		begin
			# Create array of DNIS values and filter SCAN results
			@stores,@stores_count,stores_names,@media_types,@request_id = $ivr.filtered_store_list(:create, {dnis_array: params.values})
			@stores_names = $ivr.get_store_headers(stores_names)

			files = S3_CLIENT.list_objects({bucket: S3_BUCKET, max_keys: 50})[:contents]
			@existing_files = Array.new
			files.each do |file|
				@existing_files.push(file['key'])
			end
			@existing_files.push("Add New File")
		rescue => e
			$app_logger.error "#{$ivr.html_logging_prefix(__method__,request,"ERROR")} #{e} | Redirecting to /error"
			redirect "/error?error=stores_bulk&value=#{e}"
		else
			$app_logger.debug "#{__method__} | Files : #{files} | Filtered List : #{@existing_files} | Store Headers : #{@stores_names} | Rendor bulk_edit"
			if @stores_count < 1
				redirect "/stores?error=no_stores_selected"
			end
			erb :bulk_edit
		end

		
	end

	post '/stores/edit' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"

		begin 
			if params['file_name'] == 'Add New File'
				redirect "/stores/recording/new?request_id=#{params['request_id']}&search=#{params['search']}"
			else
				result = $ivr.stores_edit(params)
			end
		rescue => e
			$app_logger.error "#{$ivr.html_logging_prefix(__method__,request,"ERROR")} #{e} | Redirecting to /error"
			redirect "/error?error=post_edit&value=#{e}"
		else		
			redirect "/stores/results?request_id=#{params['request_id']}"
		end
	
	end

	get '/stores/recording/new' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"
		@warning,@error,@succuss = $ivr.get_prompts(params)

		begin
			# Create array of DNIS values and filter SCAN results
			@stores,@stores_count,stores_names,@media_types = $ivr.filtered_store_list(:get, {request_id: params['request_id']})
			@stores_names = $ivr.get_store_headers(stores_names)			
			@request_id = params['request_id']
			@search = params['search']
		rescue => e
			puts "#{__method__} | Error : #{e}"
			$app_logger.error "#{$ivr.html_logging_prefix(__method__,request,"ERROR")} #{e} | Redirecting to /error"
			redirect "/error?error=rendor_recording_new&value=#{e.to_s}"			
		else
			$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"RENDOR")} recording_new.erb"		
			erb :recording_new			
		end
	end

	post '/stores/recording/call' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"
		@start_call = nil
		result = nil
		begin
			result = $ivr.recording_greeting(params['phone_number'],params['file_name'])
		rescue => e
			$app_logger.error "#{$ivr.html_logging_prefix(__method__,request,"ERROR")} #{e} | Redirecting to /error"
			redirect "/error?error=post_stores_recording_call&value=#{e}"
		else
			if result && result.has_key?(:conversation_uuid)
				if result[:status] == 'busy'
					redirect "/error?error=unable_to_connect&key=#{params['phone_number']}&value=#{result[:status]}"
				elsif result[:status] == 'failed_to_get_recording'
					redirect "/stores/recording/new?request_id=#{params['request_id']}&error=#{result[:status]}"
				else
					result = $ivr.stores_edit({'request_id' => params['request_id'], 'search' => params['search'], 'file_name' => params['file_name']})
					redirect "/stores/results?request_id=#{params['request_id']}"
				end
			end
		end
		200

	end

	post '/stores/recording/upload' do 
		puts "#{__method__} | Params : #{params}"
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"

		begin
			result = $ivr.upload_greeting(params) if params.has_key?('file_data')
		rescue => e
			$app_logger.error "#{$ivr.html_logging_prefix(__method__,request,"ERROR")} #{e} | Redirecting to /error"			
			redirect "/stores/recording/new?request_id=#{params['request_id']}&error=post_stores_recording_upload&value=#{e}"
		else
			if result.has_key?(:error)
				$app_logger.error "#{$ivr.html_logging_prefix(__method__,request,"ERROR")} #{result[:error]} | Redirecting back with Error"			
				redirect "/stores/recording/new?request_id=#{params['request_id']}&error=#{result[:error]}&value=#{result[:value]}"

			elsif result.has_key?(:status)
				r = $ivr.stores_edit({'request_id' => params['request_id'], 'search' => params['search'], 'file_name' => params['file_name']})
				redirect "/stores/results?request_id=#{params['request_id']}&success=file_upload_success&key=#{r[:stores_updated]}&value=#{r[:store_or_stores]}"
			end
		end

		200

	end

	get '/stores/results' do 
		$app_logger.info "#{$ivr.html_logging_prefix(__method__,request,"ACCESS")} Params : #{params}"
		@warning,@error,@succuss = $ivr.get_prompts(params)

		begin
			@stores,@stores_count,stores_names,@media_types = $ivr.filtered_store_list(:get, {request_id: params['request_id']})
			@stores_names = $ivr.get_store_headers(stores_names)
			@request_id = params['request_id']
		rescue => e
			$app_logger.error "#{$ivr.html_logging_prefix(__method__,request,"ERROR")} #{e} | Redirecting to /error"
			redirect "/error?error=stores_results&value=#{e}"
		else
			EditStoresDB.delete_edit_request(params['request_id'])
		end

		erb :bulk_result
	end

	get '/recordings' do 
		@recordings = AWS_DB.scan_table(AWS_REC_TABLE)[:items]
		@recordings_count = @recordings.length
		@recordings_names = @recordings[0].keys

		$app_logger.info "#{__method__} | AWS_DB | recordings #{@recordings}"
		$app_logger.info "#{__method__} | AWS_DB | recordings_names #{@recordings_names}"
		erb :recordings				
	end

	get '/clear/data' do
		$app_logger.info "#{__method__} | Destroy dB | #{EditStoresDB.destroy}"
	end

	get '/test' do 
		erb :test
	end
end
