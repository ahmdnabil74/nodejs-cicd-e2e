#!/bin/bash

# Variables
cluster_name="cluster-1-test"
region="eu-central-1" #Make sure it is the same in the terraform variables
aws_id="AWS_ID"
repo_name="nodejs-app"  # name of ecr repo to store image docker 
# If you wanna change the repository name make sure you change it in the k8s/app.yml (Image name) 
image_name="$aws_id.dkr.ecr.$region.amazonaws.com/$repo_name:latest"
dbsecret="db-password-secret" # to store password for database in k8s secret
namespace="nodejs-app" # namespace in k8s which will be used to deploy the application and monitoring tools
# End Variables

# NodePorts
APP_NODEPORT=32000
PROMETHEUS_NODEPORT=30900
GRAFANA_NODEPORT=30090
ALERT_NODEPORT=30910



# update helm repos
helm repo update

# create the cluster
echo "--------------------Creating EKS--------------------" # 
echo "--------------------Creating ECR--------------------" #
echo "--------------------Creating EBS--------------------" #
cd terraform && \  
terraform init  # get tf and install provider like as aws 
terraform apply -auto-approve # # create all requirments for the cluster and monitoring tools and ingress
cd .. # get back to root directory

# update kubeconfig
echo "--------------------Update Kubeconfig--------------------"
aws eks update-kubeconfig --name $cluster_name --region $region 
# update kubeconfig to be able to connect to the cluster with kubectl and deploy the application and monitoring tools

# remove preious docker images
echo "--------------------Remove Previous build--------------------"
docker rmi -f $image_name || true # delete previous image if exist to avoid build error because of same tag

# build new docker image with new tag
echo "--------------------Build new Image--------------------"
docker build -t $image_name .

#ECR Login
echo "--------------------Login to ECR--------------------"
aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $aws_id.dkr.ecr.$region.amazonaws.com
#get password from aws and login to ecr to be able to push the image in ecr repository 


# push the latest build to dockerhub
echo "--------------------Pushing Docker Image--------------------"
docker push $image_name
# push image on ecr repository to be able to pull it in k8s and deploy the application

# create namespace
echo "--------------------creating Namespace--------------------"
kubectl create ns $namespace || true
#create namespace in k8s to deploy the application and monitoring tools in it to be organized and separated from other namespaces

# Generate database password
echo "--------------------Generate DB password--------------------"
PASSWORD=$(openssl rand -base64 12)
# create random password for database to be used in the application and store it in k8s secret to be used in the deployment of the application and keep it secure

# Store the generated password in k8s secrets
echo "--------------------Store the generated password in k8s secret--------------------"
kubectl create secret generic $dbsecret --from-literal=DB_PASSWORD=$PASSWORD --namespace=$namespace || true
# create k8s secret to store the generated password for database to be used in the deployment of the application and keep it secure

# Deploy the application
echo "--------------------Deploy App--------------------"
kubectl apply -n $namespace -f k8s
# deploy the application in k8s using the deployment and service yaml files in the k8s directory and specify the namespace to deploy it in

# Wait for application to be deployed
echo "--------------------Wait for all pods to be running--------------------"
kubectl wait --for=condition=Ready pod -l app=nodejs-app -n $namespace --timeout=120s
#sleep 60s


# Get Node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Get ingress URL
#echo "--------------------Ingress URL--------------------"
#kubectl get ingress nodejs-app-ingress -n $namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# get the ingress URL to be able to access the application and monitoring tools through it and add CNAME record in the domain to point to this URL to access the application and monitoring tools through the domain

# Display URLs
echo " "
echo "--------------------Application URL--------------------"
echo "http://$NODE_IP:$APP_NODEPORT"
echo "--------------------Prometheus URL--------------------"
echo "http://$NODE_IP:$PROMETHEUS_NODEPORT"
echo "--------------------Grafana URL--------------------"
echo "http://$NODE_IP:$GRAFANA_NODEPORT"
echo "--------------------Alertmanager URL--------------------"
echo "http://$NODE_IP:$ALERT_NODEPORT"
echo " "



#delete ingress and domain
#define stable NodePorts for services
#display URLs using Node IP and NodePort
#use kubectl wait instead of sleep for better reliability
#delete DNS instructions and CNAME instructions

#echo -e "1. Navigate to your domain cpanel.\n2. Look for Zone Editor.\n3. Add CNAME Record to your domain.\n4. In the name type domain for your application.\n5. In the CNAME Record paste the ingress URL."


################################################################################







