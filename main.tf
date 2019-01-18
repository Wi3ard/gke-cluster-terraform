/*
 * Input variables.
 */

variable "cluster_name" {
  description = "GKE cluster name"
  type        = "string"
}

variable "google_project_id" {
  description = "GCE project ID"
  type        = "string"
}

variable "initial_node_count" {
  description = "Initial number of nodes in a cluster"
  default     = 3
  type        = "string"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  default     = "1.11.6-gke.2"
  type        = "string"
}

variable "machine_type" {
  description = "Type of instances to use for a cluster"
  default     = "n1-standard-1"
  type        = "string"
}

variable "max_node_count" {
  description = "Maximum number of nodes in a cluster"
  default     = 50
  type        = "string"
}

variable "preemptible" {
  description = "Whether or not the underlying node VMs are preemptible"
  default     = false
  type        = "string"
}

variable "region" {
  description = "Region to create resources in"
  default     = "us-central1"
  type        = "string"
}

variable "subnet_cluster_cidr_range" {
  description = "Subnet CIDR range for cluster nodes"
  default     = "192.168.0.0/16"
  type        = "string"
}

variable "subnet_pod_cidr_range" {
  description = "Subnet CIDR range for pods"
  default     = "10.4.0.0/14"
  type        = "string"
}

variable "subnet_services_cidr_range" {
  description = "Subnet CIDR range for pods"
  default     = "10.0.32.0/20"
  type        = "string"
}

variable "zones" {
  description = "Zones to create a cluster in"
  default     = ["us-central1-a", "us-central1-b"]
  type        = "list"
}

/*
 * Terraform providers.
 */

provider "google" {
  version = "~> 1.20"

  project = "${var.google_project_id}"
  region  = "${var.region}"
}

/*
 * GCS remote state storage.
 */

terraform {
  backend "gcs" {}
}

/*
 * Terraform resources.
 */

resource "google_compute_network" "default" {
  name                    = "${var.cluster_name}-net"
  auto_create_subnetworks = "true"
}

resource "google_compute_subnetwork" "default" {
  name                     = "${var.cluster_name}-subnet"
  ip_cidr_range            = "${var.subnet_cluster_cidr_range}"
  region                   = "${var.region}"
  network                  = "${google_compute_network.default.self_link}"
  private_ip_google_access = "true"

  secondary_ip_range {
    range_name    = "${var.cluster_name}-secondary-pod-range"
    ip_cidr_range = "${var.subnet_pod_cidr_range}"
  }

  secondary_ip_range {
    range_name    = "${var.cluster_name}-secondary-services-range"
    ip_cidr_range = "${var.subnet_services_cidr_range}"
  }
}

# GKE cluster.
resource "google_container_cluster" "default" {
  name             = "${var.cluster_name}"
  zone             = "${var.zones[0]}"
  additional_zones = "${slice(var.zones,1,length(var.zones))}"

  network    = "${google_compute_network.default.name}"
  subnetwork = "${google_compute_subnetwork.default.name}"

  initial_node_count       = 1
  logging_service          = "logging.googleapis.com"
  monitoring_service       = "monitoring.googleapis.com"
  remove_default_node_pool = "true"
  min_master_version       = "${var.kubernetes_version}"

  addons_config {
    http_load_balancing {
      disabled = "false"
    }

    horizontal_pod_autoscaling {
      disabled = "false"
    }

    kubernetes_dashboard {
      disabled = "true"
    }

    network_policy_config {
      disabled = "true"
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "${google_compute_subnetwork.default.secondary_ip_range.0.range_name}"
    services_secondary_range_name = "${google_compute_subnetwork.default.secondary_ip_range.1.range_name}"
  }

  lifecycle {
    ignore_changes = ["node_count"]
  }

  master_authorized_networks_config {
    cidr_blocks = [
      {
        cidr_block   = "0.0.0.0/0"
        display_name = "anywhere"
      },
    ]
  }

  private_cluster_config {
    enable_private_endpoint = "false"
    enable_private_nodes    = "true"
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Default node pool.
resource "google_container_node_pool" "default_pool" {
  name               = "default-pool"
  cluster            = "${google_container_cluster.default.name}"
  zone               = "${var.zones[0]}"
  initial_node_count = 1

  autoscaling {
    max_node_count = "${var.max_node_count}"
    min_node_count = "${var.initial_node_count}"
  }

  lifecycle {
    ignore_changes = ["initial_node_count"]
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    disk_size_gb = 30
    disk_type    = "pd-standard"
    image_type   = "COS"
    machine_type = "${var.machine_type}"
    preemptible  = "${var.preemptible}"

    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}
