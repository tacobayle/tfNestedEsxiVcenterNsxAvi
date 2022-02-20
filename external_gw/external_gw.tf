resource "vsphere_content_library" "library_external_gw" {
  count = (var.external_gw.create == true ? 1 : 0)
  name            = "cl_tf_external_gw"
  storage_backing = [data.vsphere_datastore.datastore.id]
}

resource "vsphere_content_library_item" "file_external_gw" {
  count = (var.external_gw.create == true ? 1 : 0)
  name        = basename(var.vcenter_underlay.cl.file_external_gw)
  library_id  = vsphere_content_library.library_external_gw[0].id
  file_url = var.vcenter_underlay.cl.file_external_gw
}

data "template_file" "external_gw_userdata" {
  count = (var.external_gw.create == true ? 1 : 0)
  template = file("${path.module}/userdata/external_gw.userdata")
  vars = {
    pubkey        = file(var.external_gw.public_key_path)
    username = var.external_gw.username
    ipCidr  = "${var.vcenter.dvs.portgroup.management.external_gw_ip}/${var.vcenter.dvs.portgroup.management.prefix}"
    ip = var.vcenter.dvs.portgroup.management.external_gw_ip
    defaultGw = var.vcenter.dvs.portgroup.management.gateway
//    ip_data_cidr  = "${var.vcenter.dvs.portgroup.nsx_external.external_gw_ip}/${var.vcenter.dvs.portgroup.nsx_external.prefix}"
    dns      = var.external_gw.dns
    netplanFile = var.external_gw.netplanFile
    privateKey = var.external_gw.private_key_path
  }
}

resource "vsphere_virtual_machine" "external_gw" {
  count = (var.external_gw.create == true ? 1 : 0)
  name             = var.external_gw.name
  datastore_id     = data.vsphere_datastore.datastore.id
  resource_pool_id = data.vsphere_resource_pool.pool.id
  folder           = "/${var.vcenter_underlay.dc}/vm/${var.vcenter_underlay.folder}"

  network_interface {
    network_id = data.vsphere_network.vcenter_underlay_network_mgmt.id
  }

//  network_interface {
//    network_id = data.vsphere_network.vcenter_underlay_network_external.id
//  }

  num_cpus = var.external_gw.cpu
  memory = var.external_gw.memory
  wait_for_guest_net_timeout = var.external_gw.wait_for_guest_net_timeout
  guest_id = "ubuntu64Guest"

  disk {
    size             = var.external_gw.disk
    label            = "${var.external_gw.name}.lab_vmdk"
    thin_provisioned = true
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = vsphere_content_library_item.file_external_gw[0].id
  }

  vapp {
    properties = {
      hostname    = var.external_gw.name
      public-keys = file(var.external_gw.public_key_path)
      user-data   = base64encode(data.template_file.external_gw_userdata[0].rendered)
    }
  }

  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline      = [
      "while [ ! -f /tmp/cloudInitDone.log ]; do sleep 1; done"
    ]
  }
}

resource "null_resource" "clear_ssh_key_external_gw_locally" {
  provisioner "local-exec" {
    command = "ssh-keygen -f \"/home/ubuntu/.ssh/known_hosts\" -R \"${var.vcenter.dvs.portgroup.management.external_gw_ip}\" || true"
  }
}

resource "null_resource" "add_nic_to_external_gw" {
  depends_on = [vsphere_virtual_machine.external_gw]

  provisioner "local-exec" {
    command = <<-EOT
      export GOVC_USERNAME=${var.vsphere_username}
      export GOVC_PASSWORD=${var.vsphere_password}
      export GOVC_DATACENTER=${var.vcenter_underlay.dc}
      export GOVC_URL=${var.vcenter_underlay.server}
      export GOVC_CLUSTER=${var.vcenter_underlay.cluster}
      export GOVC_INSECURE=true
      /usr/local/bin/govc vm.network.add -vm "${var.external_gw.name}" -net ${var.vcenter_underlay.network_nsx_external.name}
    EOT
  }
}

resource "null_resource" "update_ip_external_gw" {
  depends_on = [null_resource.add_nic_to_external_gw]
  count = (var.external_gw.create == true ? 1 : 0)

  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo netplan apply"
    ]
  }
}