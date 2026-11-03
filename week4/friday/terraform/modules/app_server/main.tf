resource "null_resource" "this" {
  triggers = {
    name     = var.name
    image    = var.image
    cpus     = var.cpus
    memory   = var.memory
    disk     = var.disk
    init_sha = sha256(var.cloud_init)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = { CLOUD_INIT = var.cloud_init }
    command     = "printf '%s' \"$CLOUD_INIT\" | multipass launch ${self.triggers.image} --name ${self.triggers.name} --cpus ${self.triggers.cpus} --memory ${self.triggers.memory} --disk ${self.triggers.disk} --cloud-init -"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "multipass delete --purge ${self.triggers.name}"
  }
}

data "external" "ip" {
  depends_on = [null_resource.this]
  program    = ["bash", "-c", "multipass info ${null_resource.this.triggers.name} --format json | jq -c '{ip: (.info[] | .ipv4[0])}'"]
}
