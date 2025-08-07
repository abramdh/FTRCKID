#!/bin/bash

# Tampilkan banner judul secara nyata (bukan komentar)
echo "🟣═════════════════════════════════════════════════════════════════════🟣"
echo "             🚀 Google Cloud Dataflow Setup - By RAMZ DH 🧠             "
echo "🟣═════════════════════════════════════════════════════════════════════🟣"

# 👉 Prompt for project ID and bucket name
echo "🔧 Setting up your Google Cloud Dataflow environment!"
read -p "📝 Enter your GCP Project ID: " PROJECT_ID
read -p "🪣 Enter a unique GCS Bucket Name (e.g. my-unique-bucket): " BUCKET_NAME

# 🌍 Set default region
echo "🌍 Setting compute region to us-west1..."
gcloud config set compute/region us-west1

# ☁️ Create Cloud Storage bucket
echo "📦 Creating Cloud Storage bucket: gs://$BUCKET_NAME"
gsutil mb -l us -b on -c STANDARD gs://$BUCKET_NAME

# 🐳 Run Python 3.9 Docker container with Apache Beam
echo "🐳 Launching Docker container with Python 3.9 and Apache Beam..."
docker run -it -e DEVSHELL_PROJECT_ID=$PROJECT_ID --rm python:3.9 /bin/bash -c '
  echo "📦 Installing Apache Beam..." &&
  pip install "apache-beam[gcp]"==2.42.0 &&
  echo "📄 Running local example: WordCount" &&
  python -m apache_beam.examples.wordcount --output wordcount-output &&
  echo "📁 Output files:" &&
  ls wordcount-output* &&
  echo "📖 Output content:" &&
  cat wordcount-output*
'

# 🌐 Set BUCKET env var for remote job
BUCKET=gs://$BUCKET_NAME

# 🚀 Run remote Dataflow job using DataflowRunner
echo "🚀 Submitting remote Dataflow job to GCP..."
python -m apache_beam.examples.wordcount \
  --project $PROJECT_ID \
  --runner DataflowRunner \
  --staging_location $BUCKET/staging \
  --temp_location $BUCKET/temp \
  --output $BUCKET/results/output \
  --region us-west1

echo "✅ Dataflow job submitted successfully!"
echo "🔍 You can monitor your job in the GCP Console → Dataflow section."
