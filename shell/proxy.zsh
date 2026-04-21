# ~/.zshrc

# ── tinyproxy ─────────────────────────────────────────────
proxy-start() {
  # guarda dupla abertura
  if [[ -n "$HTTPS_PROXY" ]]; then
    echo "⚠️  Proxy já está ativo → ${HTTPS_PROXY}"
    echo "   Rode proxy-stop primeiro"
    return 1
  fi

  if [[ -f /tmp/tinyproxy-pf.pid ]] && kill -0 "$(cat /tmp/tinyproxy-pf.pid)" 2>/dev/null; then
    echo "⚠️  Port-forward já está rodando (PID $(cat /tmp/tinyproxy-pf.pid)) mas HTTPS_PROXY não está setado"
    echo "   Rode proxy-stop para limpar"
    return 1
  fi

  # auto-delete: agenda remoção do pod após TTL (padrão: 2h)
  local ttl=${TINYPROXY_TTL:-5}
  echo "→ Agendando auto-delete do pod em ${ttl} minutos..."
  (
    sleep $(( ttl * 60 ))
    kubectl delete deployment tinyproxy --ignore-not-found &>/dev/null
    echo "\n⏰ TTL expirado — pod tinyproxy removido do cluster"
  ) &
  echo $! > /tmp/tinyproxy-ttl.pid

  echo "→ Iniciando port-forward..."
  kubectl port-forward svc/tinyproxy 8888:8888 &>/dev/null &
  echo $! > /tmp/tinyproxy-pf.pid
  sleep 1

  # valida que o port-forward subiu
  if ! kill -0 "$(cat /tmp/tinyproxy-pf.pid)" 2>/dev/null; then
    echo "❌ Port-forward falhou — verifique se o pod está rodando"
    echo "   kubectl get pods -l app=tinyproxy"
    rm -f /tmp/tinyproxy-pf.pid /tmp/tinyproxy-ttl.pid
    return 1
  fi

  local password
  password=$(kubectl get secret tinyproxy-auth -o jsonpath='{.data.password}' | base64 -d)

  if [[ -z "$password" ]]; then
    echo "❌ Não foi possível obter a senha do Secret"
    proxy-stop
    return 1
  fi

  export HTTP_PROXY="http://proxy:${password}@localhost:8888"
  export HTTPS_PROXY="http://proxy:${password}@localhost:8888"
  export NO_PROXY="localhost,127.0.0.1,169.254.169.254,.amazonaws.com,.internal"

  echo "✅ Proxy ativo — expira em ${ttl} minutos"
  echo "   Para mudar o TTL: TINYPROXY_TTL=60 proxy-start"
}

proxy-stop() {
  # mata port-forward
  if [[ -f /tmp/tinyproxy-pf.pid ]]; then
    kill "$(cat /tmp/tinyproxy-pf.pid)" 2>/dev/null
    rm /tmp/tinyproxy-pf.pid
  fi

  # cancela o auto-delete agendado
  if [[ -f /tmp/tinyproxy-ttl.pid ]]; then
    kill "$(cat /tmp/tinyproxy-ttl.pid)" 2>/dev/null
    rm /tmp/tinyproxy-ttl.pid
    echo "→ Auto-delete cancelado"
  fi

  unset HTTP_PROXY HTTPS_PROXY NO_PROXY
  echo "🛑 Proxy desativado"
}

proxy-status() {
  if [[ -n "$HTTPS_PROXY" ]]; then
    echo "✅ Ativo → ${HTTPS_PROXY}"
    echo "   PID port-forward : $(cat /tmp/tinyproxy-pf.pid 2>/dev/null || echo 'não encontrado')"

    if [[ -f /tmp/tinyproxy-ttl.pid ]] && kill -0 "$(cat /tmp/tinyproxy-ttl.pid)" 2>/dev/null; then
      echo "   Auto-delete      : agendado (PID $(cat /tmp/tinyproxy-ttl.pid))"
    else
      echo "   Auto-delete      : não agendado"
    fi
  else
    echo "🛑 Inativo"
  fi
}