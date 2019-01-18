# Kubernetes Cluster in Google Kubernetes Engine (GKE)

- [Kubernetes Cluster in Google Kubernetes Engine (GKE)](#kubernetes-cluster-in-google-kubernetes-engine-gke)
  - [Features](#features)
  - [TL;TR](#tltr)
  - [Before you begin](#before-you-begin)
    - [GCE configuration](#gce-configuration)
  - [GCS remote state storage for Terraform](#gcs-remote-state-storage-for-terraform)
  - [Terraform initialization](#terraform-initialization)
  - [Apply Terraform plan](#apply-terraform-plan)
  - [Cluster authentication](#cluster-authentication)
  - [Post install](#post-install)
    - [Helm installation](#helm-installation)

Terraform configuration for deploying a Kubernetes cluster in the [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine/) in the Google Cloud Platform (GCP).

## Features

- [X] [Private cluster](https://cloud.google.com/kubernetes-engine/docs/how-to/private-clusters) on GKE. **Note** that nodes in a private cluster do not have outbound Internet access because they don't have external IP addresses.
- [X] Ability to use [preemptible VM instances](https://cloud.google.com/compute/docs/instances/preemptible) for cluster nodes. **Note** that you need to have at least 3 nodes (throughout all zones) to minimize cluster downtime.

## TL;TR

```shell
gcloud auth login
gcloud config set account $ACCOUNT

gcloud projects create $PROJECT_ID [--name=$NAME] [--organization=$ORGANIZATION_ID]
gcloud alpha billing accounts list
gcloud alpha billing projects link $PROJECT_ID --billing-account $BILLING_ACCOUNT_ID
gcloud config set project $PROJECT_ID
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable storage-component.googleapis.com

gcloud iam service-accounts create terraform-sa --display-name "Terraform Service Account"
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:terraform-sa@$PROJECT_ID.iam.gserviceaccount.com --role roles/editor
gcloud iam service-accounts keys create ~/key.json --iam-account terraform-sa@$PROJECT_ID.iam.gserviceaccount.com

gsutil mb -l us-central1 gs://terraform-state-storage/

terraform init -backend-config "bucket=terraform-state-storage" -backend-config "prefix=cluster/example" -backend-config "region=us-central1"
terraform apply

gcloud container clusters get-credentials $CLUSTER_NAME

helm init
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
kubectl patch deploy --namespace kube-system tiller-deploy -p "{\"spec\":{\"template\":{\"spec\":{\"serviceAccount\":\"tiller\"}}}}"
```

## Before you begin

The following prerequisites need to be installed and configured:

- [Terraform](https://www.terraform.io/downloads.html)
- [Google Cloud SDK](https://cloud.google.com/sdk/install) (run `gcloud components update` to update SDK to the latest version if you have it already installed)

### GCE configuration

Make sure you are logged in to a correct Google account. To list all available accounts, run:

```shell
gcloud auth list
```

To login to a new account, run:

```shell
gcloud auth login
```

To set the active account, run:

```shell
gcloud config set account $ACCOUNT
```

- `$ACCOUNT` should be replaced with the account's e-mail.

Optionally create a new GCS project for your deployment:

```shell
gcloud projects create $PROJECT_ID [--name=$NAME] [--organization=$ORGANIZATION_ID]
```

- `$PROJECT_ID` should be replaced with the ID of the project to create.
- `$NAME` is an optional, and should be replaced with the name of the project to create.
- `$ORGANIZATION_ID` is an optional, and should be replaced with the ID of your organization.

 Run the following command to check whether the project succesfully created:

 ```shell
 gcloud projects list
 ```

In order to be able to use Compute Engine and/or Kubernetes Engine, you need to enable billing for a new project either via [Google Cloud Console](https://cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_a_new_project), or using the following command:

```shell
gcloud alpha billing projects link $PROJECT_ID --billing-account $BILLING_ACCOUNT_ID
```

- `$PROJECT_ID` should be replaced with the ID of the project you created.
- `$BILLING_ACCOUNT_ID` should be replaced with the ID of the billing account to link to the project.

Run following command to list all your billing accounts:

```shell
gcloud alpha billing accounts list
```

> **NOTE** To be able to run `gcloud alpha` command you need to have gcloud Alpha Commands component installed. Use `gcloud components list` to list all available components. `gcloud components install alpha` to install Alpha Commands component.

Set the project you created as an active:

```shell
gcloud config set project $PROJECT_ID
```

- `$PROJECT_ID` should be replaced with the ID of the project you've created.

Enable Compute, Kubernetes, and Cloud Storage engines for the project:

```shell
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable storage-component.googleapis.com
```

Create a [Service Account](https://cloud.google.com/iam/docs/creating-managing-service-accounts) for Terraform, and grant it the `Editor` role.

```shell
gcloud iam service-accounts create terraform-sa --display-name "Terraform Service Account"
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:terraform-sa@$PROJECT_ID.iam.gserviceaccount.com --role roles/editor
```

Create [service account keys](https://cloud.google.com/iam/docs/creating-managing-service-account-keys):

```shell
gcloud iam service-accounts keys create ~/key.json --iam-account terraform-sa@[$PROJECT_ID].iam.gserviceaccount.com
```

- `$PROJECT_ID` should be replaced with the ID of the project you've created.

Set the value of `GOOGLE_APPLICATION_CREDENTIALS` environment variable to a path of the generated key file.

For example (Windows PowerShell):

```shell
$env:GOOGLE_APPLICATION_CREDENTIALS = "~/key.json"
```

## GCS remote state storage for Terraform

Create GCS bucket for storing the Terraform state in a central remote location:

```shell
gsutil mb -l $REGION gs://$BUCKET_NAME/
```

- `$REGION` should be replaced with a region name, for example `us-central1`. Refer to [documentation](https://cloud.google.com/compute/docs/regions-zones/) for more information.
- `$BUCKET_NAME` should be replaced with a globally unique bucket name.

## Terraform initialization

Copy [terraform.tfvars.example](terraform.tfvars.example) file to `terraform.tfvars` and set input variables values as per your needs. Then initialize Terraform with `init` command:

```shell
terraform init -backend-config "bucket=$BUCKET_NAME" -backend-config "prefix=cluster/$CLUSTER_NAME" -backend-config "region=$REGION"
```

- `$REGION` should be replaced with a region name.
- `$CLUSTER_NAME` should be replaced with the name of a cluster.
- `$BUCKET_NAME` should be replaced with a GCS Terraform state storage bucket name.

## Apply Terraform plan

To apply Terraform plan, run:

```shell
terraform apply
```

## Cluster authentication

To authenticate to the newly created cluster, run:

```shell
gcloud container clusters get-credentials $CLUSTER_NAME
```

- `$CLUSTER_NAME` should be replaced with a name of the cluster.

To view general cluster information, run:

```shell
kubectl cluster-info
```

## Post install

### Helm installation

Install [Helm](https://helm.sh/) to the Kubernetes cluster:

```shell
helm init
```

Create service account and grant admin role to Tiller (Helm server component):

```bash
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
kubectl patch deploy --namespace kube-system tiller-deploy -p "{\"spec\":{\"template\":{\"spec\":{\"serviceAccount\":\"tiller\"}}}}"
```

---

**Happy Kuberneting!**
