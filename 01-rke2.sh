#!/bin/bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: use sudo bash"; exit 1; }

apt-get update -y
apt-get install -y curl wireguard-tools

mkdir -p /etc/rancher/rke2 /var/lib/rancher/rke2/server/manifests

cat > /etc/rancher/rke2/config.yaml <<'EOF'
cni: canal
EOF

cat > /var/lib/rancher/rke2/server/manifests/rke2-canal-config.yaml <<'EOF'
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-canal
  namespace: kube-system
spec:
  valuesContent: |-
    flannel:
      backend: "wireguard"
EOF

curl -sfL https://get.rke2.io | sh -
systemctl enable --now rke2-server

echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' > /etc/profile.d/rke2.sh
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> /etc/profile.d/rke2.sh
