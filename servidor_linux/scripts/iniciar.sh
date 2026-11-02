#!/usr/bin/env bash
# Levanta todos los servicios. Se ejecuta solo al abrir el Codespace,
# o a mano con:  bash servidor_linux/scripts/iniciar.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Esperando a que Docker esté listo..."
for i in $(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sleep 2
done

mkdir -p reportes documentos
chmod 777 reportes documentos 2>/dev/null || true

docker compose up -d --build

# En Codespaces: deja públicos los puertos que se comparten por WhatsApp.
# Grafana tiene usuario y clave; Prometheus y Adminer quedan privados (solo VPN / dueño).
if [ -n "${CODESPACE_NAME:-}" ] && command -v gh >/dev/null 2>&1; then
  gh codespace ports visibility 8080:public 8090:public 8081:public 3000:public -c "$CODESPACE_NAME" >/dev/null 2>&1 \
    || echo "Aviso: no pude cambiar la visibilidad de los puertos. Hágalo en la pestaña PORTS (clic derecho > Port Visibility > Public)."
  DOMINIO="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
  echo ""
  echo "================ ENLACES PARA COMPARTIR ================"
  echo " App de peajes : https://${CODESPACE_NAME}-8080.${DOMINIO}"
  echo " Mensajería    : https://${CODESPACE_NAME}-8090.${DOMINIO}/peajes-alertas"
  echo " Documentos    : https://${CODESPACE_NAME}-8081.${DOMINIO}"
  echo " Monitor       : https://${CODESPACE_NAME}-3000.${DOMINIO}"
  echo "========================================================="
else
  echo ""
  echo "App: http://localhost:8080  ntfy: http://localhost:8090  Archivos: http://localhost:8081"
  echo "Grafana: http://localhost:3000  Prometheus: http://localhost:9090  Adminer: http://localhost:8082"
fi
