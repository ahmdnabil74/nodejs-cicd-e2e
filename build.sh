#!/bin/bash

# ================= Variables =================
cluster_name="cluster-1-test"
region="eu-central-1"
aws_id="649126925327"
repo_name="nodejs-app"

image_name="$aws_id.dkr.ecr.$region.amazonaws.com/$repo_name:latest"

dbsecret="db-password-secret"
namespace="nodejs-app"

APP_NODEPORT="30080"
PROMETHEUS_NODEPORT=30900
GRAFANA_NODEPORT=30090
ALERT_NODEPORT=30910

# ================= Start =================
echo "==================== START ===================="

# update helm
helm repo update

# ================= CLEAN OLD =================
echo "--------------------Cleaning Old Resources--------------------"

kubectl delete namespace $namespace --ignore-not-found
kubectl delete secret $dbsecret -n $namespace --ignore-not-found

# optional (clean terraform)
cd terraform

echo "Destroy old infra..."
terraform destroy -auto-approve || true

echo "Apply new infra..."
terraform init
terraform apply -auto-approve

cd ..

# ================= KUBECONFIG =================
echo "--------------------Update Kubeconfig--------------------"
aws eks update-kubeconfig --name $cluster_name --region $region

# ================= WAIT FOR NODES =================
echo "--------------------Waiting for Nodes--------------------"

for i in {1..30}; do
  NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

  if [ "$NODE_COUNT" -gt 0 ]; then
    echo "Nodes are ready ✅"
    break
  fi

  echo "Waiting for nodes..."
  sleep 10
done

# لو مفيش nodes
if [ "$NODE_COUNT" -eq 0 ]; then
  echo "❌ No nodes available. Check EKS Node Group!"
  exit 1
fi

# ================= DOCKER =================
echo "--------------------Docker Build--------------------"

docker rmi -f $image_name || true
docker build -t $image_name .

echo "--------------------Login to ECR--------------------"
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $aws_id.dkr.ecr.$region.amazonaws.com

echo "--------------------Push Image--------------------"
docker push $image_name

# ================= K8S =================
echo "--------------------Create Namespace--------------------"
kubectl create ns $namespace --dry-run=client -o yaml | kubectl apply -f -

echo "--------------------Create Secret--------------------"
PASSWORD=$(openssl rand -base64 12)

kubectl create secret generic $dbsecret \
  --from-literal=DB_PASSWORD=$PASSWORD \
  --namespace=$namespace \
  --dry-run=client -o yaml | kubectl apply -f -

# ================= DEPLOY =================
echo "--------------------Deploy App--------------------"
kubectl apply -n $namespace -f k8s

# ================= WAIT PODS =================
echo "--------------------Waiting for Pods--------------------"
kubectl wait --for=condition=Ready pod -l app=nodejs-app -n $namespace --timeout=180s

# ================= GET NODE IP =================
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# ================= OUTPUT =================
echo ""
echo "==================== URLs ===================="
echo "App:          http://$NODE_IP:$APP_NODEPORT"
echo "Prometheus:   http://$NODE_IP:$PROMETHEUS_NODEPORT"
echo "Grafana:      http://$NODE_IP:$GRAFANA_NODEPORT"
echo "Alertmanager: http://$NODE_IP:$ALERT_NODEPORT"
echo "============================================="


#delete ingress and domain
#define stable NodePorts for services
#display URLs using Node IP and NodePort
#use kubectl wait instead of sleep for better reliability
#delete DNS instructions and CNAME instructions

#echo -e "1. Navigate to your domain cpanel.\n2. Look for Zone Editor.\n3. Add CNAME Record to your domain.\n4. In the name type domain for your application.\n5. In the CNAME Record paste the ingress URL."


################################################################################







