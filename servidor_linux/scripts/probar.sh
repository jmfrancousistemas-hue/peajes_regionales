#!/usr/bin/env bash
# Pruebas de humo de todos los servicios. Las usa GitHub Actions y sirven para la demo:
#   bash servidor_linux/scripts/probar.sh
set -uo pipefail
APP=${APP:-http://localhost:8080}
ADMIN=${ADMIN:-admin:admin123}
fallas=0

ok()   { echo "  [OK]    $1"; }
mal()  { echo "  [FALLA] $1"; fallas=$((fallas+1)); }
esperar() { # url, nombre
  for i in $(seq 1 60); do
    curl -fsS -o /dev/null "$1" 2>/dev/null && { ok "$2 responde"; return 0; }
    sleep 3
  done
  mal "$2 no responde en $1"
}

echo "1. Servicios arriba"
esperar "$APP/health"                         "App de peajes (Nginx + Node + PostgreSQL)"
esperar "http://localhost:8090/v1/health"     "Mensajería ntfy"
esperar "http://localhost:8081/"              "File Browser"
esperar "http://localhost:3000/api/health"    "Grafana"
esperar "http://localhost:9090/-/ready"       "Prometheus"
esperar "http://localhost:8082/"              "Adminer"

echo "2. Taquilla manual"
r=$(curl -fsS -X POST "$APP/api/taquillas/2/cobro" -H 'Content-Type: application/json' -d '{"placa":"PRB123","categoria_id":1}')
echo "$r" | grep -q '"consecutivo":"T2-' && ok "Ticket emitido en taquilla 2" || mal "Cobro manual: $r"

echo "3. Carril TAG"
r=$(curl -fsS -X POST "$APP/api/tag/paso" -H 'Content-Type: application/json' -d '{"referencia":"TAG-0001"}')
echo "$r" | grep -q '"aprobado":true' && ok "TAG-0001 aprobado" || mal "Paso TAG: $r"
r=$(curl -fsS -X POST "$APP/api/tag/paso" -H 'Content-Type: application/json' -d '{"referencia":"TAG-9999"}')
echo "$r" | grep -q '"aprobado":false' && ok "TAG inexistente rechazado" || mal "Rechazo TAG: $r"

echo "4. Recarga"
r=$(curl -fsS -X POST "$APP/api/tag/TAG-0004/recarga" -H 'Content-Type: application/json' -d '{"valor":50000,"medio_pago":"NEQUI"}')
echo "$r" | grep -q '"saldo_resultante"' && ok "Recarga de \$50.000 a TAG-0004" || mal "Recarga: $r"

echo "5. Administración"
code=$(curl -s -o /dev/null -w '%{http_code}' "$APP/api/admin/resumen")
[ "$code" = "401" ] && ok "Admin protegido sin clave (401)" || mal "Admin sin clave devolvió $code"
curl -fsS -u "$ADMIN" "$APP/api/admin/resumen" | grep -q '"taquillas"' && ok "Resumen con clave" || mal "Resumen admin"
r=$(curl -fsS -u "$ADMIN" -X POST "$APP/api/admin/cierre")
echo "$r" | grep -q '"archivo"' && ok "Cierre de caja generado" || mal "Cierre: $r"

echo "6. Mensajería y monitoreo"
sleep 2
curl -fsS "http://localhost:8090/peajes-alertas/json?poll=1&since=10m" | grep -q 'Recarga' && ok "Aviso de recarga llegó a ntfy" || mal "No llegó el aviso a ntfy"
sleep 12
curl -fsS "http://localhost:9090/api/v1/query?query=peaje_transacciones_total" | grep -q 'taquilla' && ok "Prometheus recoge métricas de la app" || mal "Prometheus sin métricas de la app"
curl -fsS "http://localhost:9090/api/v1/query?query=node_load1" | grep -q 'node_load1' && ok "Prometheus recoge métricas del servidor" || mal "Sin métricas de node-exporter"

echo ""
if [ $fallas -eq 0 ]; then echo "Todas las pruebas pasaron."; else echo "$fallas prueba(s) fallaron."; fi
exit $fallas
