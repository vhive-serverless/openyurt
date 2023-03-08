# EasyOpenYurt

## 1. Introduction

[OpenYurt](https://github.com/openyurtio/openyurt) is built based on upstream Kubernetes and has been designed to meet various DevOps requirements against typical edge infrastructures.

This script can help you to set up an OpenYurt cluster quickly and easily for development and test. It currently supports two main usages:

1. **From scratch**: Firstly set up a Kubernetes cluster using kubeadm and then deploy OpenYurt on it.
2. **Based on existing Kubernetes cluster**: Deploy OpenYurt directly on an existing Kubernetes cluster.

Additionally, several YAML template files which basically shows how to deploy services on OpenYurt are provided along with the script.

**Currently supported and tested platforms:**

|      OS      | ARCH  |
| :----------: | :---: |
| Ubuntu 22.04 | amd64 |
| Ubuntu 20.04 | amd64 |

**Currently supported and tested Shells:** `zsh`, `bash`

**<u>Warning:</u>** <u>This is an experimental script under development, **DO NOT** attempt to use it in production environment! Back up your system in advance to avoid possible damage.</u>

Finally, the script is well commented. You can look at the source and see what it is going to do before running. Have a good day!

## 2. Usage

**General Usage:**

```bash
./easyOpenYurt.sh [object: system | kube | yurt] [nodeRole: master | worker] [operation: init | join | expand] <Args...>
```

By default, **logs will be written into two files**: `easyOpenYurtErr.log` and `easyOpenYurtInfo.log` **in the current directory**.

### 2.1 Clone the Repo

```bash
git clone https://github.com/flyinghorse0510/easy_openyurt.git
cd easy_openyurt
chmod u+x easyOpenYurt.sh
```

### 2.2 Configure System on Master / Worker Node

> If you already have an existing kubernetes cluster, you can directly go to [2.4 Deploy OpenYurt on Kubernetes Cluster](#24-deploy-openyurt-on-kubernetes-cluster)

This procedure will install and configure required components in your system, such as:

- `containerd`
- `runc`
- `golang`
- `kubeadm`, `kubectl`, `kubelet`
- ……

To initialize your system, use the following command:

```bash
./easyOpenYurt.sh system master init # on the master node
./easyOpenYurt.sh system worker init # on the worker node
```

### 2.3 Set up Kubernetes Cluster

#### 2.3.1 Set up Master Node

On master node, use the following command:

```bash
./easyOpenYurt.sh kube master init
```

By default, [the `kubeadm` uses the network interface associated with the default gateway to set the advertise address for this particular control-plane(master) node's API server](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/). To use a different network interface, provide an extra parameter to the script:

```bash
./easyOpenYurt.sh kube master init <serverAdvertiseAddress>
# For example:
# ./easyOpenYurt.sh kube master init 192.168.18.2
```

If everything goes well, you can find one file called `masterKey.yaml` in the current directory, which includes information that can be subsequently used to set up the worker node in kubernetes cluster:

```yaml
# Content Template of `masterKey.yaml`
controlPlaneHost: xxx.xxx.xxx.xxx
controlPlanePort: xxxx
controlPlaneToken: xxxxxxxxxx
discoveryTokenHash: sha256:xxxxxxxxxx
```

#### 2.3.2 Set up Worker Node

On worker node, to join the kubernetes cluster, use the following command:

```bash
./easyOpenYurt.sh kube worker join [controlPlaneHost] [controlPlanePort] [controlPlaneToken] [discoveryTokenHash]
# You can find these parameters in file `masterKey.yaml` previously introduced on the master node
# For Example:
# ./easyOpenYurt.sh kube worker join 192.168.18.2 6443 xxxxxxxxxx sha256:xxxxxxxxxx
```

### 2.4 Deploy OpenYurt on Kubernetes Cluster

#### 2.4.1 Deploy on Master Node

On master node, to deploy OpenYurt, use the following command:

```bash
./easyOpenYurt.sh yurt master init
```

#### 2.4.2 Deploy on Worker Node

**<u>Warning:</u>** <u>You should **ONLY** deploy OpenYurt on nodes that already have been joined in the Kubernetes cluster.</u>

**<u>Firstly, on the worker node</u>**, use the following command:

```bash
./easyOpenYurt.sh yurt worker join [controlPlaneHost] [controlPlanePort] [controlPlaneToken]
# You can find these parameters in file `masterKey.yaml` previously introduced on the master node
# For Example:
# ./easyOpenYurt.sh yurt worker join 192.168.18.2 6443 xxxxxxxxxx
```

**<u>Then, on the master node,</u>** use the following command:

```bash
./easyOpenYurt.sh yurt master expand [nodeType: edge | cloud] [nodeName]
# [nodeType] is the type of the worker node when joining the OpenYurt cluster (edge / cloud)
# [nodeName] is the name of the worker node that you want to join to the OpenYurt cluster
# For example:
# ./easyOpenYurt.sh yurt master expand edge myEdgeNode0
```

## 3. License

See the [LICENSE](https://github.com/vhive-serverless/openyurt/blob/master/LICENSE) file for details