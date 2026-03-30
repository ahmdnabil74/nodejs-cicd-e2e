resource "helm_release" "cluster-autoscaler" {
  name             = "cluster-autoscaler"
  namespace        = local.autoscaler_service_account_namespace
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = "9.10.7"
  create_namespace = false

  set = [
    { name = "cloudProvider", value = "aws" },
    { name = "awsRegion", value = var.region },
    { name = "rbac.create", value = true },
    { name = "rbac.serviceAccount.name", value = local.autoscaler_service_account_name },
    { name = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = module.iam_assumable_role_admin.iam_role_arn },
    { name = "autoDiscovery.clusterName", value = module.eks.cluster_id },
    { name = "autoDiscovery.enabled", value = "true" },
    { name = "extraArgs.skip-nodes-with-local-storage", value = "false" },
    { name = "extraArgs.skip-nodes-with-system-pods", value = "false" },
    { name = "extraArgs.scale-down-enabled", value = "true" },
    { name = "extraArgs.scale-down-unneeded-time", value = "5m" },
  ]
}