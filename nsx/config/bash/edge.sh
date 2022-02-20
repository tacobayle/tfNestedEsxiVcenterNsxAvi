#!/bin/bash
#
if [ -f "../../variables.json" ]; then
  jsonFile="../../variables.json"
else
  echo "ERROR: no json file found"
  exit 1
fi
nsx_ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_ip $jsonFile)
vcenter_username=administrator
vcenter_domain=$(jq -r .vcenter.sso.domain_name $jsonFile)
vcenter_fqdn="$(jq -r .vcenter.name $jsonFile).$(jq -r .dns.domain $jsonFile)"
rm -f cookies.txt headers.txt
curl -k -c cookies.txt -D headers.txt -X POST -d 'j_username=admin&j_password='$TF_VAR_nsx_password'' https://$nsx_ip/api/session/create
#curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/transport-nodes
compute_managers=$(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/fabric/compute-managers)
IFS=$'\n'
for item in $(echo $compute_managers | jq -c -r .results[])
do
  if [[ $(echo $item | jq -r .display_name) == $(jq -r .vcenter.name $jsonFile).$(jq -r .dns.domain $jsonFile) ]] ; then
    vc_id=$(echo $item | jq -r .id)
  fi
done
echo $vc_id
segments=$(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/infra/segments)
for item in $(echo $segments | jq -c -r .results[])
do
  if [[ $(echo $item | jq -r .display_name) == $(jq -r .nsx.config.edge_node.data_network $jsonFile) ]] ; then
    data_network_path=$(echo $item | jq -r .path)
  fi
done
api_host="$(jq -r .vcenter.name $jsonFile).$(jq -r .dns.domain $jsonFile)"
vcenter_username=administrator
vcenter_domain=$(jq -r .vcenter.sso.domain_name $jsonFile)
vcenter_password=$TF_VAR_vcenter_password
token=$(curl -k -s -X POST -u "$vcenter_username@$vcenter_domain:$vcenter_password" https://$api_host/api/session -H "Content-Type: application/json" | tr -d \")
storage_id=$(curl -k -X GET -H "vmware-api-session-id: $token" -H "Content-Type: application/json" "https://$api_host/api/vcenter/datastore" | jq -r .[0].datastore)
echo $storage_id
vcenter_networks=$(curl -k -X GET -H "vmware-api-session-id: $token" -H "Content-Type: application/json" "https://$api_host/api/vcenter/network")
for item in $(echo $vcenter_networks | jq -c -r .[])
do
  if [[ $(echo $item | jq -r .name) == $(jq -r .vcenter.dvs.portgroup.management.name $jsonFile) ]] ; then
    management_network_id=$(echo $item | jq -r .network)
  fi
done
echo $management_network_id
vcenter_resource_pools=$(curl -k -X GET -H "vmware-api-session-id: $token" -H "Content-Type: application/json" "https://$api_host/api/vcenter/resource-pool")
for item in $(echo $vcenter_resource_pools| jq -c -r .[])
do
  if [[ $(echo $item | jq -r .name) == "Resources" ]] ; then
    compute_id=$(echo $item | jq -r .resource_pool)
  fi
done
echo $compute_id
for edge_index in $(seq 1 $(jq -r .nsx.config.edge_node.count $jsonFile))
do
  name=$(jq -r .nsx.config.edge_node.basename $jsonFile)$edge_index
  fqdn=$(jq -r .nsx.config.edge_node.basename $jsonFile)-$edge_index.$(jq -r .dns.domain $jsonFile)
  cpu=$(jq -r .nsx.config.edge_node.cpu $jsonFile)
  memory=$(jq -r .nsx.config.edge_node.memory $jsonFile)
  disk=$(jq -r .nsx.config.edge_node.disk $jsonFile)
  gateway=$(jq -r .vcenter.dvs.portgroup.management.gateway $jsonFile)
  prefix_length=$(jq -r .vcenter.dvs.portgroup.management.prefix $jsonFile)
  ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_edge $jsonFile)
  curl -k -s -X POST -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d '{"maintenance_mode" : "DISABLED", "display_name":"'$name'", "node_deployment_info": {"resource_type":"EdgeNode", "deployment_type": "VIRTUAL_MACHINE", "deployment_config": { "vm_deployment_config": {"vc_id": "'$vc_id'", "compute_id": "'$compute_id'", "storage_id": "'$storage_id'", "management_network_id": "'$management_network_id'", "management_port_subnets": [{"ip_addresses": ["'$ip'"], "prefix_length": '$prefix_length'}], "default_gateway_addresses": ["'$gateway'"], "data_network_ids": ["'$data_network_path'",  "'$data_network_path'"], "reservation_info": { "memory_reservation" : {"reservation_percentage": 100 }, "cpu_reservation": { "reservation_in_shares": "HIGH_PRIORITY", "reservation_in_mhz": 0 }}, "resource_allocation": {"cpu_count": '$cpu', "memory_allocation_in_mb": '$memory' }, "placement_type": "VsphereDeploymentConfig"}, "form_factor": "MEDIUM", "node_user_settings": {"cli_username": "admin", "root_password": "'$TF_VAR_nsx_password'", "cli_password": "'$TF_VAR_nsx_password'"}}, "node_settings": {"hostname": "'$fqdn'", "enable_ssh": true, "allow_ssh_root_login": true }}}' https://$nsx_ip/api/v1/transport-nodes
done