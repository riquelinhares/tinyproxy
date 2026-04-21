#!/bin/bash
set -e

# ── configuração ──────────────────────────────────────────
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REPO="tinyproxy"
IMAGE_TAG="latest"
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"

echo "→ Account: ${AWS_ACCOUNT_ID}"
echo "→ Region:  ${AWS_REGION}"
echo "→ Image:   ${IMAGE_URI}"
echo ""

# ── gera senha aleatória ──────────────────────────────────
TINYPROXY_PASSWORD=$(openssl rand -hex 16)
echo "→ Senha gerada: ${TINYPROXY_PASSWORD}"
echo ""

# ── ECR: cria repositório se não existir ──────────────────
echo "[1/6] Verificando repositório ECR..."
aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${AWS_REGION}" > /dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${ECR_REPO}" --region "${AWS_REGION}"

# ── ECR: login ────────────────────────────────────────────
echo "[2/6] Autenticando no ECR..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin \
  "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# ── Docker: build e push ──────────────────────────────────
echo "[3/6] Build e push da imagem..."
docker build -t "${ECR_REPO}:${IMAGE_TAG}" ./docker
docker tag "${ECR_REPO}:${IMAGE_TAG}" "${IMAGE_URI}"
docker push "${IMAGE_URI}"

# ── Kubernetes: secret com a senha ───────────────────────
echo "[4/6] Criando Secret com a senha..."
export TINYPROXY_PASSWORD
envsubst < k8s/secret.yaml # pre-visualização
envsubst < k8s/secret.yaml | kubectl apply -f -

# ── Kubernetes: configmap e demais manifests ──────────────
echo "[5/6] Aplicando manifests no K8S..."
export AWS_ACCOUNT_ID AWS_REGION
kubectl apply -f k8s/configmap.yaml
envsubst < k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/service.yaml

# ── Aguarda pod ficar pronto ──────────────────────────────
echo "[6/6] Aguardando pod ficar pronto..."
kubectl rollout status deployment/tinyproxy --timeout=90s

# ── instruções de uso ─────────────────────────────────────
echo ""
echo "✅ Deploy concluído!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Terminal 1 — manter o tunnel aberto:"
echo "  kubectl port-forward svc/tinyproxy 8888:8888"
echo ""
echo "Terminal 2 — exportar antes de usar:"
echo "  export HTTP_PROXY=http://proxy:${TINYPROXY_PASSWORD}@localhost:8888"
echo "  export HTTPS_PROXY=http://proxy:${TINYPROXY_PASSWORD}@localhost:8888"
echo "  export NO_PROXY=localhost,127.0.0.1,169.254.169.254,.amazonaws.com,.internal"
echo ""
echo "Ou por comando isolado (recomendado):"
echo "  HTTPS_PROXY=http://proxy:${TINYPROXY_PASSWORD}@localhost:8888 \\"
echo "  HTTP_PROXY=http://proxy:${TINYPROXY_PASSWORD}@localhost:8888 \\"
echo "  terraform init"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
