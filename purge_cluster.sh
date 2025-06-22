export FSID=$(cephadm shell ceph config get mon fsid)
ansible-playbook -i /usr/share/cephadm-ansible/hosts /usr/share/cephadm-ansible/cephadm-purge-cluster.yml -e fsid=${FSID} --limit '!client'
