#!/usr/bin/env bash
source config.shlib # load the config library functions
project_id=$(gcloud config get-value project)
project_number=$(gcloud projects describe ${project_id} | grep projectNumber | sed 's/projectNumber: //g' | tr -d [[:punct:]])
deploy_microservices="$(config_get deploy_microservices)"
echo Provisioning infrastructure in ${project_id}
echo project number is ${project_number}

echo Granting "$(config_get cloudbuild_sa_role)" access to the Cloud Build Service Account
gcloud projects add-iam-policy-binding ${project_id} --member "serviceAccount:${project_number}@cloudbuild.gserviceaccount.com" --role "$(config_get cloudbuild_sa_role)"

echo Executing the Set Up GCP Infra pipeline
gcloud builds submit --substitutions=_TRANSACTION_TOPIC_NAME="$(config_get transaction_topic_name)",_BALANCE_TOPIC_NAME="$(config_get balance_topic_name)"
echo Task: Set Up GCP Infra pipeline executed, check the logs if its successful

if [ "$deploy_microservices" = true ]; then

    echo Deploying the Customer Service
    gcloud builds submit ../gcp-training-customer-service --config="../gcp-training-customer-service/cloudbuild.yaml"
    customer_service_url=$(gcloud run services describe gcp-training-customer-service --platform=managed --region=europe-west1 | grep https://gcp-training-customer-service)
    echo Task: Customer Service deployment executed, check the logs if its successful

    echo Deploying the Account Service
    gcloud builds submit ../gcp-training-account-service --config="../gcp-training-account-service/cloudbuild.yaml" --substitutions=_CUSTOMER_SERVICE_URL=${customer_service_url}
    account_service_url=$(gcloud run services describe gcp-training-account-service --platform=managed --region=europe-west1 | grep https://gcp-training-account-service)
    echo Task: Account Service deployment executed, check the logs if its successful

    echo Deploying the Cashier Service
    gcloud builds submit ../gcp-training-cashier-service --config="../gcp-training-cashier-service/cloudbuild.yaml"
    cashier_service_url=$(gcloud run services describe gcp-training-cashier-service --platform=managed --region=europe-west1 | grep https://gcp-training-cashier-service)
    echo Task: Cashier Service deployment executed, check the logs if its successful

    echo Deploying the Transaction Service
    gcloud builds submit ../gcp-training-transaction-service --config="../gcp-training-transaction-service/cloudbuild.yaml" --substitutions=_ACCOUNTS_SERVICE_URL=${account_service_url}
    transaction_service_url=$(gcloud run services describe gcp-training-transaction-service --platform=managed --region=europe-west1 | grep https://gcp-training-transaction-service)
    echo Task: Transaction Service deployment executed, check the logs if its successful

    echo Deploying the Balance Service
    gcloud builds submit ../gcp-training-balance-service --config="../gcp-training-balance-service/cloudbuild.yaml"
    balance_service_url=$(gcloud run services describe gcp-training-balance-service --platform=managed --region=europe-west1 | grep https://gcp-training-balance-service)
    echo Task: Balance Service deployment executed, check the logs if its successful

    echo -------------------------------------------------------------------------------------------------------------------------
    echo Exporting all the Microservice URLs to environment variables and create a microservice_url_env.sh for further references.
    echo -------------------------------------------------------------------------------------------------------------------------
    rm -rf microservice_url_env.sh
    echo export CUSTOMER_SERVICE_URL=${customer_service_url} >>microservice_url_env.sh
    echo export ACCOUNT_SERVICE_URL=${account_service_url} >>microservice_url_env.sh
    echo export CASHIER_SERVICE_URL=${cashier_service_url} >>microservice_url_env.sh
    echo export TRANSACTION_SERVICE_URL=${transaction_service_url} >>microservice_url_env.sh
    echo export BALANCE_SERVICE_URL=${balance_service_url} >>microservice_url_env.sh
    . microservice_url_env.sh

    echo Executing the Smoke Tests in Cloud Build Pipeline
    gcloud builds submit --substitutions=_CUSTOMER_SERVICE_URL=$CUSTOMER_SERVICE_URL,_ACCOUNT_SERVICE_URL=$ACCOUNT_SERVICE_URL,_CASHIER_SERVICE_URL=$CASHIER_SERVICE_URL,_TRANSACTION_SERVICE_URL=$TRANSACTION_SERVICE_URL,_BALANCE_SERVICE_URL=$BALANCE_SERVICE_URL ../gcp-training-microservices-smoke-tests --config="../gcp-training-microservices-smoke-tests/cloudbuild.yaml"
else
    echo Skipped microservices deployment
fi

echo Setup GCP infra script execution completed