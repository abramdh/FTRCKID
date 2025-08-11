#!/bin/bash
# ===========================
# Qwiklabs VPC, Bastion, NAT Setup Script
# Region & Zone: Ditentukan User
# ===========================

read -p "Masukkan REGION (misalnya: us-east4): " REGION
read -p "Masukkan ZONE (misalnya: us-east4-c): " ZONE

BUCKET_NAME="bucket-$(date +%s)"

echo "=== Membuat VPC network ==="
gcloud compute networks create privatenet \
  --subnet-mode=custom

echo "=== Membuat subnet ==="
gcloud compute networks subnets create privatenet-subnet \
  --network=privatenet \
  --region=$REGION \
  --range=10.130.0.0/20

echo "=== Membuat firewall rule allow SSH ==="
gcloud compute firewall-rules create privatenet-allow-ssh \
  --network=privatenet \
  --allow=tcp:22 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=allow-ssh

echo "=== Membuat VM internal tanpa external IP ==="
gcloud compute instances create vm-internal \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --subnet=privatenet-subnet \
  --no-address \
  --tags=allow-ssh

echo "=== Membuat bastion host dengan external IP ==="
gcloud compute instances create vm-bastion \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --subnet=privatenet-subnet \
  --tags=allow-ssh \
  --scopes=compute-rw

echo "=== Membuat Cloud Storage bucket ==="
gcloud storage buckets create gs://$BUCKET_NAME \
  --location=US \
  --default-storage-class=MULTI_REGIONAL

echo "=== Menyalin file image ke bucket ==="
gsutil cp gs://cloud-training/gcpnet/private/access.png gs://$BUCKET_NAME

echo "=== Mengaktifkan Private Google Access untuk subnet ==="
gcloud compute networks subnets update privatenet-subnet \
  --region=$REGION \
  --enable-private-ip-google-access

echo "=== Membuat Cloud NAT + Router ==="
gcloud compute routers create nat-router \
  --network=privatenet \
  --region=$REGION

gcloud compute routers nats create nat-config \
  --router=nat-router \
  --region=$REGION \
  --nat-all-subnet-ip-ranges \
  --auto-allocate-nat-external-ips

echo "=== Mengaktifkan logging NAT untuk Translation dan Errors ==="
gcloud compute routers nats update nat-config \
  --router=nat-router \
  --region=$REGION \
  --enable-logging \
  --log-filter=ALL

echo "=== Selesai! ==="
echo "Bucket yang digunakan: $BUCKET_NAME"
echo "VM internal: vm-internal"
echo "VM bastion: vm-bastion"
