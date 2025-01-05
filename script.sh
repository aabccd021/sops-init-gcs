#!/bin/bash
set -eu

echo_blue() {
  printf "\033[34mINFO:\033[0m %s\n" "$1"
}

project_id=""
service_account_name=""
bucket_name=""
secret_name=""
secret_file=""

while [ $# -gt 0 ]; do
  case "$1" in
  --project-id)
    project_id="$2"
    shift
    ;;
  --service-account-name)
    service_account_name="$2"
    shift
    ;;
  --bucket-name)
    bucket_name="$2"
    shift
    ;;
  --secret-name)
    secret_name="$2"
    shift
    ;;
  --secret-file)
    secret_file="$2"
    shift
    ;;
  *)
    echo_blue "Unknown argument: $1" >&2
    exit 1
    ;;
  esac
  shift
done

if [ -z "$project_id" ] || [ -z "$service_account_name" ] || [ -z "$bucket_name" ] || [ -z "$secret_name" ] || [ -z "$secret_file" ]; then
  echo_blue "Usage: $0 --project-id PROJECT_ID --service-account-name SERVICE_ACCOUNT_NAME --bucket-name BUCKET_NAME --secret-name SECRET_NAME --secret-file SECRET_FILE" >&2
  exit 1
fi

SOPS_AGE_KEY="${SOPS_AGE_KEY:-}"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-}"
if [ -z "$SOPS_AGE_KEY" ] && [ -z "$SOPS_AGE_KEY_FILE" ]; then
  echo_blue "Error: SOPS_AGE_KEY or SOPS_AGE_KEY_FILE environment variable is not set" >&2
  exit 1
fi

if gcloud auth list --format="get(account)" | grep -q .; then
  gcloud auth revoke
fi

gcloud auth login

service_account_email="$service_account_name@$project_id.iam.gserviceaccount.com"

if ! gcloud storage ls "gs://$bucket_name" >/dev/null 2>&1; then
  echo_blue "Creating bucket gs://$bucket_name" >&2
  gcloud storage buckets create "gs://$bucket_name" \
    --project="$project_id"
else
  echo_blue "Bucket gs://$bucket_name already exists" >&2
  echo_blue "Check it on the Cloud Console:"
  echo_blue "https://console.cloud.google.com/storage/browser/$bucket_name?project=$project_id"
fi

service_account_details=$(mktemp)
chmod 600 "$service_account_details"

exit_code=0
gcloud iam service-accounts \
  describe "$service_account_email" \
  --project="$project_id" \
  >"$service_account_details" ||
  exit_code=$?

echo_blue "exit_code: $exit_code" >&2

if [ $exit_code -ne 0 ]; then
  echo_blue "Creating service account $service_account_name" >&2
  gcloud iam service-accounts create "$service_account_name" \
    --description="Service account for GCS upload/download" \
    --display-name="GCS Uploader" \
    --project="$project_id"
else
  service_account_id=$(
    grep ^uniqueId: "$service_account_details" |
      cut -d' ' -f2 |
      tr -d "'"
  )
  echo_blue "Service account $service_account_name already exists" >&2
  echo_blue "Check it on the Cloud Console:"
  echo_blue "https://console.cloud.google.com/iam-admin/serviceaccounts/details/$service_account_id/keys?project=$project_id"
fi

gcloud projects add-iam-policy-binding "$project_id" \
  --member="serviceAccount:$service_account_email" \
  --role="roles/storage.objectAdmin"

printf "This action will create a new service account key. Continue? [y/N] "
read -r reply
echo
if [ ! "$reply" = "Y" ] && [ ! "$reply" = "y" ]; then
  echo_blue "Aborted" >&2
  exit 1
fi

echo_blue "Creating new service account key" >&2
secret=$(
  gcloud iam service-accounts keys create - \
    --iam-account="$service_account_email" \
    --project="$project_id" |
    jq -R -s '.' |
    jq -r @json
)

sops \
  --in-place \
  set \
  "$secret_file" \
  "[\"$secret_name\"]" \
  "$secret"
