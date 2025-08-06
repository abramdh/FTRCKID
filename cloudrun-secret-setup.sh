#!/bin/bash

# Stop on any error
set -e

PROJECT_ID="qwiklabs-gcp-01-7e85351c5fed"
REGION="us-west1"
SECRET_ID="arcade-secret"
SECRET_VALUE="t0ps3cr3t!"

echo "🔧 Setting project configuration..."
gcloud config set project $PROJECT_ID
gcloud config set run/region $REGION

echo "✅ Enabling necessary APIs..."
gcloud services enable secretmanager.googleapis.com run.googleapis.com artifactregistry.googleapis.com

echo "🔐 Creating secret..."
gcloud secrets create $SECRET_ID --replication-policy=automatic || echo "Secret already exists"
echo -n "$SECRET_VALUE" | gcloud secrets versions add $SECRET_ID --data-file=-

echo "✅ Setup completed."
