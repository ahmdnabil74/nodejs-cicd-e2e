############################
# DATA
############################
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

############################
# LOCALS
############################
locals {
  cluster_name = "${var.name_prefix}-${var.environment}"

  autoscaler_service_account_namespace = "kube-system"
  autoscaler_service_account_name      = "cluster-autoscaler-aws"

  admin_user_map_users = [
    for admin_user in var.admin_users : {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${admin_user}"
      username = admin_user
      groups   = ["system:masters"]
    }
  ]

  developer_user_map_users = [
    for developer_user in var.developer_users : {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${developer_user}"
      username = developer_user
      groups   = ["${var.name_prefix}-developers"]
    }
  ]
}

############################
# NAT EIP
############################
resource "aws_eip" "nat_gw_elastic_ip" {
  vpc = true
  tags = {
    Name = "${local.cluster_name}-nat-eip"
  }
}

############################
# EBS CSI ROLE (IRSA)
############################
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Environment = "test"
  }
}

############################
# EKS CLUSTER
############################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.29"

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  ################ ADDONS ################
  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  ################ NODE GROUP ################
eks_managed_node_groups = {
  system = {
    min_size     = 1
    max_size     = 3
    desired_size = 2

    instance_types = var.asg_sys_instance_types
    subnet_ids     = module.vpc.private_subnets

    iam_role_additional_policies = [
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
      "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    ]

    labels = {
      Environment = "test"
    }

    tags = {
      "kubernetes.io/cluster/${local.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"           = "true"
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
    }
  }
}

  ################ TAGS ################
  tags = {
    Environment = "test"
    Terraform   = "true"
  }
}

############################
# CLUSTER DATA
############################
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

############################
# AUTH (aws-auth configmap)
############################
module "eks_auth" {
  source = "aidanmelen/eks-auth/aws"
  eks    = module.eks

  map_users = concat(local.admin_user_map_users, local.developer_user_map_users)
}

############################
# AUTOSCALER IAM ROLE
############################
module "iam_assumable_role_admin" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "~> 4.0"

  create_role = true
  role_name   = "${local.cluster_name}-cluster-autoscaler"

  provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  role_policy_arns = [
    aws_iam_policy.cluster_autoscaler.arn
  ]

  oidc_fully_qualified_subjects = [
    "system:serviceaccount:${local.autoscaler_service_account_namespace}:${local.autoscaler_service_account_name}"
  ]
}

############################
# AUTOSCALER POLICY
############################
resource "aws_iam_policy" "cluster_autoscaler" {
  name_prefix = "${local.cluster_name}-cluster-autoscaler"

  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:*",
      "ec2:Describe*"
    ]
    resources = ["*"]
  }
}

############################
# HELM AUTOSCALER
############################
resource "helm_release" "cluster-autoscaler" {
  depends_on = [module.eks]

  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.29.0"

  timeout = 300
  wait    = true

  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_id
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = local.autoscaler_service_account_name
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role_admin.iam_role_arn
  }
}