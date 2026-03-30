Node.js DevOps Project (NodePort Deployment)

This repository contains scripts and Kubernetes manifests for deploying the Node.js application with a Postgres database on an AWS EKS cluster. The deployment uses NodePorts instead of an Ingress and custom domain.

The project includes:

AWS EKS cluster deployment using Terraform
Docker image build and push to ECR
Postgres database setup with K8s Secrets
NodePort services for:
Node.js app
Prometheus
Grafana
Alertmanager
Continuous deployment pipeline with GitHub Actions
Prerequisites

Make sure the following tools are installed and configured:

AWS CLI with proper permissions
Docker
kubectl
Terraform
Helm
Git
K9s (for DB port forwarding)
BeeKeeper Studio (for Postgres database access)
Setup
Update Variables in build.sh:
cluster_name="cluster-1-test"
region="eu-central-1"
aws_id="YOUR_AWS_ACCOUNT_ID"
repo_name="nodejs-app"
dbsecret="db-password-secret"
namespace="nodejs-app"

# NodePorts
APP_NODEPORT=32000
PROMETHEUS_NODEPORT=30900
GRAFANA_NODEPORT=30090
ALERT_NODEPORT=30910
Make the deployment script executable:
chmod +x build.sh
Run the deployment script:
./build.sh
Accessing Services

After deployment, use the Node IP and NodePort for each service:

Node.js App:       http://<NODE_IP>:32000
Prometheus:        http://<NODE_IP>:30900
Grafana:           http://<NODE_IP>:30090
Alertmanager:      http://<NODE_IP>:30910

The script automatically displays these URLs after deployment.

Database Access
Port forward the Postgres service using k9s:
# Open k9s and type:
:svc
# Highlight postgres-service and press Shift+F
Connect using BeeKeeper Studio:
Host: localhost
Port: 5432
Username: from K8s env variable
Password: retrieve from K8s secret db-password-secret
Example SQL to create a table:
CREATE TABLE posts (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO posts (title, body) VALUES ('First Post', 'This is the first post.');
CI/CD
Continuous Integration (CI): builds Docker image and pushes to ECR.
Continuous Deployment (CD): deploys manifests to EKS using GitHub Actions.

GitHub Secrets required:

AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
KUBECONFIG_SECRET (base64-encoded Kubeconfig)

Use the included github_secrets.sh script to automate setting secrets.

Destroying Infrastructure

Run destroy.sh to clean up:

chmod +x destroy.sh
./destroy.sh

This deletes Docker images from ECR, Kubernetes resources, and AWS infrastructure created by Terraform.

Notes
NodePorts are stable, so you can access services directly via Node IP.
No Ingress or domain setup required.
Always verify AWS region, account ID, and namespace in the scripts.
