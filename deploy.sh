#!/bin/bash
set -e

# --- CONFIGURATION ---
PROJECT_ID="your-gcp-project-id"
REGION="your-region" # e.g., us-central1
REPO="your-artifact-registry-repo"
IMAGE="your-image-name"
CLUSTER_NAME="your-gke-cluster"
K8S_MANIFEST="k8s/deployment.yaml"
SERVICE_ACCOUNT_KEY_PATH="path/to/your-service-account-key.json" # Path to your service account JSON key

# --- STEP 0: Check Required Tools ---
for cmd in gcloud kubectl mvn git; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd is not installed or not in PATH."
    exit 1
  fi
done

# --- STEP 1: Authenticate gcloud with Service Account ---
gcloud auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY_PATH"
gcloud config set project "$PROJECT_ID"

# --- STEP 2: Authenticate Docker  ---
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# --- STEP 3: Authenticate kubectl with GKE ---
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"

# --- STEP 4: Authenticate git ---
if ! git ls-remote &> /dev/null; then
  echo "Error: git authentication failed. Ensure credentials are available in CI/CD environment."
  exit 1
fi

# --- STEP 5: Get current commit SHA ---
COMMIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${COMMIT_SHA}"


# --- STEP 6: Build and push Docker image with Maven Jib ---
mvn compile jib:build -Dimage="$IMAGE_TAG"

# --- STEP 7: Update Kubernetes manifest with new image tag ---
cp "$K8S_MANIFEST" "${K8S_MANIFEST}.bak"
sed -i "s|IMAGE_PLACEHOLDER|$IMAGE_TAG|g" "$K8S_MANIFEST"

# --- STEP 8: Deploy to GKE ---
kubectl apply -f "$K8S_MANIFEST"

# --- STEP 9: Clean up (restore manifest) ---
mv "${K8S_MANIFEST}.bak" "$K8S_MANIFEST"

echo "Pipeline finished."
