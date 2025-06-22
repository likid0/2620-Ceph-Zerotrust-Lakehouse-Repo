#!/bin/bash

uid=$(grep -m 1 'ceph-node' /etc/hosts | awk '{print $2}' | sed 's/.*-\(.*\)/\1/')

yaml_file="/root/ceph-cluster-hosts.yaml"

yum install ansible -y

# Create the YAML configuration file with static entries and UID placeholders
cat <<EOF > "$yaml_file"
service_type: host
addr: ceph-node1-$uid
hostname: ceph-node1-$uid
labels:
  - mon
  - osd
  - rgw
  - mds
---

service_type: host
addr: ceph-node2-$uid
hostname: ceph-node2-$uid
labels:
  - mon
  - osd
  - rgw
  - mds
---

service_type: host
addr: ceph-node3-$uid
hostname: ceph-node3-$uid
labels:
  - mon
  - osd
  - nvmeof
---

service_type: host
addr: ceph-node4-$uid
hostname: ceph-node4-$uid
labels:
  - mon
  - osd
  - nfs
---
service_type: mds
service_id: cephfs
placement:
  label: "mds"
---
service_type: osd
service_id: all-available-devices
service_name: osd.all-available-devices
spec:
  data_devices:
    all: true
    limit: 3
placement:
  label: "osd"
---
service_type: rgw
service_id: objectgw
service_name: rgw.objectgw
placement:
  count: 1
  label: "rgw"
spec:
  rgw_frontend_port: 8080
---
service_type: nfs
service_id: nfsc
placement:
  label: "nfs"
spec:
  port: 2049
---

EOF

# Apply the configuration using cephadm
echo "Adding all hosts to the Ceph cluster..."
ceph orch apply -i "$yaml_file"

ceph config set global mon_max_pg_per_osd 512
# Create and enable a new RDB block pool.
ceph osd pool create rbdpool 32 32
ceph osd pool application enable rbdpool rbd

# Create the CephFS volume.
ceph fs volume create cephfs 2> /dev/null
ceph nfs export create cephfs --cluster-id nfsc --pseudo-path /nfs --fsname cephfs 2> /dev/null

echo "All Ceph nodes have been added to the cluster using $yaml_file."
echo "##################################################################"
echo "##################################################################"
echo "It will take around 5 minutes for the nodes to be added and the cluster in HEALTH_OK status"
echo "##################################################################"
echo "##################################################################"
sleep 15

EXPECTED_OSDS=12

echo "Waiting for $EXPECTED_OSDS OSDs to be up and in and the cluster to be HEALTH_OK..."

while true; do
    # Get the cluster status in JSON for easier parsing
    STATUS=$(ceph -s --format json)

    # Extract the current health status and OSD counts
    HEALTH=$(echo "$STATUS" | jq -r '.health.status')
    OSD_UP=$(echo "$STATUS" | jq '.osdmap.num_up_osds')
    OSD_IN=$(echo "$STATUS" | jq '.osdmap.num_in_osds')

    # Check conditions: all OSDs up & in, and HEALTH_OK
    if [ "$OSD_UP" -eq "$EXPECTED_OSDS" ] && [ "$OSD_IN" -eq "$EXPECTED_OSDS" ] && [ "$HEALTH" = "HEALTH_OK" ]; then
        echo "All $EXPECTED_OSDS OSDs are up and in, and the cluster is HEALTH_OK."
        break
    else
        echo "Currently: $OSD_UP/$EXPECTED_OSDS OSDs up, $OSD_IN/$EXPECTED_OSDS in, Health: $HEALTH. Rechecking in 30s..."
        sleep 30
    fi
done


