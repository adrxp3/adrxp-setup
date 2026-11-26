#!/bin/bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: use sudo bash"; exit 1; }

export PATH="$PATH:/var/lib/rancher/rke2/bin"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

kubectl get nodes > /dev/null

apt-get update -y
apt-get install -y pciutils ubuntu-drivers-common

lspci | grep -i nvidia > /dev/null || { echo "No NVIDIA GPU found on this server (lspci shows none)."; exit 1; }

if ! nvidia-smi > /dev/null 2>&1; then
  if command -v mokutil > /dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -i enabled > /dev/null; then
    echo "Secure Boot is ON, which blocks the NVIDIA driver. Turn it off in the BIOS, then run this again."
    exit 1
  fi
  echo "NVIDIA driver is not working yet. Installing the recommended server driver..."
  ubuntu-drivers install --gpgpu
  echo
  echo "Driver installed. REBOOT now (sudo reboot), then run this same command again."
  exit 0
fi

echo "NVIDIA driver is working:"
nvidia-smi -L

CV="$(containerd --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
if [ -n "$CV" ]; then
  MAJOR="${CV#v}"
  MAJOR="${MAJOR%%.*}"
  if [ "$MAJOR" -lt 2 ]; then
    echo "containerd $CV is too old (the GPU operator needs 2.0 or newer). Upgrade RKE2 first."
    exit 1
  fi
fi

echo "Installing the NVIDIA GPU Operator. This restarts RKE2 once, so apps pause for a minute or two."

kubectl apply -f - <<'EOF'
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: gpu-operator
  namespace: kube-system
spec:
  repo: https://helm.ngc.nvidia.com/nvidia
  chart: gpu-operator
  version: v26.7.2
  targetNamespace: gpu-operator
  createNamespace: true
  valuesContent: |-
    driver:
      enabled: false
    toolkit:
      env:
      - name: CONTAINERD_SOCKET
        value: /run/k3s/containerd/containerd.sock
EOF

echo "Waiting for the GPU to show up in Kubernetes (can take 5 to 15 minutes)..."
GPUS=""
for _ in $(seq 1 120); do
  GPUS="$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)"
  [ -n "$GPUS" ] && [ "$GPUS" != "0" ] && break
  sleep 10
done

if [ -z "$GPUS" ] || [ "$GPUS" = "0" ]; then
  echo "The GPU has not appeared yet. Check progress with:  kubectl -n gpu-operator get pods"
  exit 1
fi

echo
echo "Done: Kubernetes sees ${GPUS} NVIDIA GPU(s) (nvidia.com/gpu)."
