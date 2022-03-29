resource "null_resource" "ansible_hosts_avi_header_1" {
  provisioner "local-exec" {
    command = "echo '---' | tee hosts_avi; echo 'all:' | tee -a hosts_avi ; echo '  children:' | tee -a hosts_avi; echo '    controller:' | tee -a hosts_avi; echo '      hosts:' | tee -a hosts_avi"
  }
}

resource "null_resource" "ansible_hosts_avi_controllers" {
  depends_on = [null_resource.ansible_hosts_avi_header_1]
  provisioner "local-exec" {
    command = "echo '        ${cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller)}:' | tee -a hosts_avi "
  }
}

data "template_file" "values" {
  template = file("templates/values.yml.template")
  vars = {
    avi_version = var.avi.controller.version
    controllerPrivateIp = cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller)
    avi_old_password =  jsonencode(var.avi_old_password)
    avi_password = jsonencode(var.avi_password)
    avi_username = jsonencode(var.avi_username)
    ntp = var.ntp.server
    dns = var.dns.nameserver
    nsx_password = var.nsx_password
    nsx_server = var.vcenter.dvs.portgroup.management.nsx_ip
    domain = var.dns.domain
    cloud_name = var.avi.config.cloud.name
    cloud_obj_name_prefix = var.avi.config.cloud.obj_name_prefix
    transport_zone_name = var.avi.config.transport_zone_name
    network_management = jsonencode(var.avi.config.network_management)
    networks_data = jsonencode(var.avi.config.networks_data)
    sso_domain = var.vcenter.sso.domain_name
    vcenter_password = var.vcenter_password
    vcenter_ip = var.vcenter.dvs.portgroup.management.vcenter_ip
    content_library = var.avi.config.content_library_avi
    service_engine_groups = jsonencode(var.avi.config.service_engine_groups)
    pools = jsonencode(var.avi.config.pools)
    virtual_services = jsonencode(var.avi.config.virtual_services)
  }
}

resource "null_resource" "ansible_avi" {
  depends_on = [null_resource.ansible_hosts_avi_controllers]

  connection {
    host = var.vcenter.dvs.portgroup.management.external_gw_ip
    type = "ssh"
    agent = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    source = "hosts_avi"
    destination = "hosts_avi"
  }

  provisioner "file" {
    content = data.template_file.values.rendered
    destination = "values.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "git clone ${var.avi.config.avi_config_repo} --branch ${var.avi.config.avi_config_tag}",
      "cd ${split("/", var.avi.config.avi_config_repo)[4]}",
      "ansible-playbook -i ../hosts_avi nsx.yml --extra-vars @../values.yml"
//      "ansible-playbook -i ../hosts_avi local.yml --extra-vars '{\"avi_version\": ${jsonencode(var.avi.controller.version)}, \"controllerPrivateIps\": [${cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller)}], \"avi_old_password\": ${jsonencode(var.avi_old_password)}, \"avi_password\": ${jsonencode(var.avi_password)}, \"avi_username\": ${jsonencode(var.avi_username)}, \"controller\": {\"aviCredsJsonFile\": \"~/.creds.json\", \"environment\": \"vCenter\", \"cluster\": false, \"ntp\": [${jsonencode(var.ntp.server)}], \"dns\": [${jsonencode(var.dns.nameserver)}]}, \"nsx_username\": \"admin\", \"nsx_password\": ${jsonencode(var.nsx_password)}, \"nsx_server\": ${jsonencode(var.vcenter.dvs.portgroup.management.nsx_ip)}, \"nsxt\": {\"name\": \"dc1_nsxt\", \"domains\": [{\"name\": ${jsonencode(var.dns.domain)}}], \"transport_zone\": {\"name\": ${jsonencode(var.avi.config.transport_zone_name)} }, \"network_management\": ${jsonencode(var.avi.config.network_management)}, \"networks_data\": ${jsonencode(var.avi.config.networks_data)}, \"networks_backend\": ${jsonencode(var.avi.config.networks_backend)} }, \"vcenter_credentials\": [{\"username\": \"administrator@${var.vcenter.sso.domain_name}\", \"password\": ${jsonencode(var.vcenter_password)}}]}'"
    ]
  }
}