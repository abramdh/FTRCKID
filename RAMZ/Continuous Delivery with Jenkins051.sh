#!/bin/bash
# run_all_lab.sh
# Automate Tasks 1-12 from the "continuous-deployment-on-kubernetes" lab.
# Intended for Google Cloud Shell.
set -euo pipefail
IFS=$'\n\t'

echo "=== Jenkins + Canary Deployment FULL AUTOMATION SCRIPT ==="
echo "Read the notes in the script header before running (costs may apply)."
read -p "Masukkan Project ID: " PROJECT_ID
read -p "Masukkan Compute Zone (misal: us-central1-c): " ZONE
read -p "Masukkan GitHub Email (untuk git config): " GITHUB_EMAIL
read -p "Masukkan GitHub Username: " GITHUB_USERNAME
read -p "Masukkan nama repo yang akan dibuat di GitHub (mis: default): " GITHUB_REPO
read -p "Apakah lanjut? (y/n) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Dibatalkan."
  exit 1
fi

echo
echo "=== Set gcloud project & zone ==="
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/zone "${ZONE}"

echo
echo "=== Task 1: Download source code ==="
gsutil cp gs://spls/gsp051/continuous-deployment-on-kubernetes.zip .
unzip -o continuous-deployment-on-kubernetes.zip
cd continuous-deployment-on-kubernetes

echo
echo "=== Task 2: Provision Kubernetes cluster for Jenkins ==="
echo "Creating GKE cluster 'jenkins-cd' (this may take several minutes)..."
gcloud container clusters create jenkins-cd \
  --num-nodes 2 \
  --machine-type e2-standard-2 \
  --zone "${ZONE}" \
  --scopes "https://www.googleapis.com/auth/source.read_write,cloud-platform"

echo "Getting credentials..."
gcloud container clusters get-credentials jenkins-cd --zone "${ZONE}"
kubectl cluster-info

echo
echo "=== Task 3: Install Helm & add repo ==="
# install helm is usually present in Cloud Shell; if not, install quickly
if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found, installing..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm repo add jenkins https://charts.jenkins.io || true
helm repo update

echo
echo "=== Task 4: Install Jenkins via Helm (with provided values.yaml) ==="
# We'll install chart from provided folder in repo
helm install cd jenkins/jenkins -f jenkins/values.yaml --wait

# wait until pod is Running
echo "Waiting for Jenkins pod to be ready..."
kubectl wait --for=condition=Ready pod -l "app.kubernetes.io/instance=cd,app.kubernetes.io/component=jenkins-master" --timeout=600s || true
kubectl get pods

echo
echo "=== Create clusterrolebinding for Jenkins to deploy ==="
kubectl create clusterrolebinding jenkins-deploy --clusterrole=cluster-admin --serviceaccount=default:cd-jenkins || true

echo
echo "=== Port-forward Jenkins master to localhost:8080 (background) ==="
POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/component=jenkins-master" -l "app.kubernetes.io/instance=cd" -o jsonpath="{.items[0].metadata.name}")
echo "Jenkins pod: $POD_NAME"
# start in background
kubectl port-forward "$POD_NAME" 8080:8080 > /tmp/jenkins-port-forward.log 2>&1 &
PF_PID=$!
echo "kubectl port-forward pid: $PF_PID"
# wait for Jenkins UI to become available
echo "Menunggu Jenkins UI (http://localhost:8080) siap..."
for i in {1..60}; do
  if curl -sSf http://localhost:8080/ >/dev/null 2>&1; then
    echo "Jenkins tersedia."
    break
  fi
  sleep 3
done

echo
echo "=== Task 5: Retrieve admin password ==="
JENKINS_SECRET=$(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" || true)
if [[ -n "$JENKINS_SECRET" ]]; then
  JENKINS_ADMIN_PASSWORD=$(printf "%s" "$JENKINS_SECRET" | base64 --decode)
  echo "Jenkins admin password retrieved."
else
  echo "Gagal ambil secret cd-jenkins; menunggu lagi..."
  JENKINS_ADMIN_PASSWORD=$(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)
fi
echo "Admin password is loaded into variable (not printed)."

echo
echo "=== Task 6: (prepare) - create SSH key for GitHub and known_hosts ==="
cd sample-app || (echo "sample-app folder not found"; exit 1)
# generate key pair without passphrase (overwrites if exists)
SSH_KEY_FILE=./id_github
ssh-keygen -t rsa -b 4096 -N '' -f "$SSH_KEY_FILE" -C "${GITHUB_EMAIL}" || true
chmod 600 "$SSH_KEY_FILE"
echo "Generated SSH key at $SSH_KEY_FILE and $SSH_KEY_FILE.pub"

# create known_hosts file for github
ssh-keyscan -t rsa github.com > known_hosts.github || true
chmod 644 known_hosts.github

echo
echo "=== Task 8: Create GitHub repo & push sample-app ==="
# gh CLI may not be installed — install helper
if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Installing..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update && sudo apt install gh -y
fi

echo "Please authenticate gh with GitHub in opened browser (follow prompts)."
gh auth login --web
echo "gh authenticated as: $(gh api user -q .login)"

# create repo if not exists
if gh repo view "${GITHUB_USERNAME}/${GITHUB_REPO}" >/dev/null 2>&1; then
  echo "Repo ${GITHUB_USERNAME}/${GITHUB_REPO} already exists."
else
  echo "Creating GitHub repo ${GITHUB_REPO} (private)..."
  gh repo create "${GITHUB_USERNAME}/${GITHUB_REPO}" --private --confirm
fi

# push sample-app content
git init || true
git config user.email "${GITHUB_EMAIL}"
git config user.name "${GITHUB_USERNAME}"
git config credential.helper gcloud.sh || true
# ensure remote set to SSH URL for Jenkins to use
REMOTE_SSH="git@github.com:${GITHUB_USERNAME}/${GITHUB_REPO}.git"
git remote remove origin || true
git remote add origin "$REMOTE_SSH"
git add .
git commit -m "Initial commit from automation script" || true
git push -u origin master --force

echo
echo "=== Add generated public SSH key as Deploy Key to GitHub repo (so Jenkins can clone) ==="
PUBKEY_CONTENT=$(cat "${SSH_KEY_FILE}.pub")
# create a deploy key using gh api (title unique)
DEPLOY_KEY_TITLE="jenkins-lab-key-$(date +%s)"
gh api --method POST -H "Accept: application/vnd.github+json" /repos/"${GITHUB_USERNAME}"/"${GITHUB_REPO}"/keys \
  -f title="$DEPLOY_KEY_TITLE" -f key="$PUBKEY_CONTENT" -f read_only=false
echo "Deploy key added to repo."

echo
echo "=== Task 8 (continued): Add SSH key as Jenkins credential and Google SA cred ==="
# We need to create credentials in Jenkins: (1) SSH credential (private key), (2) Google Service Account JSON (from gcloud)
# Create Jenkins credentials via Groovy script sent to /script using basic auth (admin:password)
JENKINS_URL="http://localhost:8080"
ADMIN_USER="admin"
ADMIN_PASS="${JENKINS_ADMIN_PASSWORD}"

# obtain crumb for CSRF
CRUMB_XML=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${JENKINS_URL}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)") || true
if [[ -z "$CRUMB_XML" ]]; then
  echo "Gagal ambil Jenkins crumb. Mencoba tanpa crumb..."
  CRUMB_HEADER=""
else
  CRUMB_HEADER="-H ${CRUMB_XML}"
fi

# Prepare Groovy script to create SSH credential and Git known_hosts
SSH_PRIVATE_KEY_CONTENT=$(sed -e ':a' -e 'N' -e '$!ba' -e 's/$/\\n/g' "$SSH_KEY_FILE")
GROOVY_CREATE_CREDENTIALS=$(cat <<EOF
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.plugins.credentials.domains.*
import hudson.util.Secret
def domain = Domain.global()
def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

// SSH Username with private key
def sshId = "qwiklabs-ssh-key"
def sshUser = "${GITHUB_USERNAME}"
def privateKey = """${SSH_PRIVATE_KEY_CONTENT}"""
def sshCred = new BasicSSHUserPrivateKey(
  CredentialsScope.GLOBAL,
  sshId,
  sshUser,
  new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(privateKey),
  "",
  "Auto-created SSH key for lab"
)
store.addCredentials(domain, sshCred)

// Optionally add known hosts as a string credential (text)
def knownHostsId = "github-known-hosts"
def knownHosts = """$(sed -e ':a' -e 'N' -e '$!ba' -e 's/$/\\n/g' known_hosts.github)"""
def kh = new StringCredentialsImpl(CredentialsScope.GLOBAL, knownHostsId, "GitHub Known Hosts", Secret.fromString(knownHosts))
store.addCredentials(domain, kh)

println("Created SSH and known-hosts credentials: " + sshId + ", " + knownHostsId)
EOF
)

# Post groovy to Jenkins script console
echo "Posting Groovy script to Jenkins to create credentials..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST "${JENKINS_URL}/scriptText" \
  -d "script=${GROOVY_CREATE_CREDENTIALS}" ${CRUMB_XML:+-H "$CRUMB_XML"} > /tmp/groovy_result.txt || true
echo "Groovy result stored in /tmp/groovy_result.txt"
echo "Contents:"
tail -n +1 /tmp/groovy_result.txt

echo
echo "=== Configure Jenkins Kubernetes Cloud (so agents can run) via Groovy ==="
# create a basic Kubernetes cloud config pointing to current cluster and the service account
GROOVY_K8S_CLOUD=$(cat <<'EOF'
import jenkins.model.*
import org.csanchez.jenkins.plugins.kubernetes.*
import com.nirima.jenkins.plugins.docker.strategy.*

def instance = Jenkins.getInstance()
def cloudName = "kubernetes-cloud-auto"
def serverUrl = "https://kubernetes.default" // internal cluster URL; Jenkins in cluster will use in-cluster config
def namespace = "default"
def credentialsId = "" // use in-cluster service account for Jenkins master so leave empty if using in-cluster
def containerCapStr = "10"
def kubCloud = new KubernetesCloud(cloudName)
kubCloud.setServerUrl(serverUrl)
kubCloud.setNamespace(namespace)
kubCloud.setContainerCapStr(containerCapStr)
kubCloud.setSkipTlsVerify(true)
instance.clouds.add(kubCloud)
instance.save()
println("Added Kubernetes cloud: " + cloudName)
EOF
)
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST "${JENKINS_URL}/scriptText" \
  -d "script=${GROOVY_K8S_CLOUD}" ${CRUMB_XML:+-H "$CRUMB_XML"} > /tmp/groovy_k8s_result.txt || true
echo "Kubernetes cloud groovy result appended."

echo
echo "=== Task 8: Configure Multibranch Pipeline via Groovy ==="
# Create Multibranch Pipeline job pointing to git@github.com:USER/REPO.git
JENKINS_JOB_GROOVY=$(cat <<EOF
import jenkins.model.*
import org.jenkinsci.plugins.workflow.multibranch.*
import jenkins.branch.*
import com.cloudbees.plugins.credentials.*
import jenkins.model.Jenkins
def instance = Jenkins.getInstance()

def repoUrl = "git@github.com:${GITHUB_USERNAME}/${GITHUB_REPO}.git"
def jobName = "sample-app"
def existing = instance.getItem(jobName)
if (existing != null) {
  println("Job exists, deleting and recreating.")
  existing.delete()
}

import org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject
def project = new WorkflowMultiBranchProject(instance, jobName)
def scmSource = new jenkins.plugins.git.GitSCMSource(null, repoUrl, "${GITHUB_USERNAME}", "", "", false)
project.getSourcesList().add(new BranchSource(scmSource))
instance.add(project, jobName)
project.save()
println("Created multibranch Project: " + jobName)
EOF
)
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST "${JENKINS_URL}/scriptText" \
  -d "script=${JENKINS_JOB_GROOVY}" ${CRUMB_XML:+-H "$CRUMB_XML"} > /tmp/groovy_job_result.txt || true
echo "Multibranch pipeline groovy result stored."

echo
echo "=== Task 9 & 10: Create development branch, modify Jenkinsfile & site, commit, push ==="
# create branch new-feature, change Jenkinsfile PROJECT_ID and CLUSTER_ZONE, modify html.go + main.go as lab asks (simple sed)
git checkout -b new-feature || git switch -c new-feature
# replace tokens in Jenkinsfile
if grep -q "REPLACE_WITH_YOUR_PROJECT_ID" Jenkinsfile 2>/dev/null || true; then
  sed -i "s/REPLACE_WITH_YOUR_PROJECT_ID/${PROJECT_ID}/g" Jenkinsfile || true
fi
# set CLUSTER_ZONE if present
if grep -q "CLUSTER_ZONE" Jenkinsfile 2>/dev/null || true; then
  sed -i "s/CLUSTER_ZONE=.*/CLUSTER_ZONE=${ZONE}/g" Jenkinsfile || true
fi

# simple modification: change color from blue to orange in html.go (lab instruction)
if [ -f html.go ]; then
  sed -i "s/blue/orange/g" html.go || true
fi
git add Jenkinsfile html.go main.go || true
git commit -m "Version 2.0.0 - automated changes" || true
git push origin new-feature -u

echo
echo "=== Start kubectl proxy in background for dev branch test ==="
kubectl proxy > /tmp/kubectl-proxy.log 2>&1 &
KPROXY_PID=$!
sleep 3

# attempt to curl the dev service (may fail if Jenkins hasn't deployed yet)
echo "Attempting to access new-feature service via kubectl proxy (may take time until Jenkins deploys)"
curl -sSf http://localhost:8001/api/v1/namespaces/new-feature/services/gceme-frontend:80/proxy/version || true

echo
echo "=== Trigger Jenkins scan to detect new branch (via Jenkins API) ==="
# trigger indexing of the multibranch project
echo "Triggering indexing by invoking job scan (if available)..."
# Attempt to find job and trigger indexing
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X POST "${JENKINS_URL}/job/sample-app/indexing/" ${CRUMB_XML:+-H "$CRUMB_XML"} || true

echo
echo "=== Wait for Jenkins jobs to run & for canary to be deployed ==="
echo "This can take several minutes. Monitoring logs is recommended."
echo "We'll wait a moderate time and then try to apply k8s manifests for production/canary (Task 7)."

sleep 30

echo
echo "=== Task 7 (deploy app): create production namespace + apply manifests ==="
kubectl create ns production || true
kubectl apply -f k8s/production -n production
kubectl apply -f k8s/canary -n production
kubectl apply -f k8s/services -n production

echo "Scale production frontend to 4 replicas"
kubectl scale deployment gceme-frontend-production -n production --replicas=4 || true

echo "Check pods (frontend + backend)"
kubectl get pods -n production -l app=gceme -l role=frontend || true
kubectl get pods -n production -l app=gceme -l role=backend || true

echo
echo "=== Retrieve external IP for frontend (may take a few minutes to get LB IP) ==="
echo "Waiting up to 5 minutes for external IP..."
for i in {1..30}; do
  FRONTEND_IP=$(kubectl get service gceme-frontend -n production -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null || true)
  if [[ -n "$FRONTEND_IP" ]]; then
    echo "Frontend IP: $FRONTEND_IP"
    break
  fi
  sleep 10
done
if [[ -z "${FRONTEND_IP:-}" ]]; then
  echo "Belum mendapat external IP. Periksa 'kubectl get svc -n production' nanti."
else
  echo "Testing /version endpoint (loop 10x):"
  for i in {1..10}; do curl -s http://$FRONTEND_IP/version || true; sleep 1; done
fi

echo
echo "=== Task 11: Create canary branch and push ==="
git checkout -b canary || git switch -c canary
git push origin canary -u || true
echo "Pushed canary branch. Jenkins should pick it up."

echo
echo "=== Task 12: Merge canary to master (simulate deploy to production) ==="
git checkout master || git switch master || git checkout -b master
git merge --no-edit canary || true
git push origin master || true
echo "Merged canary into master and pushed. Jenkins master pipeline should run."

echo
echo "=== DONE ==="
echo "Script finished. Summary:"
echo " - Jenkins UI available at http://localhost:8080 (access via Cloud Shell or open port-forward)."
echo " - Jenkins admin password saved in variable JENKINS_ADMIN_PASSWORD (not printed)."
echo " - GitHub repo: git@github.com:${GITHUB_USERNAME}/${GITHUB_REPO}.git"
echo " - Frontend Service IP (if assigned): ${FRONTEND_IP:-<pending>}"
echo
echo "Important next steps / troubleshooting tips:"
echo " - If multibranch jobs didn't run: open Jenkins UI -> sample-app -> scan repository or trigger branch indexing."
echo " - If Jenkins Groovy script failed: check /tmp/groovy_result.txt and /tmp/groovy_job_result.txt for details."
echo " - If load balancer external IP not assigned: run 'kubectl get svc -n production' and wait (cloud provider may need time)."
echo
echo "Have fun! Jika mau, aku bisa bantu debug error spesifik (copy-paste output)."
