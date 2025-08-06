#!/bin/bash

# ===================================
# 💜 Code By RAMZ 💜 (with purple color)
# ===================================

PURPLE='\033[1;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}💜 Code By RAMZ 💜${NC}"

# Prompt for manual input
read -p "Enter your PROJECT_ID: " PROJECT_ID
read -p "Enter your REGION (e.g., us-east1): " REGION
read -p "Enter your SECRET_NAME: " SECRET_NAME
read -p "Enter your SECRET_VALUE: " SECRET_VALUE
read -p "Enter your SERVICE_NAME: " SERVICE_NAME
read -p "Enter your REPO_NAME: " REPO_NAME
read -p "Enter your IMAGE_NAME: " IMAGE_NAME
read -p "Enter your SERVICE_ACCOUNT_NAME: " SERVICE_ACCOUNT_NAME

# Set configuration
gcloud config set project $PROJECT_ID
gcloud config set run/region $REGION

# Enable required services
gcloud services enable secretmanager.googleapis.com run.googleapis.com artifactregistry.googleapis.com

# Create secret and add version
gcloud secrets create $SECRET_NAME --replication-policy=automatic
echo -n "$SECRET_VALUE" | gcloud secrets versions add $SECRET_NAME --data-file=-

# Create app.py
cat <<EOF > app.py
import os
from flask import Flask, jsonify
from google.cloud import secretmanager
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
secret_manager_client = secretmanager.SecretManagerServiceClient()

PROJECT_ID = "$PROJECT_ID"
SECRET_ID = "$SECRET_NAME"

@app.route('/')
def get_secret():
    if not SECRET_ID or not PROJECT_ID:
        logging.error("Missing config")
        return jsonify({"error": "Config missing"}), 500

    secret_version_name = f"projects/{PROJECT_ID}/secrets/{SECRET_ID}/versions/latest"
    try:
        logging.info(f"Accessing: {secret_version_name}")
        response = secret_manager_client.access_secret_version(request={"name": secret_version_name})
        secret_payload = response.payload.data.decode("UTF-8")
        return jsonify({"secret_id": SECRET_ID, "secret_value": secret_payload})
    except Exception as e:
        logging.error(f"Error: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

# Create requirements.txt
cat <<EOF > requirements.txt
Flask==3.*
google-cloud-secret-manager==2.*
EOF

# Create Dockerfile
cat <<EOF > Dockerfile
FROM python:3.9-slim-buster
WORKDIR /app
COPY requirements.txt .
RUN pip3 install -r requirements.txt
COPY . .
CMD ["python3", "app.py"]
EOF

# Create Artifact Registry
gcloud artifacts repositories create $REPO_NAME --repository-format=docker --location=$REGION --description="Docker repository" --quiet

# Build and push Docker image
docker build -t $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest .
docker push $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest

# Create Service Account
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
  --display-name="$SERVICE_ACCOUNT_NAME" \
  --description="Service account for Cloud Run app"

# Grant Secret Access
gcloud secrets add-iam-policy-binding $SECRET_NAME \
  --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Deploy to Cloud Run
gcloud run deploy $SERVICE_NAME \
  --image=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest \
  --region=$REGION \
  --set-secrets SECRET_ENV_VAR=$SECRET_NAME:latest \
  --service-account=$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com \
  --allow-unauthenticated

# Output URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format='value(status.url)')
echo -e "\nYour Cloud Run service is deployed at: ${PURPLE}$SERVICE_URL${NC}"
