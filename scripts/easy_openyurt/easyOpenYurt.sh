#!/bin/bash

# MIT License
# 
# Copyright (c) 2023 Haoyuan Ma <flyinghorse0510@zju.edu.cn>

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Version Lock
KUBE_VERSION="1.23.16"
GO_VERSION="1.17.13"
CONTAINERD_VERSION="1.6.18"
RUNC_VERSION="1.1.4"
CNI_PLUGINS_VERSION="1.2.0"
KUBECTL_VERSION="1.23.16-00"
KUBEADM_VERSION="1.23.16-00"
KUBELET_VERSION="1.23.16-00"

# Global Variables
argc=$#
operationObject=$1
nodeRole=$2
operation=$3
apiserverAdvertiseAddress=$4
controlPlaneHost=$4
nodeType=$4
controlPlanePort=$5
nodeName=$5
controlPlaneToken=$6
discoveryTokenHash=$7
ARCH=""
PROXY_CMD=""
KUBEADM_INIT_IMG_REPO_ARGS=""
TMP_DIR=""
OS=""
SYMBOL_WAITING=" >>>>> "
TEMPLATE_DIR="template"

# Configure Redirection and Logs
exec 3>&1
exec 4>&2
exec 1>> ${PWD}/easyOpenYurtInfo.log
exec 2>> ${PWD}/easyOpenYurtErr.log

# Text Color Definition
COLOR_ERROR=1
COLOR_WARNING=3
COLOR_SUCCESS=2
COLOR_INFO=4
color_echo () {
    echo -e -n "$(tput setaf $1)[$(date +'%T')] $2$(tput sgr 0)"
}

# Print Helper Function
info_echo () {
	echo -e -n "[$(date +'%T')] [Info] $1" # For Logs
	color_echo ${COLOR_INFO} "[Info] $1" >&3 # For Output
}
success_echo () {
	echo -e -n "[$(date +'%T')] [Success] $1" # For Logs
	color_echo ${COLOR_SUCCESS} "[Success] $1" >&3 # For Output
}
warn_echo () {
	echo -e -n "[$(date +'%T')] [Warn] $1" >&2 # For Logs
	color_echo ${COLOR_WARNING} "[Warn] $1" >&4 # For Output
}
error_echo () {
	echo -e -n "[$(date +'%T')] [Error] $1" >&2 # For Logs
	color_echo ${COLOR_ERROR} "[Error] $1" >&4 # For Output
}
print_general_usage () {
	info_echo "Usage: $0 [object: system | kube | yurt] [nodeRole: master | worker] [operation: init | join | expand] <Args...>\n"
}
print_welcome () {
	color_echo ${COLOR_SUCCESS} "<<<<<<<<< EasyOpenYurt v0.1.0b >>>>>>>>>\n" >&3
}
print_start_warning () {
	warn_echo "THIS IS AN EXPERIMENTAL SCRIPT DEVELOPED PERSONALLY\n"
	warn_echo "DO NOT ATTEMPT TO USE IN PRODUCTION ENVIRONMENT!\n"
	warn_echo "MAKE SURE TO BACK UP YOUR SYSTEM AND TAKE CARE!\n"
}
print_start_info () {
	success_echo "Stdout Log -> ${PWD}/easyOpenYurtInfo.log\n"
	success_echo "Stderr Log -> ${PWD}/easyOpenYurtErr.log\n"
}

# Detect the Architecture
detect_arch () {
	ARCH=$(uname -m)
	case $ARCH in
		armv5*)	ARCH="armv5" ;;
		armv6*) ARCH="armv6" ;;
		armv7*) ARCH="arm" ;;
		aarch64) ARCH="arm64" ;;
		x86) ARCH="386" ;;
		x86_64) ARCH="amd64" ;;
		i686) ARCH="386" ;;
		i386) ARCH="386" ;;
		*)	terminate_with_error "Unsupported Architecture: ${ARCH}!" ;;
	esac
	info_echo "Detected Arch: ${ARCH}\n"
}

detect_os () {
	OS=$(sed -n "s/\s*\(\S\S*\).*/\1/p" < /etc/issue | head -1 | tr '[:upper:]' '[:lower:]')
	case ${OS} in
		ubuntu) ;;
		*)	terminate_with_error "Unsupported OS: ${OS}!" ;;
	esac
	info_echo "Detected OS: ${OS}\n"
}

# Detect Executable in PATH
detect_cmd () {
	cmd=$1
	if [ -x "$(command -v ${cmd})" ]; then
		return 0
	fi
	return 1
}


# Script Control
terminate_with_error () {
	funcArgc=$#
	errorMsg=$1
	if [ ${funcArgc} -ge 1 ]; then
		error_echo "${errorMsg}\n"
	fi
	error_echo "Script Terminated!\n"
	exit 1
}

terminate_if_error () {
	cmdResult=$?
	errorMsg=$1
	if ! [ ${cmdResult} -eq 0 ]; then
		error_echo "\n"
		terminate_with_error "${errorMsg}"
	else
		success_echo "\n"
	fi
}

exit_with_success_info () {
	funcArgc=$#
	exitMsg=$1
	if [ ${funcArgc} -ge 1 ]; then
		success_echo "${exitMsg}\n"
	fi
	exit 0
}

choose_yes () {
	msg=$1
	warn_echo "${msg} [y/n]: "
	read -r confirmation
	case ${confirmation} in
		[yY]*)
			return 0
		;;
		*)
			return 1
		;;
	esac
}


# Temporary Files Management
create_tmp_dir () {
	# Create Temporary Directory
	info_echo "Creating Temporary Directory${SYMBOL_WAITING}"
	TMP_DIR=$(mktemp -d yurt_tmp.XXXXXX) 
	terminate_if_error "Failed to Create Temporary Directory!"
}

clean_tmp_dir () {
	# Clean Temporary Directory
	info_echo "Cleaning Temporary Directory${SYMBOL_WAITING}"
	rm -rf "${TMP_DIR}"
	terminate_if_error "Failed to Clean Temporary Directory!"
}

download_to_tmp () {
	url=$1
	${PROXY_CMD} curl -sSLO --output-dir ${TMP_DIR} ${url}
	return $?
}

# Proxy Settings
use_proxychains () {
	# Use Proxychains If Existed
	if detect_cmd "proxychains"; then
		if choose_yes "Proxychains Detected! Use Proxy?"; then
			PROXY_CMD="proxychains"
			info_echo "Proxychains WILL be Used!\n"
		else
			info_echo "Proxychains WILL NOT be Used!\n"
		fi
		sleep 1
	fi
}

# Install Package
install_package () {
	packages=$*
	case ${OS} in
		ubuntu)
			sudo ${PROXY_CMD} apt-get -qq update && sudo ${PROXY_CMD} apt-get -qq install -y --allow-downgrades ${packages}
			return $?
		;;
		*)	terminate_with_error "Script Internal Error!" ;;
	esac
}

# Adaptation for China Mainland
adapt_for_cn () {
	# China Mainland Adaptation
	if choose_yes "Apply Adaptation & Optimization for China Mainland Users to Avoid Network Issues?"; then
		info_echo "Applying China Mainland Adaptation${SYMBOL_WAITING}"
		KUBEADM_INIT_IMG_REPO_ARGS="--image-repository docker.io/flyinghorse0510"
		sudo sed -i "s/sandbox_image = .*/sandbox_image = \"docker.io/flyinghorse0510/pause:3.6\"/g" /etc/containerd/config.toml
		terminate_if_error "Failed to Apply China Mainland Adaptation!"
	else
		info_echo "Adaptation WILL NOT be Applied!\n"
	fi
}

# Node Role
treat_master_as_cloud () {
	# Whether to Treat Master Node as a Cloud Node
	if choose_yes "Treat Master Node as a Cloud Node?"; then
		info_echo "Master Node WILL also be Treated as a Cloud Node${SYMBOL_WAITING}\n"
		kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule-
		kubectl taint nodes --all node-role.kubernetes.io/control-plane-
	else
		info_echo "Master Node WILL NOT be Treated as a Cloud Node\n"
	fi
}

# Write Master Node Info to YAML
write_master_node_info_to_yaml () {
	controlPlaneHost=$1
	controlPlanePort=$2
	controlPlaneToken=$3
	discoveryTokenHash=$4
	echo -n -e "controlPlaneHost: ${controlPlaneHost}\ncontrolPlanePort: ${controlPlanePort}\ncontrolPlaneToken: ${controlPlaneToken}\ndiscoveryTokenHash: ${discoveryTokenHash}" | tee ${PWD}/masterKey.yaml
}


system_init () {

	# Initialize
	use_proxychains
	create_tmp_dir

	# Disable Swap
	info_echo "Disabling Swap${SYMBOL_WAITING}"
	sudo swapoff -a && sudo cp /etc/fstab /etc/fstab.old 	# Turn off Swap && Backup fstab file
	terminate_if_error "Failed to Disable Swap!"

	info_echo "Modifying fstab${SYMBOL_WAITING}"
	sudo sed -i 's/.*swap.*/# &/g' /etc/fstab		# Modify fstab to Disable Swap Permanently
	terminate_if_error "Failed to Modify fstab!"

	# Install Dependencies
	info_echo "Installing Dependencies${SYMBOL_WAITING}"
	install_package git wget curl build-essential apt-transport-https ca-certificates 
	terminate_if_error "Failed to Install Dependencies!"

	# Install Containerd
	info_echo "Installing Containerd(ver ${CONTAINERD_VERSION})${SYMBOL_WAITING}\n"
	info_echo "Downloading Containerd${SYMBOL_WAITING}"
	download_to_tmp https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz 
	terminate_if_error "Failed to Download Containerd!"

	info_echo "Extracting Containerd${SYMBOL_WAITING}"
	sudo tar Cxzvf /usr/local ${TMP_DIR}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz
	terminate_if_error "Failed to Extract Containerd!"

	# Start Containerd via Systemd
	info_echo "Starting Containerd${SYMBOL_WAITING}"
	download_to_tmp https://raw.githubusercontent.com/containerd/containerd/main/containerd.service && sudo cp ${TMP_DIR}/containerd.service /lib/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now containerd
	terminate_if_error "Failed to Start Containerd!"

	# Install Runc
	info_echo "Installing Runc(ver ${RUNC_VERSION})${SYMBOL_WAITING}"
	download_to_tmp https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH} && sudo install -m 755 ${TMP_DIR}/runc.${ARCH} /usr/local/sbin/runc
	terminate_if_error "Failed to Install Runc!"

	# Install CNI Plugins
	info_echo "Installing CNI Plugins(ver ${CNI_PLUGINS_VERSION})${SYMBOL_WAITING}"
	download_to_tmp https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz && sudo mkdir -p /opt/cni/bin && sudo tar Cxzvf /opt/cni/bin ${TMP_DIR}/cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz
	terminate_if_error "Failed to Install CNI Plugins!"

	# Configure the Systemd Cgroup Driver
	info_echo "Configuring the Systemd Cgroup Driver${SYMBOL_WAITING}"
	containerd config default > ${TMP_DIR}/config.toml && sudo mkdir -p /etc/containerd && sudo cp ${TMP_DIR}/config.toml /etc/containerd/config.toml && sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml && sudo systemctl restart containerd
	terminate_if_error "Failed to Configure the Systemd Cgroup Driver!"

	# Install Golang
	info_echo "Installing Golang(ver ${GO_VERSION})${SYMBOL_WAITING}"
	download_to_tmp https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz && sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf ${TMP_DIR}/go${GO_VERSION}.linux-${ARCH}.tar.gz
	terminate_if_error "Failed to Install Golang!"

	# Update PATH
	info_echo "Updating PATH${SYMBOL_WAITING}"
	case ${SHELL} in
		/usr/bin/zsh | /bin/zsh | zsh)
			echo "export PATH=\$PATH:/usr/local/go/bin" >> ${HOME}/.zshrc
		;;
		/usr/bin/bash | /bin/bash | bash)
			echo "export PATH=\$PATH:/usr/local/go/bin" >> ${HOME}/.bashrc
		;;
		*)
			error_echo "\n"
			terminate_with_error "Unsupported Default Shell!"
		;;
	esac
	terminate_if_error "Failed to Update PATH!"

	# Enable IP Forwading & Br_netfilter
	info_echo "Enabling IP Forwading & Br_netfilter${SYMBOL_WAITING}"
	sudo modprobe br_netfilter && sudo sysctl -w net.ipv4.ip_forward=1 # Enable IP Forwading & Br_netfilter instantly
	terminate_if_error "Failed to Enable IP Forwading & Br_netfilter!"

	info_echo "Ensuring Boot-Resistant${SYMBOL_WAITING}"
	echo "br_netfilter" | sudo tee /etc/modules-load.d/netfilter.conf && sudo sed -i 's/# *net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf && sudo sed -i 's/net.ipv4.ip_forward=0/net.ipv4.ip_forward=1/g' /etc/sysctl.conf # Ensure Boot-Resistant
	terminate_if_error "Failed to Enable IP Forwading & Br_netfilter!"

	# Install Kubeadm, Kubelet, Kubectl
	info_echo "Downloading Google Cloud Public Signing Key${SYMBOL_WAITING}"
	sudo mkdir -p /etc/apt/keyrings && sudo ${PROXY_CMD} curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list # Download the Google Cloud public signing key && Add the Kubernetes apt repository
	terminate_if_error "Failed to Download the Google Cloud public signing key && Add the Kubernetes apt repository!"

	sudo apt-mark unhold kubelet kubeadm kubectl
	info_echo "Installing Kubeadm, Kubelet, Kubectl${SYMBOL_WAITING}"
	install_package kubeadm=${KUBEADM_VERSION} kubelet=${KUBELET_VERSION} kubectl=${KUBECTL_VERSION} && sudo apt-mark hold kubelet kubeadm kubectl
	terminate_if_error "Failed to Install Kubeadm, Kubelet, Kubectl!"

	# Clean Up
	clean_tmp_dir
}

kubeadm_pre_pull () {

	# Initialize
	adapt_for_cn

	# Pre-Pull Required Images
	info_echo "Pre-Pulling Required Images${SYMBOL_WAITING}"
	sudo kubeadm config images pull --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS}
	terminate_if_error "Failed to Pre-Pull Required Images!"
}

kubeadm_master_init () {
	
	funcArgc=$#

	# Initialize
	use_proxychains
	create_tmp_dir

	info_echo "kubeadm init${SYMBOL_WAITING}"
	if [ ${funcArgc} -eq 1 ]; then
		sudo kubeadm init --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS} --pod-network-cidr="10.244.0.0/16" --apiserver-advertise-address=${apiserverAdvertiseAddress} | tee -a ${PWD}/easyOpenYurtInfo.log > ${TMP_DIR}/masterNodeInfo
	else
		sudo kubeadm init --kubernetes-version ${KUBE_VERSION} ${KUBEADM_INIT_IMG_REPO_ARGS} --pod-network-cidr="10.244.0.0/16" | tee -a ${PWD}/easyOpenYurtInfo.log > ${TMP_DIR}/masterNodeInfo
	fi
	terminate_if_error "kubeadm init Failed!"

	# Make kubectl Work for Non-Root User
	info_echo "Making kubectl Work for Non-Root User${SYMBOL_WAITING}"
	mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown "$(id -u)":"$(id -g)" $HOME/.kube/config
	terminate_if_error "Failed to Make kubectl Work for Non-Root User!"

	# Install Pod Network
	info_echo "Installing Pod Network${SYMBOL_WAITING}"
	${PROXY_CMD} kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
	terminate_if_error "Failed to Install Pod Network!"

	# Extract Master Node Information from Logs
	info_echo "Extracting Master Node Information from Logs${SYMBOL_WAITING}"
	ipPortToken=$(sed -n "/.*kubeadm join.*/p" < ${TMP_DIR}/masterNodeInfo | sed -n "s/.*join \(.*\):\(\S*\) --token \(\S*\).*/\1 \2 \3/p") && discoveryTokenHash=$(sed -n "/.*sha256:.*/p" < ${TMP_DIR}/masterNodeInfo | sed -n "s/.*\(sha256:\S*\).*/\1/p") && write_master_node_info_to_yaml ${ipPortToken} ${discoveryTokenHash}
	terminate_if_error "Failed to Extract Master Node Information from Logs!"
	success_echo "Master Node Key Information has been Written to ${PWD}/masterKey.yaml! You can Check for Details.\n"

	# Clean Up
	clean_tmp_dir
}

kubeadm_worker_join () {
	# Join Kubernetes Cluster
	info_echo "Joining Kubernetes Cluster${SYMBOL_WAITING}"
	sudo kubeadm join ${controlPlaneHost}:${controlPlanePort} --token ${controlPlaneToken} --discovery-token-ca-cert-hash ${discoveryTokenHash}
	terminate_if_error "Failed to Join Kubernetes Cluster"
}

yurt_master_init () {

	# Initialize
	use_proxychains
	create_tmp_dir
	
	# Treat Master as Cloud Node
	treat_master_as_cloud

	# Install Helm
	info_echo "Downloading Public Signing Key && Add the Helm Apt Repository${SYMBOL_WAITING}"
	download_to_tmp https://baltocdn.com/helm/signing.asc && sudo mkdir -p /usr/share/keyrings && cat ${TMP_DIR}/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
	terminate_if_error "Failed to Download Public Signing Key && Add the Helm Apt Repository!"

	info_echo "Installing Helm${SYMBOL_WAITING}"
	install_package apt-transport-https && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list && install_package helm
	terminate_if_error "Failed to Install Helm!"

	# Install Kustomize
	info_echo "Installing Kustomize${SYMBOL_WAITING}"
	download_to_tmp "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" && chmod u+x ${TMP_DIR}/install_kustomize.sh && ${TMP_DIR}/install_kustomize.sh ${TMP_DIR} && sudo cp ${TMP_DIR}/kustomize /usr/local/bin
	terminate_if_error "Failed to Install Kustomize!"

	# Add OpenYurt Repo with Helm
	info_echo "Adding OpenYurt Repo with Helm${SYMBOL_WAITING}"
	helm repo add openyurt https://openyurtio.github.io/openyurt-helm
	terminate_if_error "Failed to Add OpenYurt Repo with Helm"

	# Deploy yurt-app-manager
	info_echo "Deploying yurt-app-manager${SYMBOL_WAITING}"
	helm upgrade --install yurt-app-manager -n kube-system openyurt/yurt-app-manager
	terminate_if_error "Failed to Deploy yurt-app-manager!"
	kubectl get pod -n kube-system | grep yurt-app-manager	# For log
	kubectl get svc -n kube-system | grep yurt-app-manager	# For log

	# Create NodePool
	info_echo "Creating NodePool${SYMBOL_WAITING}"
	waitCount=1
	while [ "$(kubectl get pod -n kube-system | grep yurt-app-manager | sed -n "s/\s*\(\S*\)\s*\(\S*\)\s*\(\S*\).*/\2 \3/p")" != "1/1 Running" ]
	do
		warn_echo "Waiting for yurt-app-manager to be Ready [${waitCount}s]\n"
		((waitCount=waitCount+1))
		sleep 1
	done
	kubectl apply -f ${TEMPLATE_DIR}/masterNodePoolTemplate.yaml
	kubectl apply -f ${TEMPLATE_DIR}/workerNodePoolTemplate.yaml
	terminate_if_error "Failed to Create NodePool!"

	# Add Current Node into NodePool
	info_echo "Adding Current Node into NodePool${SYMBOL_WAITING}"
	currentNodeName=$(kubectl get nodes | sed -n "/.*control.*\|.*master.*/p" | head -1 | sed -n "s/\s*\(\S*\).*/\1/p") && kubectl label node ${currentNodeName} apps.openyurt.io/desired-nodepool=master
	terminate_if_error "Failed to Add Current Node into NodePool!"

	# Deploy yurt-controller-manager
	info_echo "Deploying yurt-controller-manager${SYMBOL_WAITING}"
	helm upgrade --install openyurt -n kube-system openyurt/openyurt
	terminate_if_error "Failed to Deploy yurt-controller-manager!"
	helm list -A # For log

	# Setup raven-controller-manager Component
	info_echo "Cloning Repo: raven-controller-manager${SYMBOL_WAITING}"
	git clone --quiet https://github.com/openyurtio/raven-controller-manager.git ${TMP_DIR}/raven-controller-manager
	terminate_if_error "Failed to clone Clone Repo: raven-controller-manager!"

	info_echo "Deploying raven-controller-manager${SYMBOL_WAITING}"
	pushd ${TMP_DIR}/raven-controller-manager && git checkout v0.3.0 && make generate-deploy-yaml && kubectl apply -f _output/yamls/raven-controller-manager.yaml && popd
	terminate_if_error "Failed to Deploy raven-controller-manager!"

	# Setup raven-agent Component
	info_echo "Cloning Repo: raven-agent${SYMBOL_WAITING}"
	git clone --quiet https://github.com/openyurtio/raven.git ${TMP_DIR}/raven-agent
	terminate_if_error "Failed to Clone Repo: raven-agent!"

	info_echo "Deploying raven-agent${SYMBOL_WAITING}"
	pushd ${TMP_DIR}/raven-agent && git checkout v0.3.0 && FORWARD_NODE_IP=true make deploy && popd
	terminate_if_error "Failed to Deploy raven-controller-manager!"

	clean_tmp_dir
}

yurt_master_expand () {

	# Initialize
	isEdgeWorker=$1
	nodeName=$2

	# Label Worker Node as Cloud/Edge
	info_echo "Labeling Node: ${nodeName} as ${nodeType}${SYMBOL_WAITING}"
	kubectl label node ${nodeName} openyurt.io/is-edge-worker=${isEdgeWorker}
	terminate_if_error "Failed to Label Node: ${nodeName} as ${nodeType}"

	# Activate the Node Autonomous Mode
	info_echo "Activating the Autonomous Mode of Node: ${nodeName}${SYMBOL_WAITING}"
	kubectl annotate node ${nodeName} node.beta.openyurt.io/autonomy=true
	terminate_if_error "Failed to Activate the Node Autonomous Mode!"

	# Add Worker Node into NodePool
	info_echo "Adding Worker Node into NodePool${SYMBOL_WAITING}"
	kubectl label node ${nodeName} apps.openyurt.io/desired-nodepool=worker
	terminate_if_error "Failed to Add Worker Node into NodePool!"

	# Wait for Worker Node to be Ready
	waitCount=1
	while [ "$(kubectl get nodes | sed -n "/.*${nodeName}.*/p" | sed -n "s/\s*\(\S*\)\s*\(\S*\).*/\2/p")" != "Ready" ]
	do
		warn_echo "Waiting for Worker Node to be Ready [${waitCount}s]\n"
		((waitCount=waitCount+1))
		sleep 1
	done

	# Restart Pods in the Worker Node
	info_echo "Restarting Pods in the Worker Node${SYMBOL_WAITING}"
	existingPods=$(kubectl get pod -A -o wide | grep ${nodeName})
	originalIFS=${IFS}	# Save IFS
	IFS=$'\n'
	while read -r pod
	do
		if [ -z "$(echo ${pod} | sed -n "/.*yurt-hub.*/p")" ]; then
			podNameSpace=$(echo ${pod} | sed -n "s/\s*\(\S*\)\s*\(\S*\).*/\1/p")
			podName=$(echo ${pod} | sed -n "s/\s*\(\S*\)\s*\(\S*\).*/\2/p")
			info_echo "Restarting Pod: ${podNameSpace}=>${podName}${SYMBOL_WAITING}"
			kubectl -n ${podNameSpace} delete pod ${podName}
			terminate_if_error "Failed to Restart Pods in the Worker Node!"
		fi
	done <<< ${existingPods}
	IFS=${originalIFS}	# Restore IFS
}

yurt_worker_join () {

	# Initialize
	controlPlaneHost=$1
	controlPlanePort=$2
	controlPlaneToken=$3
	create_tmp_dir

	# Set up Yurthub
	info_echo "Setting up Yurthub${SYMBOL_WAITING}"
	cat ${TEMPLATE_DIR}/yurthubTemplate.yaml | sed -e "s|__kubernetes_master_address__|${controlPlaneHost}:${controlPlanePort}|" -e "s|__bootstrap_token__|${controlPlaneToken}|" > ${TMP_DIR}/yurthub-ack.yaml && sudo cp ${TMP_DIR}/yurthub-ack.yaml /etc/kubernetes/manifests
	terminate_if_error "Failed to Set up Yurthub!"

	# Configure Kubelet
	info_echo "Configuring Kubelet${SYMBOL_WAITING}"
	sudo mkdir -p /var/lib/openyurt && sudo cp ${TEMPLATE_DIR}/kubeletTemplate.conf /var/lib/openyurt/kubelet.conf && \
	sudo sed -i "s|KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=\/etc\/kubernetes\/bootstrap-kubelet.conf\ --kubeconfig=\/etc\/kubernetes\/kubelet.conf|KUBELET_KUBECONFIG_ARGS=--kubeconfig=\/var\/lib\/openyurt\/kubelet.conf|g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf && \
	sudo systemctl daemon-reload && sudo systemctl restart kubelet
	terminate_if_error "Failed to Configure Kubelet!"

	# Clean Up
	clean_tmp_dir
}

# Print Warn and Info
print_welcome
print_start_warning
print_start_info

# Detect Arch & OS
detect_arch
detect_os
# Check Arguments
if [ ${argc} -lt 3 ]; then
	print_general_usage
	terminate_with_error "Too Few Arguments!"
fi

# Process Arguments
case ${operationObject} in
	system)
		case ${nodeRole} in
			master | worker)
				if [ "${operation}" != "init" ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init\n"
					terminate_with_error "Invalid Operation: [operation]->${operation}"
				fi
				if [ ${argc} -ne 3 ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init\n"
					terminate_with_error "Invalid Arguments: Too Many Arguments!"
				fi
				system_init
				exit_with_success_info "Init System Successfully!"
			;;
			*)
				print_general_usage
				terminate_with_error "Invalid NodeRole: [nodeRole]->${nodeRole}"
			;;
		esac
	;;
    kube)
		case ${nodeRole} in
			master)
				if [ "${operation}" != "init" ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init <serverAdvertiseAddress>\n"
					terminate_with_error "Invalid Operation: [operation]->${operation}"
				fi
				if [ ${argc} -gt 4 ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} init <serverAdvertiseAddress>\n"
					terminate_with_error "Invalid Arguments: Too Many Arguments!"
				fi
				# kubeadm init
				kubeadm_pre_pull # Pre-Pull Required Images
				if [ ${argc} -eq 4 ]; then
					kubeadm_master_init ${apiserverAdvertiseAddress}
				else
					kubeadm_master_init
				fi
				exit_with_success_info "Successfully Init Kubernetes Cluster Master Node!"
			;;
			worker)
				if [ "${operation}" != "join" ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken] [discoveryTokenHash]\n"
					terminate_with_error "Invalid Operation: [operation]->${operation}"
				fi
				if [ ${argc} -ne 7 ]; then
					info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken] [discoveryTokenHash]\n"
					terminate_with_error "Invalid Arguments: Need 7, Got ${argc}"
				fi
				# kubeadm join
				kubeadm_worker_join ${controlPlaneHost} ${controlPlanePort} ${controlPlaneToken} ${discoveryTokenHash}
				exit_with_success_info "Join Kubernetes Cluster Successfully!"
			;;
			*)
				print_general_usage
				terminate_with_error "Invalid NodeRole: [nodeRole]->${nodeRole}"
			;;
		esac
    ;;
    yurt)
		case ${nodeRole} in
			master)
				case ${operation} in
					init)
						yurt_master_init
						exit_with_success_info "Successfully Init OpenYurt Cluster Master Node!"
					;;
					expand)
						if [ ${argc} -ne 5 ]; then
							info_echo "Usage: $0 ${operationObject} ${nodeRole} expand [nodeType: edge | cloud] [nodeName]\n"
							terminate_with_error "Invalid Arguments: Need 5, Got ${argc}"
						fi
						case ${nodeType} in
							edge)	isEdgeWorker=true ;;
							cloud)	isEdgeWorker=false ;;
							*)
								info_echo "Usage: $0 ${operationObject} ${nodeRole} expand [nodeType: edge | cloud] [nodeName]\n"
								terminate_with_error "Invalid NodeType: [nodeType]->${nodeType}"
							;;
						esac
						yurt_master_expand ${isEdgeWorker} ${nodeName}
						exit_with_success_info "Successfully Expand OpenYurt to Node[${nodeName}] as Type[${nodeType}]"
					;;
					*)
						info_echo "Usage: $0 ${operationObject} ${nodeRole} [init | expand] <Args...>\n"
						terminate_with_error "Invalid Operation: [operation]->${operation}"
					;;
				esac
			;;
			worker)
				case ${operation} in
					join)
						if [ ${argc} -ne 6 ]; then
							info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken]\n"
							terminate_with_error "Invalid Arguments: Need 6, Got ${argc}"
						fi
						yurt_worker_join ${controlPlaneHost} ${controlPlanePort} ${controlPlaneToken}
						exit_with_success_info "Successfully Joined OpenYurt Cluster!"
					;;
					*)
						info_echo "Usage: $0 ${operationObject} ${nodeRole} join [controlPlaneHost] [controlPlanePort] [controlPlaneToken]\n"
						terminate_with_error "Invalid Operation: [operation]->${operation}"
					;;
				esac
			;;
			*)
				print_general_usage
				terminate_with_error "Invalid NodeRole: [nodeRole]->${nodeRole}"
			;;
		esac
    ;;
    *)
        print_general_usage
		terminate_with_error "Invalid Object: [object]->${operationObject}"
	;;
esac
