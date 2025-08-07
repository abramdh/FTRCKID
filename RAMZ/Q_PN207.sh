#!/bin/bash

# Tampilkan banner judul secara nyata (bukan komentar)
echo "🟣═════════════════════════════════════════════════════════════════════🟣"
echo "             🚀 Google Cloud Dataflow Setup - By RAMZ DH 🧠             "
echo "🟣═════════════════════════════════════════════════════════════════════🟣"

# 🗺️ SET REGION
gcloud config set compute/region us-west1

# 🪣 TASK 1: Create Cloud Storage Bucket
echo "📦 Creating Cloud Storage bucket..."
PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="${PROJECT_ID}-bucket"
gsutil mb -c standard -l US -p $PROJECT_ID gs://${BUCKET_NAME}
echo "✅ Bucket created: gs://${BUCKET_NAME}"

# 🐳 TASK 2-3: Run Apache Beam inside Docker
echo "🐍 Launching Docker container with Python 3.9..."
docker run -it --env PROJECT_ID=$PROJECT_ID --env BUCKET=${BUCKET_NAME} python:3.9 /bin/bash -c "

  echo '🐍 Installing Apache Beam...'
  pip install --quiet 'apache-beam[gcp]'==2.42.0

  echo '🧪 Running wordcount locally (DirectRunner)...'
  python -m apache_beam.examples.wordcount --output output.txt

  echo '📄 Local wordcount result:'
  cat output.txt

  echo '🚀 Submitting remote Dataflow job to GCP...'
  python -m apache_beam.examples.wordcount \\
    --project \$PROJECT_ID \\
    --runner DataflowRunner \\
    --staging_location gs://\$BUCKET/staging \\
    --temp_location gs://\$BUCKET/temp \\
    --output gs://\$BUCKET/results/output \\
    --region us-west1
"

echo "✅ Script completed! Check Dataflow and GCS bucket results on Google Cloud Console 🌐"
