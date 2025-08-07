#!/bin/bash

# Tampilkan banner judul secara nyata (bukan komentar)
echo "🟣═════════════════════════════════════════════════════════════════════🟣"
echo "             🚀 Google Cloud Dataflow Setup - By RAMZ DH 🧠             "
echo "🟣═════════════════════════════════════════════════════════════════════🟣"

# Set region
REGION="us-west1"
gcloud config set compute/region $REGION

# Enable Dataflow API (manual step in GUI, so just remind user)
echo "🧠 Please make sure the Dataflow API is enabled via the Cloud Console."

# Create a GCS Bucket
PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="${PROJECT_ID}-bucket"
echo "📦 Creating bucket: gs://${BUCKET_NAME}..."
gsutil mb -p $PROJECT_ID -c STANDARD -l us -b on gs://${BUCKET_NAME}/

# Launch Docker container with Python 3.9
echo "🐳 Launching Python 3.9 Docker container..."
docker run -i -t -e DEVSHELL_PROJECT_ID=$PROJECT_ID python:3.9 /bin/bash <<'EOF'

# Inside container
echo "🐍 Installing Apache Beam SDK..."
pip install 'apache-beam[gcp]'==2.42.0

echo "✍️  Running local WordCount..."
python -m apache_beam.examples.wordcount --output output.txt

echo "📂 Listing output file..."
ls
echo "📖 Preview:"
cat output.txt

echo "🌐 Running WordCount remotely on Dataflow..."
export BUCKET=gs://${DEVSHELL_PROJECT_ID}-bucket
python -m apache_beam.examples.wordcount --project $DEVSHELL_PROJECT_ID \
  --runner DataflowRunner \
  --staging_location $BUCKET/staging \
  --temp_location $BUCKET/temp \
  --output $BUCKET/results/output \
  --region us-west1

echo "✅ Remote Dataflow job submitted. Check status in the Google Cloud Console."

EOF

