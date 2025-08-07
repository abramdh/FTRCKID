#!/bin/bash

# Set your Google Cloud project ID here
PROJECT_ID="your-project-id"

# Task 1: Create VPC Network
gcloud compute networks create xall-vpc--vpc-01 \
  --description="XYZ-all VPC network = Standard VPC network - 01" \
  --project="$PROJECT_ID" \
  --subnet-mode=custom \
  --bgp-routing-mode=global \
  --mtu=1460

# Task 2: Create Subnet
gcloud compute networks subnets create xgl-subnet--cerps-bau-nonprd--be1-01 \
  --description="XYZ-Global subnet = CERPS-BaU-NonProd - Belgium 1 (GCP) - 01" \
  --project="$PROJECT_ID" \
  --network=xall-vpc--vpc-01 \
  --region=us-east1 \
  --range=10.1.1.0/24 \
  --enable-private-ip-google-access \
  --enable-flow-logs

# Task 3: Firewall Rules - User Access
gcloud compute firewall-rules create xall-vpc--vpc-01--xall-fw--user--a--linux--v01 \
  --description="xall-vpc--vpc-01 - XYZ-all firewall rule = User access - ALLOW standard linux access - version 01" \
  --project="$PROJECT_ID" \
  --network=xall-vpc--vpc-01 \
  --priority=1000 \
  --direction=ingress \
  --action=allow \
  --target-tags=xall-vpc--vpc-01--xall-fw--user--a--linux--v01 \
  --source-ranges=0.0.0.0/0 \
  --rules=tcp:22,icmp

gcloud compute firewall-rules create xall-vpc--vpc-01--xall-fw--user--a--windows--v01 \
  --description="xall-vpc--vpc-01 - XYZ-all firewall rule = User access - ALLOW standard windows access - version 01" \
  --project="$PROJECT_ID" \
  --network=xall-vpc--vpc-01 \
  --priority=1000 \
  --direction=ingress \
  --action=allow \
  --target-tags=xall-vpc--vpc-01--xall-fw--user--a--windows--v01 \
  --source-ranges=0.0.0.0/0 \
  --rules=tcp:3389,icmp

gcloud compute firewall-rules create xall-vpc--vpc-01--xall-fw--user--a--sapgui--v01 \
  --description="xall-vpc--vpc-01 - XYZ-all firewall rule = User access - ALLOW SAPGUI access - version 01" \
  --project="$PROJECT_ID" \
  --network=xall-vpc--vpc-01 \
  --priority=1000 \
  --direction=ingress \
  --action=allow \
  --target-tags=xall-vpc--vpc-01--xall-fw--user--a--sapgui--v01 \
  --source-ranges=0.0.0.0/0 \
  --rules=tcp:3200-3299,tcp:3600-3699

gcloud compute firewall-rules create xall-vpc--vpc-01--xall-fw--user--a--sap-fiori--v01 \
  --description="xall-vpc--vpc-01 - XYZ-all firewall rule = User access - ALLOW SAP Fiori access - version 01" \
  --project="$PROJECT_ID" \
  --network=xall-vpc--vpc-01 \
  --priority=1000 \
  --direction=ingress \
  --action=allow \
  --target-tags=xall-vpc--vpc-01--xall-fw--user--a--sap-fiori--v01 \
  --source-ranges=0.0.0.0/0 \
  --rules=tcp:80,tcp:8000-8099,tcp:443,tcp:4300-44300

# Task 4: Firewall Rules - Environment Access
gcloud compute firewall-rules create xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-env--v01 \
  --description="xall-vpc--vpc-01 - XYZ-Global firewall rule = CERPS-BaU-Dev - ALLOW environment wide access - version 01" \
  --project="$PROJECT_ID" \
  --network=xall-vpc--vpc-01 \
  --priority=1000 \
  --direction=ingress \
  --action=allow \
  --target-tags=xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-env--v01 \
  --source-tags=xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-env--v01 \
  --rules=tcp:3200-3299,tcp:3300-3399,tcp:4800-4899,tcp:80,tcp:8000-8099,tcp:443,tcp:44300-44399,tcp:3600-3699,tcp:8100-8199,tcp:44400-44499,tcp:50000-59999,tcp:30000-39999,tcp:4300-4399,tcp:40000-49999,tcp:1128-1129,tcp:5050,tcp:8000-8499,tcp:515,icmp

# Task 5: Firewall Rules - System Access
gcloud compute firewall-rules create xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-ds4--v01 \
  --description="xall-vpc--vpc-01 - XYZ-Global firewall rule = CERPS-BaU-Dev - ALLOW SAP S4 (DS4) system wide access - version 01" \
  --project="$PROJECT_ID" \
  --network=xall-vpc--vpc-01 \
  --priority=1000 \
  --direction=ingress \
  --action=allow \
  --target-tags=xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-ds4--v01 \
  --source-tags=xall-vpc--vpc-01--xgl-fw--cerps-bau-dev--a-ds4--v01 \
  --rules=tcp,udp,icmp
