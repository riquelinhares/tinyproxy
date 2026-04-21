# tinyproxy-K8S

Proxy HTTP/HTTPS

## Estrutura

```
tinyproxy-K8S/
├── docker/
│   └── Dockerfile          # imagem Alpine + tinyproxy
├── k8s/
│   ├── configmap.yaml      # configuração do tinyproxy
│   ├── deployment.yaml     # deployment no K8S
│   ├── secret.yaml         # senha do proxy (não commitar com valor real)
│   └── service.yaml        # service ClusterIP
├── scripts/
│   └── deploy.sh           # build, push ECR e apply k8s
└── .github/
    └── workflows/
        └── release.yaml    # build e push automático ao criar tag
```

## Pré-requisitos

- `aws cli` configurado com acesso ao ECR e K8S
- `docker` instalado e rodando
- `kubectl` apontando pro cluster K8S correto
- `envsubst` instalado (`brew install gettext` no macOS)

## Teste local

Valida a imagem e o proxy sem precisar do K8S.

```bash
# build da imagem
docker build -t tinyproxy ./docker

# gera senha e cria o conf local
PASSWORD=$(openssl rand -hex 16)

cat > /tmp/tinyproxy-local.conf << EOF
Port 8888
Listen 0.0.0.0
Timeout 600
Allow 0.0.0.0/0
LogLevel Info
MaxClients 100
ConnectPort 443
ConnectPort 80
BasicAuth proxy ${PASSWORD}
EOF

# sobe o container
docker run -d \
  --name tinyproxy \
  -p 8888:8888 \
  -v /tmp/tinyproxy-local.conf:/etc/tinyproxy/tinyproxy.conf \
  tinyproxy

# testa — esperado: 200 do proxy + 401 do ghcr (correto, sem auth do registry)
HTTPS_PROXY=http://proxy:${PASSWORD}@localhost:8888 \
  curl -v https://ghcr.io/v2/ 2>&1 | grep -E "Connection established|HTTP/2|SSL certificate"

# limpa
docker rm -f tinyproxy
```

Saída esperada:
```
< HTTP/1.1 200 Connection established   ← proxy aceitou
*  SSL certificate verify ok            ← TLS direto ao destino, sem interceptação
< HTTP/2 401                            ← ghcr pediu auth do registry (esperado)
```

> O `401` do ghcr é correto — significa que o proxy deixou passar.
> Se o proxy rejeitasse seria `407` antes do TLS começar.

## Deploy no K8S

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

Opcionalmente, defina a região antes:

```bash
export AWS_REGION=sa-east-1
./scripts/deploy.sh
```

O script gera uma senha aleatória, cria o Secret no cluster e imprime os comandos prontos para uso ao final.

## Uso

**Terminal 1 — manter o tunnel aberto:**
```bash
kubectl port-forward svc/tinyproxy 8888:8888
```

**Terminal 2 — usar o proxy por comando (recomendado):**
```bash
HTTPS_PROXY=http://proxy:SENHA@localhost:8888 \
HTTP_PROXY=http://proxy:SENHA@localhost:8888 \
  terraform init
```

**Ou exportar para a sessão inteira:**
```bash
export HTTP_PROXY=http://proxy:SENHA@localhost:8888
export HTTPS_PROXY=http://proxy:SENHA@localhost:8888
export NO_PROXY=localhost,127.0.0.1,169.254.169.254,.amazonaws.com,.internal

terraform init
helm repo update
```

> Prefira o modo por comando para evitar que ferramentas como `aws cli` roteiem pelo proxy.

## Release

O build e push da imagem só acontecem ao criar uma tag — nenhum PR executa o pipeline.

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Como funciona

```
sua máquina (localhost:8888)
    └── kubectl port-forward (TLS → K8S API)
            └── pod tinyproxy
                    └── ghcr.io / registry.terraform.io / etc.
```
