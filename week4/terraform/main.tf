terraform {
  required_providers {
    null     = { source = "hashicorp/null" }
    external = { source = "hashicorp/external" }
  }

  backend "s3" {
    bucket                      = "kijanikiosk-tfstate"
    key                         = "terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "http://localhost:9000" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }
}

locals {
  cloud_init = <<-EOT
    #cloud-config
    ssh_authorized_keys:
      - ${trimspace(file(pathexpand(var.ssh_public_key_path)))}
  EOT
}

module "app_server" {
  source   = "./modules/app_server"
  for_each = var.servers

  name       = "${var.name_prefix}-${each.key}"
  image      = var.ubuntu_image
  cpus       = each.value.cpus
  memory     = each.value.memory
  disk       = each.value.disk
  cloud_init = local.cloud_init
}
