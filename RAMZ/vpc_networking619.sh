#!/bin/bash


echo "Masukkan REGION 1 (contoh: us-west1):"
read REGION1
echo "Masukkan ZONE 1 (contoh: us-west1-a):"
read ZONE1
echo "Masukkan REGION 2 (contoh: us-east4):"
read REGION2
echo "Masukkan ZONE 2 (contoh: us-east4-b):"
read ZONE2
echo "Masukkan SHARED_SECRET untuk VPN:"
read SHARED_SECRET

echo "=== Task 1: Membuat VPC vpc-demo ==="
gcloud compute networks create vpc-demo --subnet-mode custom

echo "=== Membuat Subnets ==="
gcloud beta compute networks subnets create vpc-demo-subnet1 \
  --network vpc-demo --range 10.1.1.0/24 --region "$REGION1"

gcloud beta compute networks subnets create vpc-demo-subnet2 \
  --network vpc-demo --range 10.2.1.0/24 --region "$REGION2"

echo "=== Firewall Rules untuk vpc-demo ==="
gcloud compute firewall-rules create vpc-demo-allow-internal \
  --network vpc-demo --allow tcp:0-65535,udp:0-65535,icmp \
  --source-ranges 10.0.0.0/8

gcloud compute firewall-rules create vpc-demo-allow-ssh-icmp \
  --network vpc-demo --allow tcp:22,icmp

echo "=== Membuat VM Instances di vpc-demo ==="
gcloud compute instances create vpc-demo-instance1 \
  --zone "$ZONE1" --subnet vpc-demo-subnet1 --machine-type e2-medium

gcloud compute instances create vpc-demo-instance2 \
  --zone "$ZONE2" --subnet vpc-demo-subnet2 --machine-type e2-medium

echo "=== Task 2: Simulasi On-Premises (VPC on-prem) ==="
gcloud compute networks create on-prem --subnet-mode custom

gcloud beta compute networks subnets create on-prem-subnet1 \
  --network on-prem --range 192.168.1.0/24 --region "$REGION1"

echo "=== Firewall Rules untuk on-prem ==="
gcloud compute firewall-rules create on-prem-allow-internal \
  --network on-prem --allow tcp:0-65535,udp:0-65535,icmp \
  --source-ranges 192.168.0.0/16

gcloud compute firewall-rules create on-prem-allow-ssh-icmp \
  --network on-prem --allow tcp:22,icmp

echo "=== Membuat VM Instance di on-prem ==="
gcloud compute instances create on-prem-instance1 \
  --zone "$ZONE1" --subnet on-prem-subnet1 --machine-type e2-medium

echo "=== Task 3: Membuat HA-VPN Gateway & Router ==="
gcloud beta compute vpn-gateways create vpc-demo-vpn-gw1 \
  --network vpc-demo --region "$REGION1"

gcloud beta compute vpn-gateways create on-prem-vpn-gw1 \
  --network on-prem --region "$REGION1"

gcloud compute routers create vpc-demo-router1 \
  --region "$REGION1" --network vpc-demo --asn 65001

gcloud compute routers create on-prem-router1 \
  --region "$REGION1" --network on-prem --asn 65002

echo "=== Membuat VPN Tunnels ==="
gcloud beta compute vpn-tunnels create vpc-demo-tunnel0 \
  --peer-gcp-gateway on-prem-vpn-gw1 --region "$REGION1" \
  --ike-version 2 --shared-secret "$SHARED_SECRET" \
  --router vpc-demo-router1 --vpn-gateway vpc-demo-vpn-gw1 --interface 0

gcloud beta compute vpn-tunnels create vpc-demo-tunnel1 \
  --peer-gcp-gateway on-prem-vpn-gw1 --region "$REGION1" \
  --ike-version 2 --shared-secret "$SHARED_SECRET" \
  --router vpc-demo-router1 --vpn-gateway vpc-demo-vpn-gw1 --interface 1

gcloud beta compute vpn-tunnels create on-prem-tunnel0 \
  --peer-gcp-gateway vpc-demo-vpn-gw1 --region "$REGION1" \
  --ike-version 2 --shared-secret "$SHARED_SECRET" \
  --router on-prem-router1 --vpn-gateway on-prem-vpn-gw1 --interface 0

gcloud beta compute vpn-tunnels create on-prem-tunnel1 \
  --peer-gcp-gateway vpc-demo-vpn-gw1 --region "$REGION1" \
  --ike-version 2 --shared-secret "$SHARED_SECRET" \
  --router on-prem-router1 --vpn-gateway on-prem-vpn-gw1 --interface 1

echo "=== BGP Peering untuk vpc-demo ==="
gcloud compute routers add-interface vpc-demo-router1 \
  --interface-name if-tunnel0-to-on-prem --ip-address 169.254.0.1 \
  --mask-length 30 --vpn-tunnel vpc-demo-tunnel0 --region "$REGION1"

gcloud compute routers add-bgp-peer vpc-demo-router1 \
  --peer-name bgp-on-prem-tunnel0 --interface if-tunnel0-to-on-prem \
  --peer-ip-address 169.254.0.2 --peer-asn 65002 --region "$REGION1"

gcloud compute routers add-interface vpc-demo-router1 \
  --interface-name if-tunnel1-to-on-prem --ip-address 169.254.1.1 \
  --mask-length 30 --vpn-tunnel vpc-demo-tunnel1 --region "$REGION1"

gcloud compute routers add-bgp-peer vpc-demo-router1 \
  --peer-name bgp-on-prem-tunnel1 --interface if-tunnel1-to-on-prem \
  --peer-ip-address 169.254.1.2 --peer-asn 65002 --region "$REGION1"

echo "=== BGP Peering untuk on-prem ==="
gcloud compute routers add-interface on-prem-router1 \
  --interface-name if-tunnel0-to-vpc-demo --ip-address 169.254.0.2 \
  --mask-length 30 --vpn-tunnel on-prem-tunnel0 --region "$REGION1"

gcloud compute routers add-bgp-peer on-prem-router1 \
  --peer-name bgp-vpc-demo-tunnel0 --interface if-tunnel0-to-vpc-demo \
  --peer-ip-address 169.254.0.1 --peer-asn 65001 --region "$REGION1"

gcloud compute routers add-interface on-prem-router1 \
  --interface-name if-tunnel1-to-vpc-demo --ip-address 169.254.1.2 \
  --mask-length 30 --vpn-tunnel on-prem-tunnel1 --region "$REGION1"

gcloud compute routers add-bgp-peer on-prem-router1 \
  --peer-name bgp-vpc-demo-tunnel1 --interface if-tunnel1-to-vpc-demo \
  --peer-ip-address 169.254.1.1 --peer-asn 65001 --region "$REGION1"

echo "=== Firewall tambahan untuk komunikasi cross-VPC ==="
gcloud compute firewall-rules create vpc-demo-allow-subnets-from-on-prem \
  --network vpc-demo --allow tcp,udp,icmp \
  --source-ranges 192.168.1.0/24

gcloud compute firewall-rules create on-prem-allow-subnets-from-vpc-demo \
  --network on-prem --allow tcp,udp,icmp \
  --source-ranges 10.1.1.0/24,10.2.1.0/24

echo "=== Mengaktifkan Global Routing di vpc-demo ==="
gcloud compute networks update vpc-demo --bgp-routing-mode GLOBAL

echo "=== Selesai! Silakan cek tunnel status ==="
gcloud beta compute vpn-tunnels list
