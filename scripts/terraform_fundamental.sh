#!/bin/bash
echo -e "\033[0;35mDibuat oleh RAMZDH\033[0m"
echo "🔍 Verifying Terraform installation..."
terraform --version || { echo "❌ Terraform not installed!"; exit 1; }

read -p "Enter your Google Cloud Project ID: " PROJECT_ID
read -p "Enter desired zone (e.g. us-central1-f): " ZONE

gcloud config set project "$PROJECT_ID"
gcloud config set compute/zone "$ZONE"

echo "📝 Creating Terraform configuration file: instance.tf"
cat > instance.tf <<EOF
resource "google_compute_instance" "terraform" {
  project      = "${PROJECT_ID}"
  name         = "terraform"
  machine_type = "e2-medium"
  zone         = "${ZONE}"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }
}
EOF

echo "📁 Listing *.tf files in current directory:"
ls *.tf

echo "🚀 Initializing Terraform..."
terraform init

echo "📊 Generating Terraform execution plan..."
terraform plan

echo "⚙️ Applying Terraform configuration..."
terraform apply -auto-approve

echo "✅ VM created successfully with Terraform!"
