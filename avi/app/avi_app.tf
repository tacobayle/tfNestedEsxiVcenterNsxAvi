data "template_file" "avi_app_userdata_segment_1" {
  count = var.avi.app.count
  template = file("${path.module}/userdata/avi_app.userdata")
  vars = {
    username     = var.avi.app.username
    hostname     = "${var.avi.app.basename}${count.index}"
    password      = var.ubuntu_password
    pubkey       = file(var.avi.app.public_key_path)
    netplan_file  = var.avi.app.netplan_file
    prefix = cidrnetmask(var.nsx.config.segments_overlay[1].cidr)
    ip = cidrhost(var.nsx.config.segments_overlay[1].cidr, var.nsx.config.segments_overlay[count.index].avi_app_server_starting_ip)
    default_gw = cidrhost(var.nsx.config.segments_overlay[1].cidr, var.nsx.config.segments_overlay[1].gw)
    dns = var.dns.nameserver
    docker_registry_username = var.docker_registry_username
    docker_registry_password = var.docker_registry_password
    avi_app_docker_image = var.avi.app.avi_app_docker_image
    avi_app_tcp_port = var.avi.app.avi_app_tcp_port
    hackazon_docker_image = var.avi.app.hackazon_docker_image
    hackazon_tcp_port = var.avi.app.hackazon_tcp_port
  }
}

data "template_file" "avi_app_userdata_segment_2" {
  count = var.avi.app.count
  template = file("${path.module}/userdata/avi_app.userdata")
  vars = {
    username     = var.avi.app.username
    hostname     = "${var.avi.app.basename}${count.index}"
    password      = var.ubuntu_password
    pubkey       = file(var.avi.app.public_key_path)
    netplan_file  = var.avi.app.netplan_file
    prefix = cidrnetmask(var.nsx.config.segments_overlay[2].cidr)
    ip = cidrhost(var.nsx.config.segments_overlay[2].cidr, var.nsx.config.segments_overlay[count.index].avi_app_server_starting_ip)
    default_gw = cidrhost(var.nsx.config.segments_overlay[2].cidr, var.nsx.config.segments_overlay[2].gw)
    dns = var.dns.nameserver
    docker_registry_username = var.docker_registry_username
    docker_registry_password = var.docker_registry_password
    avi_app_docker_image = var.avi.app.avi_app_docker_image
    avi_app_tcp_port = var.avi.app.avi_app_tcp_port
    hackazon_docker_image = var.avi.app.hackazon_docker_image
    hackazon_tcp_port = var.avi.app.hackazon_tcp_port
  }
}

resource "vsphere_virtual_machine" "avi_app_segment_1" {
  count = var.avi.app.count
  name             = "${var.avi.app.basename}${count.index}"
  datastore_id     = data.vsphere_datastore.datastore_nested.id
  resource_pool_id = data.vsphere_resource_pool.resource_pool_nested.id

  network_interface {
    network_id = data.vsphere_network.vcenter_network_1.id
  }

  num_cpus = var.avi.app.cpu
  memory = var.avi.app.memory
  wait_for_guest_net_timeout = "4"
  guest_id = "avi_app-${count.index}"

  disk {
    size             = var.avi.app.disk
    label            = "${var.avi.app.basename}${count.index}.lab_vmdk"
    thin_provisioned = true
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = vsphere_content_library_item.nested_library_item_avi_app.id
  }

  vapp {
    properties = {
      hostname    = "${var.avi.app.basename}${count.index}"
      public-keys = file(var.avi.app.public_key_path)
      user-data   = base64encode(data.template_file.avi_app_userdata_segment_1[count.index].rendered)
    }
  }

  connection {
    host        = cidrhost(var.nsx.config.segments_overlay[1].cidr, var.nsx.config.segments_overlay[count.index].avi_app_server_starting_ip)
    type        = "ssh"
    agent       = false
    user        = var.avi.app.username
    private_key = file(var.avi.app.private_key_path)
  }

  provisioner "remote-exec" {
    inline      = [
      "while [ ! -f /tmp/cloudInitDone.log ]; do sleep 1; done"
    ]
  }
}

resource "vsphere_virtual_machine" "avi_app_segment_2" {
  count = var.avi.app.count
  name             = "${var.avi.app.basename}${count.index}"
  datastore_id     = data.vsphere_datastore.datastore_nested.id
  resource_pool_id = data.vsphere_resource_pool.resource_pool_nested.id

  network_interface {
    network_id = data.vsphere_network.vcenter_network_2.id
  }

  num_cpus = var.avi.app.cpu
  memory = var.avi.app.memory
  wait_for_guest_net_timeout = "4"
  guest_id = "avi_app-${count.index}"

  disk {
    size             = var.avi.app.disk
    label            = "${var.avi.app.basename}${count.index}.lab_vmdk"
    thin_provisioned = true
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = vsphere_content_library_item.nested_library_item_avi_app.id
  }

  vapp {
    properties = {
      hostname    = "${var.avi.app.basename}${count.index}"
      public-keys = file(var.avi.app.public_key_path)
      user-data   = base64encode(data.template_file.avi_app_userdata_segment_1[count.index].rendered)
    }
  }

  connection {
    host        = cidrhost(var.nsx.config.segments_overlay[2].cidr, var.nsx.config.segments_overlay[count.index].avi_app_server_starting_ip)
    type        = "ssh"
    agent       = false
    user        = var.avi.app.username
    private_key = file(var.avi.app.private_key_path)
  }

  provisioner "remote-exec" {
    inline      = [
      "while [ ! -f /tmp/cloudInitDone.log ]; do sleep 1; done"
    ]
  }
}