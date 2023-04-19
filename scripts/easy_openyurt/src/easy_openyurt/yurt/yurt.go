// Author: Haoyuan Ma <flyinghorse0510@zju.edu.cn>
package yurt

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	configs "gogs.infcompute.com/mhy/easy_openyurt/src/easy_openyurt/configs"
	logs "gogs.infcompute.com/mhy/easy_openyurt/src/easy_openyurt/logs"
	system "gogs.infcompute.com/mhy/easy_openyurt/src/easy_openyurt/system"
	template "gogs.infcompute.com/mhy/easy_openyurt/src/easy_openyurt/template"
)

// Parse parameters for subcommand `yurt`
func ParseSubcommandYurt(args []string) {
	nodeRole := args[0]
	operation := args[1]
	var help bool
	// Add parameters to flag set
	yurtFlagsName := fmt.Sprintf("%s yurt %s %s", os.Args[0], nodeRole, operation)
	yurtFlags := flag.NewFlagSet(yurtFlagsName, flag.ExitOnError)
	yurtFlags.BoolVar(&help, "help", false, "Show help")
	yurtFlags.BoolVar(&help, "h", false, "Show help")
	switch nodeRole {
	case "master":
		// Parse parameters for `yurt master init`
		if operation == "init" {
			yurtFlags.BoolVar(&configs.Yurt.MasterAsCloud, "master-as-cloud", configs.Yurt.MasterAsCloud, "Treat master as cloud node")
			yurtFlags.Parse(args[2:])
			// Show help
			if help {
				yurtFlags.Usage()
				os.Exit(0)
			}
			YurtMasterInit()
			logs.SuccessPrintf("Successfully init OpenYurt cluster master node!\n")
		} else if operation == "expand" {
			// Parse parameters for `yurt master expand`
			yurtFlags.BoolVar(&configs.Yurt.WorkerAsEdge, "worker-as-edge", configs.Yurt.WorkerAsEdge, "Treat worker as edge node")
			yurtFlags.StringVar(&configs.Yurt.WorkerNodeName, "worker-node-name", configs.Yurt.WorkerNodeName, "Worker node name(**REQUIRED**)")
			yurtFlags.Parse(args[2:])
			// Show help
			if help {
				yurtFlags.Usage()
				os.Exit(0)
			}
			// Check required parameters
			if len(configs.Yurt.WorkerNodeName) == 0 {
				yurtFlags.Usage()
				logs.FatalPrintf("Parameter --worker-node-name needed!\n")
			}
			YurtMasterExpand()
			logs.SuccessPrintf("Successfully expand OpenYurt to node [%s]!\n", configs.Yurt.WorkerNodeName)
		} else {
			logs.InfoPrintf("Usage: %s %s %s <init | expand> [parameters...]\n", os.Args[0], os.Args[1], nodeRole)
			logs.FatalPrintf("Invalid operation: <operation> -> %s\n", operation)
		}
	case "worker":
		// Parse parameters for `yurt worker join`
		if operation != "join" {
			logs.InfoPrintf("Usage: %s %s %s join [parameters...]\n", os.Args[0], os.Args[1], nodeRole)
			logs.FatalPrintf("Invalid operation: <operation> -> %s\n", operation)
		}
		yurtFlags.StringVar(&configs.Kube.ApiserverAdvertiseAddress, "apiserver-advertise-address", configs.Kube.ApiserverAdvertiseAddress, "Kubernetes API server advertise address (**REQUIRED**)")
		yurtFlags.StringVar(&configs.Kube.ApiserverPort, "apiserver-port", configs.Kube.ApiserverPort, "Kubernetes API server port")
		yurtFlags.StringVar(&configs.Kube.ApiserverToken, "apiserver-token", configs.Kube.ApiserverToken, "Kubernetes API server token (**REQUIRED**)")
		yurtFlags.Parse(args[2:])
		// Show help
		if help {
			yurtFlags.Usage()
			os.Exit(0)
		}
		// Check required parameters
		if len(configs.Kube.ApiserverAdvertiseAddress) == 0 {
			yurtFlags.Usage()
			logs.FatalPrintf("Parameter --apiserver-advertise-address needed!\n")
		}
		if len(configs.Kube.ApiserverToken) == 0 {
			yurtFlags.Usage()
			logs.FatalPrintf("Parameter --apiserver-token needed!\n")
		}
		YurtWorkerJoin()
		logs.SuccessPrintf("Successfully joined OpenYurt cluster!\n")
	default:
		logs.InfoPrintf("Usage: %s %s <master | worker> <init | join | expand> [parameters...]\n", os.Args[0], os.Args[1])
		logs.FatalPrintf("Invalid nodeRole: <nodeRole> -> %s\n", nodeRole)
	}
}

func CheckYurtMasterEnvironment() {

	// Check environment
	var err error
	logs.InfoPrintf("Checking system environment...\n")

	// Check Helm
	_, err = exec.LookPath("helm")
	if err != nil {
		logs.WarnPrintf("Helm not found! Helm will be automatically installed!\n")
	} else {
		logs.SuccessPrintf("Helm found!\n")
		configs.Yurt.HelmInstalled = true
	}

	// Check Kustomize
	_, err = exec.LookPath("kustomize")
	if err != nil {
		logs.WarnPrintf("Kustomize not found! Kustomize will be automatically installed!\n")
	} else {
		logs.SuccessPrintf("Kustomize found!\n")
		configs.Yurt.KustomizeInstalled = true
	}

	// Add OS-specific dependencies to installation lists
	switch configs.System.CurrentOS {
	case "ubuntu":
		configs.Yurt.Dependencies = "curl apt-transport-https ca-certificates build-essential git"
	case "rocky linux":
		configs.Yurt.Dependencies = ""
	case "centos":
		configs.Yurt.Dependencies = ""
	default:
		logs.FatalPrintf("Unsupported OS: %s\n", configs.System.CurrentOS)
	}

	logs.SuccessPrintf("Finished checking system environment!\n")
}

// Initialize Openyurt on master node
func YurtMasterInit() {
	// Initialize
	var err error
	CheckYurtMasterEnvironment()
	system.CreateTmpDir()
	defer system.CleanUpTmpDir()

	// Install dependencies
	logs.WaitPrintf("Installing dependencies")
	err = system.InstallPackages(configs.Yurt.Dependencies)
	logs.CheckErrorWithTagAndMsg(err, "Failed to install dependencies!\n")

	// Treat master as cloud node
	if configs.Yurt.MasterAsCloud {
		logs.WarnPrintf("Master node WILL also be treated as a cloud node!\n")
		system.ExecShellCmd("kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule-")
		system.ExecShellCmd("kubectl taint nodes --all node-role.kubernetes.io/control-plane-")
	}

	// Install helm
	if !configs.Yurt.HelmInstalled {
		switch configs.System.CurrentOS {
		case "ubuntu":
			// Download public signing key && Add the Helm apt repository
			logs.WaitPrintf("Downloading public signing key && Add the Helm apt repository")
			// Download public signing key
			filePathName, err := system.DownloadToTmpDir(configs.Yurt.HelmPublicSigningKeyDownloadUrl)
			logs.CheckErrorWithMsg(err, "Failed to download public signing key && add the Helm apt repository!\n")
			_, err = system.ExecShellCmd("sudo mkdir -p /usr/share/keyrings && cat %s | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null", filePathName)
			logs.CheckErrorWithMsg(err, "Failed to download public signing key && add the Helm apt repository!\n")
			// Add the Helm apt repository
			_, err = system.ExecShellCmd(`echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list`)
			logs.CheckErrorWithTagAndMsg(err, "Failed to download public signing key && add the Helm apt repository!\n")
			// Install helm
			logs.WaitPrintf("Installing Helm")
			err = system.InstallPackages("helm")
			logs.CheckErrorWithTagAndMsg(err, "Failed to install helm!\n")
		default:
			logs.FatalPrintf("Unsupported Linux distribution: %s\n", configs.System.CurrentOS)
		}
	}

	// Install kustomize
	if !configs.Yurt.KustomizeInstalled {
		// Download kustomize helper script
		logs.WaitPrintf("Downloading kustomize")
		filePathName, err := system.DownloadToTmpDir(configs.Yurt.KustomizeScriptDownloadUrl)
		logs.CheckErrorWithMsg(err, "Failed to download kustomize!\n")
		// Download kustomize
		_, err = system.ExecShellCmd("chmod u+x %s && %s %s", filePathName, filePathName, configs.System.TmpDir)
		logs.CheckErrorWithTagAndMsg(err, "Failed to download kustomize!\n")
		// Install kustomize
		logs.WaitPrintf("Installing kustomize")
		_, err = system.ExecShellCmd("sudo cp %s /usr/local/bin", configs.System.TmpDir+"/kustomize")
		logs.CheckErrorWithTagAndMsg(err, "Failed to Install kustomize!\n")
	}

	// Add OpenYurt repo with helm
	logs.WaitPrintf("Adding OpenYurt repo(version %s) with helm", configs.Yurt.YurtVersion)
	_, err = system.ExecShellCmd("git clone --quiet https://github.com/openyurtio/openyurt-helm.git %s/openyurt-helm && pushd %s/openyurt-helm && git checkout openyurt-%s && popd", configs.System.TmpDir, configs.System.TmpDir, configs.Yurt.YurtVersion)
	logs.CheckErrorWithTagAndMsg(err, "Failed to add OpenYurt repo with helm!\n")

	// Deploy yurt-app-manager
	logs.WaitPrintf("Deploying yurt-app-manager")
	_, err = system.ExecShellCmd("helm install yurt-app-manager -n kube-system %s/openyurt-helm/charts/yurt-app-manager", configs.System.TmpDir)
	logs.CheckErrorWithTagAndMsg(err, "Failed to deploy yurt-app-manager!\n")

	// Wait for yurt-app-manager to be ready
	logs.WaitPrintf("Waiting for yurt-app-manager to be ready")
	waitCount := 1
	for {
		yurtAppManagerStatus, err := system.ExecShellCmd(`kubectl get pod -n kube-system | grep yurt-app-manager | sed -n "s/\s*\(\S*\)\s*\(\S*\)\s*\(\S*\).*/\2 \3/p"`)
		logs.CheckErrorWithMsg(err, "Failed to wait for yurt-app-manager to be ready!\n")
		if yurtAppManagerStatus == "1/1 Running" {
			logs.SuccessPrintf("\n")
			break
		} else {
			logs.WarnPrintf("Waiting for yurt-app-manager to be ready [%ds]\n", waitCount)
			waitCount += 1
			time.Sleep(time.Second)
		}
	}

	// Deploy yurt-controller-manager
	logs.WaitPrintf("Deploying yurt-controller-manager")
	_, err = system.ExecShellCmd("helm install openyurt %s/openyurt-helm/charts/openyurt -n kube-system", configs.System.TmpDir)
	logs.CheckErrorWithTagAndMsg(err, "Failed to deploy yurt-controller-manager!\n")

	// Setup raven-controller-manager Component
	// Clone repository
	logs.WaitPrintf("Cloning repo: raven-controller-manager")
	_, err = system.ExecShellCmd("git clone --quiet https://github.com/openyurtio/raven-controller-manager.git %s/raven-controller-manager", configs.System.TmpDir)
	logs.CheckErrorWithTagAndMsg(err, "Failed to clone repo: raven-controller-manager!\n")
	// Deploy raven-controller-manager
	logs.WaitPrintf("Deploying raven-controller-manager")
	_, err = system.ExecShellCmd("pushd %s/raven-controller-manager && git checkout v0.3.0 && make generate-deploy-yaml && kubectl apply -f _output/yamls/raven-controller-manager.yaml && popd", configs.System.TmpDir)
	logs.CheckErrorWithTagAndMsg(err, "Failed to deploy raven-controller-manager!\n")

	// Setup raven-agent Component
	// Clone repository
	logs.WaitPrintf("Cloning repo: raven-agent")
	_, err = system.ExecShellCmd("git clone --quiet https://github.com/openyurtio/raven.git %s/raven-agent", configs.System.TmpDir)
	logs.CheckErrorWithTagAndMsg(err, "Failed to clone repo: raven-agent!\n")
	// Deploy raven-agent
	logs.WaitPrintf("Deploying raven-agent")
	_, err = system.ExecShellCmd("pushd %s/raven-agent && git checkout v0.3.0 && FORWARD_NODE_IP=true make deploy && popd", configs.System.TmpDir)
	logs.CheckErrorWithTagAndMsg(err, "Failed to deploy raven-agent!\n")
}

// Expand Openyurt to worker node
func YurtMasterExpand() {
	// Initialize
	var err error
	var workerAsEdge string

	// Label worker node as cloud/edge
	logs.WaitPrintf("Labeling worker node: %s", configs.Yurt.WorkerNodeName)
	if configs.Yurt.WorkerAsEdge {
		workerAsEdge = "true"
	} else {
		workerAsEdge = "false"
	}
	_, err = system.ExecShellCmd("kubectl label node %s openyurt.io/is-edge-worker=%s --overwrite", configs.Yurt.WorkerNodeName, workerAsEdge)
	logs.CheckErrorWithTagAndMsg(err, "Failed to label worker node!\n")

	// Activate the node autonomous mode
	logs.WaitPrintf("Activating the node autonomous mode")
	_, err = system.ExecShellCmd("kubectl annotate node %s node.beta.openyurt.io/autonomy=true --overwrite", configs.Yurt.WorkerNodeName)
	logs.CheckErrorWithTagAndMsg(err, "Failed to activate the node autonomous mode!\n")

	// Wait for worker node to be Ready
	logs.WaitPrintf("Waiting for worker node to be ready")
	waitCount := 1
	for {
		workerNodeStatus, err := system.ExecShellCmd(`kubectl get nodes | sed -n "/.*%s.*/p" | sed -n "s/\s*\(\S*\)\s*\(\S*\).*/\2/p"`, configs.Yurt.WorkerNodeName)
		logs.CheckErrorWithMsg(err, "Failed to wait for worker node to be ready!\n")
		if workerNodeStatus == "Ready" {
			logs.SuccessPrintf("\n")
			break
		} else {
			logs.WarnPrintf("Waiting for worker node to be ready [%ds]\n", waitCount)
			waitCount += 1
			time.Sleep(time.Second)
		}
	}

	// Restart pods in the worker node
	logs.WaitPrintf("Restarting pods in the worker node")
	shellOutput, err := system.ExecShellCmd(template.GetRestartPodsShell(), configs.Yurt.WorkerNodeName)
	logs.CheckErrorWithMsg(err, "Failed to restart pods in the worker node!\n")
	podsToBeRestarted := strings.Split(shellOutput, "\n")
	for _, pods := range podsToBeRestarted {
		podsInfo := strings.Split(pods, " ")
		logs.WaitPrintf("Restarting pod: %s => %s", podsInfo[0], podsInfo[1])
		_, err = system.ExecShellCmd("kubectl -n %s delete pod %s", podsInfo[0], podsInfo[1])
		logs.CheckErrorWithTagAndMsg(err, "Failed to restart pods in the worker node!\n")
	}
}

// Join existing Kubernetes worker node to Openyurt cluster
func YurtWorkerJoin() {

	// Initialize
	var err error

	// Set up Yurthub
	logs.WaitPrintf("Setting up Yurthub")
	_, err = system.ExecShellCmd(
		"echo '%s' | sed -e 's|__kubernetes_master_address__|%s:%s|' -e 's|__bootstrap_token__|%s|' | sudo tee /etc/kubernetes/manifests/yurthub-ack.yaml",
		template.GetYurtHubConfig(),
		configs.Kube.ApiserverAdvertiseAddress,
		configs.Kube.ApiserverPort,
		configs.Kube.ApiserverToken)
	logs.CheckErrorWithTagAndMsg(err, "Failed to set up Yurthub!\n")

	// Configure Kubelet
	logs.WaitPrintf("Configuring kubelet")
	system.ExecShellCmd("sudo mkdir -p /var/lib/openyurt && echo '%s' | sudo tee /var/lib/openyurt/kubelet.conf", template.GetKubeletConfig())
	logs.CheckErrorWithMsg(err, "Failed to configure kubelet!\n")
	system.ExecShellCmd(`sudo sed -i "s|KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=\/etc\/kubernetes\/bootstrap-kubelet.conf\ --kubeconfig=\/etc\/kubernetes\/kubelet.conf|KUBELET_KUBECONFIG_ARGS=--kubeconfig=\/var\/lib\/openyurt\/kubelet.conf|g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf`)
	logs.CheckErrorWithMsg(err, "Failed to configure kubelet!\n")
	system.ExecShellCmd("sudo systemctl daemon-reload && sudo systemctl restart kubelet")
	logs.CheckErrorWithTagAndMsg(err, "Failed to configure kubelet!\n")
}
