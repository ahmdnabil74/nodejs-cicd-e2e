
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"
 
  name = "${local.cluster_name}-vpc"
  cidr = var.main_network_block # block of main network 
  azs  = data.aws_availability_zones.available.names
  # distribute network on all avz


  private_subnets = ["10.0.0.0/20", "10.0.16.0/20"]

  public_subnets = ["10.0.128.0/20", "10.0.144.0/20"]

#  enable_nat_gateway           = true 
  #enable pods in private subnets to conenct with internet 
#  single_nat_gateway           = true 
  one_nat_gateway_per_az       = false
  create_database_subnet_group = false
  enable_dns_hostnames         = true
  reuse_nat_ips                = true
 # external_nat_ip_ids          = [aws_eip.nat_gw_elastic_ip.id]

#  public_subnet_tags = {
 #   "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  #  "kubernetes.io/role/elb"                      = "1"
  #}

  #private_subnet_tags = {
   # "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    #"kubernetes.io/role/internal-elb"             = "1"
  #}

  tags = {
    Terraform   = "true"
    Environment = "test"
  }
}
