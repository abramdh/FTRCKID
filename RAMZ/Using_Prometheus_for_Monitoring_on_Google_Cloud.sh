#!/bin/bash

echo "🟣═════════════════════════════════════════════════════════════════════🟣"
echo "             🚀 Using Prometheus For Monitor - By RAMZ DH 🧠             "
echo "🟣═════════════════════════════════════════════════════════════════════🟣"

PROJECT_ID="qwiklabs-gcp-02-a6e1ea75ffc6"
REGION="us-east1"
ZONE="us-east1-d"
REPO_NAME="docker-repo"
CLUSTER_NAME="gmp-cluster"
IMAGE_TAG="flask-telemetry:v1"
NAMESPACE="gmp-test"
APP_IMAGE="us-east1-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/flask-telemetry:v1"

gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud services enable container.googleapis.com artifactregistry.googleapis.com monitoring.googleapis.com

gcloud artifacts repositories create $REPO_NAME --repository-format=docker \
    --location=$REGION --description="Docker repository" --quiet

wget -q https://storage.googleapis.com/spls/gsp1024/flask_telemetry.zip
unzip -q flask_telemetry.zip
docker load -i flask_telemetry.tar

docker tag gcr.io/ops-demo-330920/flask_telemetry:61a2a7aabc7077ef474eb24f4b69faeab47deed9 $APP_IMAGE
docker push $APP_IMAGE

gcloud beta container clusters create $CLUSTER_NAME --num-nodes=1 --zone $ZONE --enable-managed-prometheus --quiet
gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE

kubectl create ns $NAMESPACE

wget -q https://storage.googleapis.com/spls/gsp1024/gmp_prom_setup.zip
unzip -q gmp_prom_setup.zip
cd gmp_prom_setup

sed -i "s|<ARTIFACT REGISTRY IMAGE NAME>|$APP_IMAGE|g" flask_deployment.yaml

kubectl -n $NAMESPACE apply -f flask_deployment.yaml
kubectl -n $NAMESPACE apply -f flask_service.yaml

echo "Waiting for external IP..."
while [[ -z "$(kubectl get svc -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')" ]]; do
  sleep 5
done
SERVICE_IP=$(kubectl get svc -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
echo "Service IP: $SERVICE_IP"

curl http://$SERVICE_IP/metrics || true

kubectl -n $NAMESPACE apply -f prom_deploy.yaml

timeout 120 bash -c -- "while true; do curl http://$SERVICE_IP; sleep $((RANDOM % 4)); done"

gcloud monitoring dashboards create --config='''{
  "category": "CUSTOM",
  "displayName": "Prometheus Dashboard Example",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "height": 4,
        "widget": {
          "title": "prometheus/flask_http_request_total/counter [MEAN]",
          "xyChart": {
            "chartOptions": {
              "mode": "COLOR"
            },
            "dataSets": [
              {
                "minAlignmentPeriod": "60s",
                "plotType": "LINE",
                "targetAxis": "Y1",
                "timeSeriesQuery": {
                  "apiSource": "DEFAULT_CLOUD",
                  "timeSeriesFilter": {
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_NONE",
                      "perSeriesAligner": "ALIGN_RATE"
                    },
                    "filter": "metric.type=\\"prometheus.googleapis.com/flask_http_request_total/counter\\" resource.type=\\"prometheus_target\\"",
                    "secondaryAggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["metric.label.\\"status\\""],
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ],
            "thresholds": [],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "y1Axis",
              "scale": "LINEAR"
            }
          }
        },
        "width": 6,
        "xPos": 0,
        "yPos": 0
      }
    ]
  }
}'''
