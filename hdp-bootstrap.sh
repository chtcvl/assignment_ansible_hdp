#!/bin/bash

VCPUS_MASTER=4
VCPUS_WORKER=2
RAM=4096
DISK=64G
ROOT_DIR=/export
CONFIGS=${ROOT_DIR}/cloud-init
STORAGE_POOL=${ROOT_DIR}/pool
BASE_IMAGE=${STORAGE_POOL}/base-debian10-amd64.qcow2
MACHINES="hdp-master-deb"
MAC_PREFIX="12:34:56:AA:BC:"
IP_PREFIX="192.168.1.1"

function get_addr {
	PREFIX=$3
	MACHINES=$2
	NAME=$1
	i=10
	for INAME in ${MACHINES}
	do
		i=$(( i + 1 ))
		if [ "${NAME}" == "${INAME}" ]; then
			printf "${PREFIX}%02d" "${i}"
			break
		fi
	done
}

function meta-data {
	NAME="$1"
	CONFIGS="$2"
	cat > ${CONFIGS}/${NAME}/meta-data << EOF
instance-id: iid-${NAME}
local-hostname: ${NAME}
EOF
}

function network-config {
	NAME="$1"
	CONFIGS="$2"
	IPADDR="$3"
	MACADDR="$4"
	cat > ${CONFIGS}/${NAME}/network-config << EOF
version: 2
ethernets:
  eth0:
     match:
       mac_address: "${MACADDR}"
     set-name: eth0
     nameservers:
       search: ["local"]
       addresses: [8.8.8.8]
     addresses:
     - ${IPADDR}/24
     gateway4: 192.168.1.1
EOF
}

function user-data {
	NAME="$1"
	CONFIGS="$2"
	MASTER_IP=$(get_addr master "${MACHINES}" "${IP_PREFIX}")
	cat > ${CONFIGS}/${NAME}/user-data << EOF
#cloud-config
output:
    all: ">> /var/log/cloud-init.log"

write_files:
    - path: /root/.vimrc
      content: |
               filetype plugin indent on
               au! BufNewFile,BufReadPost *.{yaml,yml} set filetype=yaml
               autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
               syntax on

users:
    - name: root
      ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDEGQ+SMorM3QvqqzVFQPsQ950MQd7t3HvjoFIFhviFDpQLBmZT8V2pXqHpMl7lTB6rPBLFoJEbOFAJ9vzD018cEqv3mQ8h8pz6arINVG7sHhcMdYZZAR4JbxDz+O2xhro+uJda0G6a2vrbSRaavgfTyUtgVFPBA0vf1IWsvG6EexoBnjh3Kf6gsDc8bqaro1Cw7670kF6hh7kXaN3r7hZka/IVJN9bNgvybptPro02ebPD7j4GwTEk3Jf5uOyIDNDcHbmxqv8pRbnCoOb9iQq+U/upH5+XuMYzeE6nPrAenwzGr0Jm7sqMeiuz9KuDkV2z4ky60d/n9Wg+2cDSjJhn

runcmd:
    - sed -i '/eth/d' /etc/network/interfaces
    - ip addr flush eth0 && systemctl restart networking

EOF
}

if [ "$1" == "up" ]; then
	for NAME in ${MACHINES}
	do
		if [ "${NAME}" == "master" ]; then
			VCPUS=${VCPUS_MASTER}
		else
			VCPUS=${VCPUS_WORKER}
		fi
		MAC=$(get_addr ${NAME} "${MACHINES}" "${MAC_PREFIX}")
		VMIMAGE=${STORAGE_POOL}/${NAME}.qcow2
		CDISO=/export/cdrom/${NAME}.iso
		echo "Generating VM image for ${NAME}: ${VMIMAGE}"
		qemu-img create -b ${BASE_IMAGE} -f qcow2 ${VMIMAGE} ${DISK}
		echo "Generating ISO for configuring ${NAME}: ${CDISO}"
		genisoimage -lJR -V cidata -o ${CDISO} ${CONFIGS}/${NAME}/
		echo "CD ISO preparation result: "$?
		echo "Starting VM ${NAME}"
		virt-install -v --vcpus ${VCPUS} --memory ${RAM} -n ${NAME} --import --virt-type kvm --boot hd \
			--network bridge=br0,model=virtio,mac=${MAC} \
			--disk ${VMIMAGE},bus=virtio,format=qcow2 \
			--disk ${CDISO},bus=ide,device=cdrom \
			--console pty,target_type=serial \
			--os-type linux --os-variant debian10 --noautoconsole --machine pc
		echo "VM launch result: "$?
		echo "Marking VM ${NAME} to start on boot"
		virsh autostart ${NAME}
	done
elif [ "$1" == "down" ]; then
	for NAME in ${MACHINES}
	do
		virsh destroy ${NAME}
		virsh undefine ${NAME}
		rm ${STORAGE_POOL}/${NAME}.qcow2
	done
elif [ "$1" == "init" ]; then
	rm -rf ${CONFIGS}
	mkdir -p ${CONFIGS}
	for NAME in ${MACHINES}
	do
		IP=$(get_addr ${NAME} "${MACHINES}" "${IP_PREFIX}")
		MAC=$(get_addr ${NAME} "${MACHINES}" "${MAC_PREFIX}")
		mkdir -p ${CONFIGS}/${NAME}
		network-config "${NAME}" ${CONFIGS} ${IP} ${MAC}
		meta-data "${NAME}" ${CONFIGS} ${IP}
		user-data "${NAME}" ${CONFIGS}
	done
else
	echo "Try up or down"
fi
