
#Deploy ArgoCD on EKS
echo "--------------------Deploy ArgoCD on EKS--------------------"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install ${RELEASE_NAME} argo/argo-cd
# install ArgoCD using Helm, you can customize the installation by providing additional parameters or values files as needed.
#add repo to helm charts of argo cd 
# install argo cd on cluster by name of my-argo-cd, you can change it as you want





#Change to LoadBalancer
echo "--------------------Change Argocd Service to LoadBalancer--------------------"
kubectl patch svc ${RELEASE_NAME}-argocd-server -n ${NAMESPACE} -p '{"spec": {"type": "LoadBalancer"}}'
#kubectl patch svc ${RELEASE_NAME}-argocd-server -n ${NAMESPACE} -p '{"spec": {"type": "NodePort"}}'
# by default, the ArgoCD server service is of type ClusterIP, which means it is only accessible within the cluster.
# By patching the service to type LoadBalancer, you are exposing it externally, allowing you to access the ArgoCD UI from outside the cluster.


#Sleep 10 seconds
echo "--------------------Creating External-IP--------------------"
sleep 10s

#Reveal Argocd URL
echo "--------------------Argocd Ex-URL--------------------"
kubectl get service ${RELEASE_NAME}-argocd-server -n ${NAMESPACE} | awk '{print $4}'
#get the external IP address of the ArgoCD server service, which is now exposed as a LoadBalancer. 
#This IP address can be used to access the ArgoCD UI from a web browser.
#extract original password for ArgoCD UI from the Kubernetes secret and decode it from base64 to get the actual password, 
#then save it to a file named argo-pass.txt for later use.


#Reveal ArgoCD Pass
echo "--------------------ArgoCD UI Password--------------------"
echo "Username: admin"
kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d > argo-pass.txt

################################################################################
################################################################################
################################################################################


#!/bin/bash

CLUSTER_NAME=cluster-1-test
NAMESPACE=default
REGION=eu-central-1
RELEASE_NAME=my-argo-cd

# Update kubeconfig
echo "--------------------Update kubeconfig--------------------"
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
#UPDATE KUBECONFIG TO ENABLE KUBECTL TO COONECT WITH THE CLUSTER

# Deploy ArgoCD using Helm
echo "--------------------Deploy ArgoCD--------------------"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install ${RELEASE_NAME} argo/argo-cd \
  --namespace ${NAMESPACE} \
  --create-namespace \
  --set server.service.type=NodePort
# install ArgoCD using Helm, you can customize the installation by providing additional parameters or values files as needed.
#add repo to helm charts of argo cd 
# install argo cd on cluster by name of my-argo-cd, you can change it as you want

# Wait for pods
echo "--------------------Waiting for ArgoCD pods--------------------"
kubectl wait --for=condition=available deployment/${RELEASE_NAME}-argocd-server \
  -n ${NAMESPACE} --timeout=120s

# Get NodePort
echo "--------------------Get NodePort--------------------"
NODE_PORT=$(kubectl get svc ${RELEASE_NAME}-argocd-server -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')

# Get Node IP (External or Internal)
echo "--------------------Get Node IP--------------------"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')

# Print URL
echo "--------------------ArgoCD URL--------------------"
echo "http://${NODE_IP}:${NODE_PORT}"

# Get Password
echo "--------------------ArgoCD Password--------------------"
echo "Username: admin"
kubectl -n ${NAMESPACE} get secret ${RELEASE_NAME}-argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo