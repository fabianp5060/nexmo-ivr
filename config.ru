#\ -p 9294 -o 0.0.0.0
require_relative 'app'
require_relative 'setup/aws_config'

#Auto Build AWS Info
ok_to_build_aws = false

#AWS Config - App Specific
PORT = 9294 #Update 1st line of file as well
DNS_NAME = "demo#{PORT.to_s[-1]}-lb.petesweb.io"

#AWS Config - AWS Environement Specific
SUBNETS = ["subnet-987775fc","subnet-284dd170"]
SECURITY_GROUPS = ["sg-070cab9793082c962"]
VPC_ID = "vpc-fb0fea9c"
SSL_CERT_ARN = "arn:aws:acm:us-west-2:313211040717:certificate/16284a6f-4794-4dbb-bb3c-21970241d43e"
DNS_HOSTING_ZONE = "Z1NFCBW8070W5J"
AWS1 = "i-08a6f7823672a143c"


# When starting app, configure AWS for load balancer, listeners, target groups and update dns
if ok_to_build_aws
	load_balancer_arn,target_group_arn = AWSConfig.create_aws_configuration(
		PORT,
		SUBNETS,
		SECURITY_GROUPS,
		VPC_ID,
		SSL_CERT_ARN,
		DNS_NAME,
		DNS_HOSTING_ZONE,
		AWS1
	)
end
# Run sintatra app
run MyApp

# When shuting down app, delete previously configured AWS stuff
at_exit do 
	AWSConfig.remove_aws_configuration(load_balancer_arn,target_group_arn) if ok_to_build_aws
end


