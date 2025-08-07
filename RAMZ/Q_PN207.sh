#!/bin/bash

# Tampilkan banner judul secara nyata (bukan komentar)
echo "🟣═════════════════════════════════════════════════════════════════════🟣"
echo "             🚀 Google Cloud Dataflow Setup - By RAMZ DH 🧠             "
echo "🟣═════════════════════════════════════════════════════════════════════🟣"

# Set region and project
REGION="us-west1"
gcloud config set compute/region $REGION
PROJECT_ID=$(gcloud config get-value project)

# Create bucket
BUCKET_NAME="${PROJECT_ID}-bucket"
echo "📦 Creating GCS Bucket: gs://${BUCKET_NAME}"
gsutil mb -p $PROJECT_ID -c STANDARD -l us -b on gs://${BUCKET_NAME}/

# Mount working directory to Docker container
echo "🐳 Running Docker container with Apache Beam installed..."

docker run --rm -v "$PWD":/app -w /app -e DEVSHELL_PROJECT_ID=$PROJECT_ID python:3.9 bash -c "
  pip install 'apache-beam[gcp]'==2.42.0 && \
  echo '📊 Running local WordCount...' && \
  python -m apache_beam.examples.wordcount --output output.txt && \
  echo '📂 Local WordCount output:' && \
  cat output.txt && \
  echo '☁️ Submitting remote WordCount job to Dataflow...' && \
  python -m apache_beam.examples.wordcount \
    --project $DEVSHELL_PROJECT_ID \
    --runner DataflowRunner \
    --staging_location gs://${BUCKET_NAME}/staging \
    --temp_location gs://${BUCKET_NAME}/temp \
    --output gs://${BUCKET_NAME}/results/output \
    --region $REGION
"

echo "✅ Done! Check Cloud Console > Dataflow to monitor your job 🎯"
echo "Made with 💜 by RAMZ DH"


