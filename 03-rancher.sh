#!/bin/bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: use sudo bash"; exit 1; }

export PATH="$PATH:/var/lib/rancher/rke2/bin"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

RANCHER_HOST="${RANCHER_HOST:-}"
if [ -z "$RANCHER_HOST" ]; then
  read -r -p "Rancher hostname (example: rancher.yourdomain.com): " RANCHER_HOST < /dev/tty
fi
[[ "$RANCHER_HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]] || { echo "That hostname looks invalid: $RANCHER_HOST"; exit 1; }

kubectl get nodes > /dev/null

PASS="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"

kubectl apply -f - <<EOF
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: rancher
  namespace: kube-system
spec:
  repo: https://releases.rancher.com/server-charts/stable
  chart: rancher
  targetNamespace: cattle-system
  createNamespace: true
  valuesContent: |-
    hostname: ${RANCHER_HOST}
    replicas: 1
    tls: external
    bootstrapPassword: ${PASS}
    ingress:
      enabled: false
EOF

echo "Waiting for Rancher to be created (this can take 5 to 10 minutes)..."
for _ in $(seq 1 60); do
  kubectl -n cattle-system get deployment rancher > /dev/null 2>&1 && break
  sleep 5
done
kubectl -n cattle-system rollout status deployment/rancher --timeout=900s

echo
echo "Done: Rancher is running."
echo "Hostname:           ${RANCHER_HOST}"
echo "Bootstrap password: ${PASS}"
echo "Tunnel target (add in Cloudflare): http://rancher.cattle-system.svc.cluster.local:80"
