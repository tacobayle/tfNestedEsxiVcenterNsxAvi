resource "null_resource" "ansible_hosts_avi_header_1" {
  provisioner "local-exec" {
    command = "echo '---' | tee hosts_avi; echo 'all:' | tee -a hosts_avi ; echo '  children:' | tee -a hosts_avi; echo '    controller:' | tee -a hosts_avi; echo '      hosts:' | tee -a hosts_avi"
  }
}

resource "null_resource" "ansible_hosts_avi_controllers" {
  depends_on = [null_resource.ansible_hosts_avi_header_1]
  provisioner "local-exec" {
    command = "echo '        ${cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[count.index].avi_controller)}:' | tee -a hosts_avi "
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

  provisioner "remote-exec" {
    inline = [
      "git clone ${var.avi.config.avi_config_repo} --branch ${var.avi.config.avi_config_tag}",
      "cd ${split("/", var.avi.config.avi_config_repo)[4]}",
      "ansible-playbook -i ../hosts_avi local.yml --extra-vars '{\"avi_version\": ${jsonencode(var.avi.controller.version)}, \"controllerPrivateIps\": [${cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[count.index].avi_controller)}], \"avi_password\": ${jsonencode(var.avi_password)}, \"avi_username\": ${jsonencode(var.avi_username)}, \"controller\": {\"cluster\": false} }'"
    ]
  }
}