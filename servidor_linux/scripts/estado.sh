#!/usr/bin/env bash
# Muestra el estado de los 10 servicios y levanta los que estén caídos.
#   bash servidor_linux/scripts/estado.sh
cd "$(dirname "$0")/.."

SERVICIOS=(db app nginx ntfy filebrowser prometheus grafana node-exporter cadvisor adminer)
TOTAL=${#SERVICIOS[@]}

contar() { docker compose ps --status running --services 2>/dev/null | wc -l; }

if [ "$(contar)" -lt "$TOTAL" ]; then
  echo "Hay servicios detenidos. Intentando levantarlos..."
  docker compose up -d >/dev/null 2>&1
  sleep 10
fi

echo ""
printf "%-16s %-22s %s\n" "SERVICIO" "CONTENEDOR" "ESTADO"
printf "%-16s %-22s %s\n" "--------" "----------" "------"
arriba=0
caidos=()
for s in "${SERVICIOS[@]}"; do
  id=$(docker compose ps -a -q "$s" 2>/dev/null)
  if [ -z "$id" ]; then
    estado="no creado"
  else
    estado=$(docker inspect -f '{{.State.Status}}{{if .State.Health}} ({{.State.Health.Status}}){{end}}' "$id")
  fi
  if [[ "$estado" == running* ]]; then
    arriba=$((arriba+1)); marca="OK   "
  else
    caidos+=("$s"); marca="FALLA"
  fi
  printf "%-16s %-22s %s %s\n" "$s" "peajes-$s" "$marca" "$estado"
done

echo ""
echo "Servicios arriba: $arriba de $TOTAL"

if [ ${#caidos[@]} -gt 0 ]; then
  for s in "${caidos[@]}"; do
    echo ""
    echo "===== Últimas líneas del registro de $s ====="
    docker compose logs --tail=15 "$s" 2>&1
  done
  echo ""
  echo "Copie este resultado y envíelo para revisarlo."
  exit 1
fi
