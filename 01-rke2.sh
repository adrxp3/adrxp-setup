#!/bin/bash
set -e
mkdir -p /etc/rancher/rke2 /var/lib/rancher/rke2/server/manifests
echo "cni: canal" > /etc/rancher/rke2/config.yaml
cat > /var/lib/rancher/rke2/server/manifests/rke2-canal-config.yaml <<EOF
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
