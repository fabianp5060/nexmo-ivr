require 'aws-sdk-elasticloadbalancingv2'
require 'aws-sdk-route53'



class AWSConfig
	@client = Aws::ElasticLoadBalancingV2::Client.new

	def self.create_aws_configuration(port,subnets_array,security_groups_array,vpc_id,ssl_cert_arn,dns_name,dns_hosting_zone,ec2)
		puts "Creating AWS Load Balancer"

		load_balancer_arn,lb_dns_name,lb_dns_hosted_zone 	= create_lb(port,subnets_array,security_groups_array)
		target_group_arn 									= create_target_group(port,vpc_id)
		target_group_result 								= register_targets_to_target_group(target_group_arn,ec2)
		listener_result 									= create_listener(load_balancer_arn,target_group_arn,ssl_cert_arn)
		dns_result 											= update_dns_record(lb_dns_name,lb_dns_hosted_zone,dns_name,dns_hosting_zone)

		puts "Created Loadbalancer: https://#{DNS_NAME}:#{PORT}"
		return load_balancer_arn,target_group_arn
	end

	def self.remove_aws_configuration(load_balancer_arn,target_group_arn)

		puts "Destroying AWS Infrastructure"
		puts "load_balancer_arn: #{load_balancer_arn}"
		puts "target_group_arn: #{target_group_arn}"
		lb_result = delete_lb(load_balancer_arn)


		tg_result = delete_target_groups(target_group_arn)
		puts "Completed:\nLB Result: #{lb_result}\nTG Result: #{tg_result}"

		return lb_result,tg_result
	end

	def self.create_lb(port,subnets_array,security_groups_array)
		#################################################
		# Create Load Balancer
		#################################################
		lb = @client.create_load_balancer({
			name: "petesweb-io-#{PORT}",
			subnets: subnets_array,
			security_groups: security_groups_array,
			type: "application",
			ip_address_type: "ipv4",
			scheme: "internet-facing"
		})


		load_balancer_arn = lb[:load_balancers][0][:load_balancer_arn]
		lb_dns_name = lb[:load_balancers][0][:dns_name]
		lb_dns_hosted_zone = lb[:load_balancers][0][:canonical_hosted_zone_id]

		puts "# Created Load Balancer"
		puts " -> Load Balancer DNS: #{lb_dns_name}"

		return load_balancer_arn,lb_dns_name,lb_dns_hosted_zone
	end

	def self.delete_lb(load_balancer_arn)
		#################################################
		# Delete Load balancer
		#################################################

		resp = @client.delete_load_balancer({
			load_balancer_arn: load_balancer_arn
		})

		puts "# Deleted Load Balancer: #{resp}"
		# Need to give LB time to delete before deleting Target Groups
		c = 0
		while c < 5 do 
			print "."
			sleep(1)
			c += 1
		end
		print "\n"

		return resp
	end

	def self.create_target_group(port,vpc_id)
		#################################################
		# Create Target Group
		#################################################
		resp = @client.create_target_group({
			name: "petesweb-ec2-#{PORT}",
			protocol: "HTTP",
			port: PORT,
			vpc_id: vpc_id,
			health_check_protocol: "HTTP",
			health_check_port: "traffic-port",
			health_check_enabled: true,
			health_check_interval_seconds: 30,
			health_check_timeout_seconds: 5,
			healthy_threshold_count: 2,
			unhealthy_threshold_count: 2,
			health_check_path: "/",
			matcher: {
				http_code: "200"
			}
		})

		target_group_arn = resp[:target_groups][0][:target_group_arn]

		puts "# Created Target Groups"
		puts " -> Target Group ARN: #{target_group_arn}"

		return target_group_arn
	end

	def self.register_targets_to_target_group(target_group_arn,ec2)
		#################################################
		# Register Target
		#################################################
		resp = @client.register_targets({
			target_group_arn: target_group_arn,
			targets: [
				{
					id: ec2
				}
			]
		})

		puts "# Registering Targets"
		puts " -> #{resp}"	

		return resp
	end

	def self.delete_target_groups(target_group_arn)
		#################################################
		# Delete Target Group
		#################################################
		attempt_count = 0
		max_attempts = 3
		begin
			attempt_count += 1
			resp = @client.delete_target_group({
			  target_group_arn: target_group_arn
			})
		rescue Aws::ElasticLoadBalancingV2::Errors::ResourceInUse => e
			puts "ERROR: #{e}, retrying in 5 seconds"
			sleep 5
			retry if attempt_count < max_attempts
		else
			puts "Deleted Target Group:\n#{resp}\n---"
		end
	end

	def self.create_listener(load_balancer_arn,target_group_arn,ssl_cert_arn)
		#################################################
		# Create Listener
		#################################################
		listener = @client.create_listener({
			certificates:[
				certificate_arn: ssl_cert_arn
			],
			default_actions:[{
				type: "forward",
				target_group_arn: target_group_arn
			}],
			load_balancer_arn: load_balancer_arn,
			port: 443,
			protocol: "HTTPS",
			ssl_policy: "ELBSecurityPolicy-2016-08"
		})

		puts "# Creating Listener"
		puts " -> #{listener[:listeners][0][:protocol]}/#{listener[:listeners][0][:port]}"	
		puts "Done Creating Listener"

		return listener
	end

	def self.update_dns_record(lb_dns_name,lb_dns_hosted_zone,dns_name,dns_hosting_zone)
		#################################################
		# Update Route53 Record 
		#################################################
		dns_client = Aws::Route53::Client.new
		resp = dns_client.change_resource_record_sets({
			change_batch: {
				changes: [
					action: "UPSERT",
					resource_record_set: {
						alias_target: {
							dns_name: lb_dns_name,
							evaluate_target_health: false,
							hosted_zone_id: lb_dns_hosted_zone
						},
						name: DNS_NAME,
						type: "A"				
					},
				],
				comment: "updated zonefile for demo",
			},
			hosted_zone_id: dns_hosting_zone
		})

		puts "# Updated DNS Record for #{dns_name}: #{resp[:change_info][:status]}"
		return resp
	end
end







