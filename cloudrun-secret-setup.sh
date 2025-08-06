#!/bin/bash

# Prompt manual input dari user
read -p "Masukkan Project ID: " PROJECT_ID
read -p "Masukkan Region (contoh: us-east1): " REGION
read -p "Masukkan Nama Secret: " SECRET_NAME
read -p "Masukkan Nilai Secret: " SECRET_VALUE
read -p "Masukkan Nama Cloud Run Service: " SERVICE_NAME
read -p "Masukkan Nama Repository (Artifact Registry): " REPO_NAME
read -p "Masukkan Nama Container Image: " IMAGE_NAME
read -p "Masukkan Nama Service Account: " SERVICE_ACCOUNT_NAME

# Konfigurasi project dan region
echo "🔧 Mengatur konfigurasi GCP..."
gcloud config set project "$PROJECT_ID"
gcloud config set run/region "$REGION"

# Enable required APIs
echo "✅ Mengaktifkan API..."
gcloud services enable secretmanager.googleapis.com run.googleapis.com artifactregistry.googleapis.com

# Membuat secret
echo "🔐 Membuat secret di Secret Manager..."
gcloud secrets create "$SECRET_NAME" --replication-policy=automatic
echo -n "$SECRET_VALUE" | gcloud secrets versions add "$SECRET_NAME" --data-file=-

# Membuat file app.py
cat <<EOF > app.py
import os
from flask import Flask, jsonify
from google.cloud import secretmanager
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

secret_manager_client = secretmanager.SecretManagerServiceClient()
PROJECT_ID = "${PROJECT_ID}"
SECRET_ID = "${SECRET_NAME}"

@app.route('/')
def get_secret():
    if not SECRET_ID or not PROJECT_ID:
        return jsonify({"error": "Missing config"}), 500

    name = f"projects/{PROJECT_ID}/secrets/{SECRET_ID}/versions/latest"
    try:
        response = secret_manager_client.access_secret_version(request={"name": name})
        secret_payload = response.payload.data.decode("UTF-8")
        return jsonify({"secret_id": SECRET_ID, "secret_value": secret_payload})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

# Membuat requirements.txt
echo -e "Flask==3.*\ngoogle-cloud-secret-manager==2.*" > requirements.txt

# Membuat Dockerfile
cat <<EOF > Dockerfile
FROM python:3.9-slim-buster
WORKDIR /app
COPY requirements.txt .
RUN pip3 install -r requirements.txt
COPY . .
CMD ["python3", "app.py"]
EOF

# Buat repo Artifact Registry
echo "📦 Membuat Artifact Registry Docker repository..."
gcloud artifacts repositories create "$REPO_NAME" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker repository"

# Build dan tag image
echo "🐳 Membuat container image..."
docker build -t "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest" .

# Push image ke Artifact Registry
echo "🚀 Push image ke Artifact Registry..."
docker push "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest"

# Membuat Service Account
echo "👤 Membuat Service Account..."
gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
  --display-name="Service Account for Cloud Run" \
  --description="Cloud Run access Secret Manager"

# Beri akses ke Secret Manager
echo "🔑 Memberikan akses Secret Manager ke service account..."
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Deploy ke Cloud Run
echo "☁️ Deploy ke Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --image="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest" \
  --region="$REGION" \
  --set-secrets SECRET_ENV_VAR="$SECRET_NAME:latest" \
  --service-account="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
  --allow-unauthenticated

# Ambil URL Cloud Run
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region="$REGION" --format='value(status.url)')
echo "✅ Deployment selesai. Akses aplikasi Anda di: $SERVICE_URL"
