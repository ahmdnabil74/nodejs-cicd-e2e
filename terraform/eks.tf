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
  tags = {
    Name        = "${local.cluster_name}-nat-eip"
    Terraform   = "true"
    Environment = "test"
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
    Terraform   = "true"
    Environment = "test"
  }
}

############################
# EKS CLUSTER
############################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  cluster_name                    = local.cluster_name
  cluster_version                 = "1.30"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  enable_irsa = true

  create_cloudwatch_log_group = false

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
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  ################ SECURITY GROUPS ################
  cluster_security_group_additional_rules = {
    ingress_nodes_8443_tcp = {
      description                = "Node groups to cluster API via port 8443"
      protocol                   = "tcp"
      from_port                  = 8443
      to_port                    = 8443
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # ✅ NodePort: السماح للـ traffic الخارجي على بورتات NodePort (30000-32767)
    ingress_nodeport = {
      description      = "Allow external traffic via NodePort range"
      protocol         = "tcp"
      from_port        = 30000
      to_port          = 32767
      type             = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  ################ NODE GROUP ################
  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

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
        Terraform                                          = "true"
        Environment                                        = "test"
        "kubernetes.io/cluster/${local.cluster_name}"      = "owned"
        "k8s.io/cluster-autoscaler/enabled"               = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      }
    }
  }

  ################ TAGS ################
  tags = {
    Terraform   = "true"
    Environment = "test"
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

  create_role  = true
  role_name    = "${local.cluster_name}-cluster-autoscaler"
  provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  role_policy_arns = [
    aws_iam_policy.cluster_autoscaler.arn
  ]

  oidc_fully_qualified_subjects = [
    "system:serviceaccount:${local.autoscaler_service_account_namespace}:${local.autoscaler_service_account_name}"
  ]

  tags = {
    Owner           = split("/", data.aws_caller_identity.current.arn)[1]
    AutoTag_Creator = data.aws_caller_identity.current.arn
  }
}

############################
# AUTOSCALER POLICY
############################
resource "aws_iam_policy" "cluster_autoscaler" {
  name_prefix = "${local.cluster_name}-cluster-autoscaler"
  description = "EKS cluster-autoscaler policy for cluster ${module.eks.cluster_id}"
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "clusterAutoscalerAll"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "clusterAutoscalerOwn"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${module.eks.cluster_id}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

############################
# HELM AUTOSCALER
############################
resource "helm_release" "cluster-autoscaler" {
  name             = "cluster-autoscaler"
  namespace        = local.autoscaler_service_account_namespace
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = "9.29.0"
  create_namespace = false
  timeout          = 300
  wait             = true
  depends_on = [module.eks]
  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "rbac.create"
    value = true
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = local.autoscaler_service_account_name
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role_admin.iam_role_arn
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_id
  }

  set {
    name  = "autoDiscovery.enabled"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-local-storage"
    value = "false"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  set {
    name  = "extraArgs.scale-down-enabled"
    value = "true"
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "5m"
  }
}