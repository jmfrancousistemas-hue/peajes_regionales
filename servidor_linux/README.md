# Servidor Linux con Docker: Sistema de Peajes Regionales

Proyecto Final de Sistemas Distribuidos (INTEP). Es un servidor Linux con Docker para la cooperativa de transporte, alojado en GitHub Codespaces. Corre 10 contenedores:

| # | Servicio | Contenedor | Puerto | Para qué sirve |
|---|---|---|---|---|
| 1 | App de peajes | `peajes-app` (Debian 12 + Node 20) | interno 3000 | 3 taquillas manuales, carril TAG, recargas, administración |
| 2 | Proxy web | `peajes-nginx` | **8080** | Puerta de entrada pública a la app |
| 3 | Base de datos | `peajes-db` (PostgreSQL 16) | interno | Tarifas, TAG, saldos, transacciones, recargas |
| 4 | **Mensajería** | `peajes-ntfy` | **8090** | Alertas al celular: saldo bajo, rechazos TAG, recargas, cierres |
| 5 | **Monitor** | `peajes-grafana` | **3000** | Tablero con el rendimiento del servidor, los contenedores y el peaje |
| 6 | Recolector de métricas | `peajes-prometheus` | 9090 | Guarda las métricas que muestra Grafana |
| 7 | Métricas del servidor | `peajes-node-exporter` | interno | CPU, RAM, disco y red del Linux |
| 8 | Métricas de contenedores | `peajes-cadvisor` | interno | CPU, RAM y red de cada contenedor |
| 9 | **Documentos** | `peajes-filebrowser` | **8081** | Reportes y documentos por web (Windows y Linux) |
| 10 | Admin de BD | `peajes-adminer` | 8082 | Administrar PostgreSQL (solo por VPN) |

Además, la VPN para administradores es **Tailscale**, que funciona sobre WireGuard (detalles en el paso 4).

```
 Celular / PC (enlace por WhatsApp)                    Administradores (VPN Tailscale/WireGuard)
            │ HTTPS                                                │
            ▼                                                      ▼
 ┌──────────────────────── GitHub Codespace (Ubuntu 24.04 + Docker) ──────────────────────┐
 │  :8080 nginx ──► app (taquillas 1-3, TAG, recargas) ──► PostgreSQL                     │
 │                      │ avisos                │ /metrics                                │
 │  :8090 ntfy ◄────────┘                       ▼                                          │
 │  :8081 File Browser ◄── cierres CSV    Prometheus ◄── node-exporter, cAdvisor           │
 │  :3000 Grafana ◄───────────────────────────┘                     :8082 Adminer (VPN)   │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
```

## 1. Crear el Codespace

1. En el repositorio: **Code → Codespaces → ⋯ → New with options**.
2. Branch `main`, región **US East**, Machine type **2-core (8 GB RAM)**. Para el día de la presentación cámbiela a **4-core (16 GB RAM)**: con el codespace detenido, ⋯ → *Change machine type*.
3. Al abrir, el codespace instala Docker y ejecuta solo `servidor_linux/scripts/iniciar.sh`. La primera vez tarda de 3 a 5 minutos descargando las imágenes.
4. Al final de la terminal aparecen los **enlaces para compartir**. También están en la pestaña **PORTS**.

Si los servicios no arrancaron solos:

```bash
bash servidor_linux/scripts/iniciar.sh
```

> **Ahorro de horas.** Con GitHub Education tiene 180 horas-núcleo al mes: unas 90 horas de la máquina de 2 núcleos o 45 de la de 4. Cuando no lo use, deténgalo: github.com/codespaces → ⋯ → *Stop codespace*.

## 2. Usuarios y claves

| Servicio | Usuario | Clave |
|---|---|---|
| Administración de la app (`/admin.html`) | `admin` | `admin123` |
| Grafana | `admin` | `admin123` |
| File Browser | `admin` | `admin` (cámbiela al entrar: Settings → Profile) |
| Adminer | servidor `db`, usuario `peajes`, base `peajes` | `peajes` |

Para cambiarlas, copie `.env.example` como `.env`, edite los valores y ejecute `docker compose up -d` dentro de `servidor_linux`.

TAG de prueba: `TAG-0001` (ABC123, $150.000), `TAG-0002` (BUS456), `TAG-0003` (TRK789) y `TAG-0004` (XYZ987, saldo bajo de $12.000, sirve para mostrar un rechazo).

## 3. Mensajería: recibir las alertas en el celular

1. Instale **ntfy** (Play Store o App Store) o abra el enlace del puerto 8090 en el navegador.
2. En la app toque **+**, active *Use another server* y pegue la URL del puerto 8090, por ejemplo `https://SU-CODESPACE-8090.app.github.dev`. El tema es `peajes-alertas`.
3. Comparta por WhatsApp el enlace `https://SU-CODESPACE-8090.app.github.dev/peajes-alertas`: quien lo abra ve las alertas en vivo y puede escribir mensajes al equipo.
4. Para probar: en **Administración → Enviar aviso de prueba**, o recargue un TAG.

## 4. VPN para administradores (Tailscale sobre WireGuard)

¿Por qué no WireGuard directo? WireGuard necesita recibir tráfico UDP desde internet y permisos de red del kernel. Codespaces solo publica puertos web (HTTP/HTTPS), así que un servidor WireGuard clásico no recibe conexiones ahí. **Tailscale usa el mismo protocolo WireGuard**, pero las conexiones salen desde el servidor, así que no hay que abrir puertos. Por eso sí funciona en Codespaces, y el profesor puede ver que la VPN es WireGuard.

1. Cree una cuenta gratis en https://tailscale.com (entre con GitHub).
2. En la terminal del codespace:
   ```bash
   sudo tailscale up --hostname=peajes-servidor
   ```
   Abra el enlace que aparece y autorice.
3. Instale Tailscale en el PC o celular del administrador y entre con la misma cuenta.
4. Desde ese equipo, ya dentro de la VPN, abra:
   - `http://peajes-servidor:8082`: Adminer (base de datos)
   - `http://peajes-servidor:9090`: Prometheus
   - `http://peajes-servidor:3000`: Grafana
5. Para mostrarlo en la exposición: `tailscale status` y `tailscale ping peajes-servidor`.

*Opcional:* guarde una clave de Tailscale como secreto del codespace (`TS_AUTH_KEY`, en github.com → Settings → Codespaces → Secrets) para que se conecte solo.

Prometheus y Adminer quedan con visibilidad **Private** en Codespaces, así que nadie de afuera los ve sin la VPN.

## 5. Guion para la presentación (unos 10 minutos)

1. **Infraestructura.** En la terminal ejecute `cat /etc/os-release` y `docker compose -f servidor_linux/docker-compose.yml ps`: se ven los 10 contenedores *Up*.
2. **Enlace por WhatsApp.** Envíe al grupo el enlace del puerto 8080. Los compañeros abren la app desde el celular.
3. **Taquilla manual.** En *Taquillas*, placa `KLM321`, Cat. I → *Cobrar*. Abra *Imprimir ticket*.
4. **Carril TAG.** Lea `TAG-0001`: semáforo verde y descuento. Luego lea `TAG-0004`: semáforo rojo por saldo insuficiente. **Al celular llega la alerta de ntfy.**
5. **Recarga.** Recargue $50.000 a `XYZ987` por NEQUI y vuelva a leerlo: ahora pasa. Llega otra alerta.
6. **Monitor.** En *Administración*, inicie la simulación (590 veh/h × 10, la misma mezcla del simulador de MATLAB). Abra Grafana: suben los vehículos por taquilla, la CPU de `peajes-app` y de `peajes-db` y la red.
7. **Documentos.** Pulse *Generar cierre de caja*, abra File Browser (8081) y descargue el CSV en Windows: abre directo en Excel.
8. **VPN.** Muestre `tailscale status` y abra Adminer por `http://peajes-servidor:8082` desde un equipo en la VPN.
9. **GitHub Actions.** En la pestaña *Actions* del repositorio está el pipeline que levanta el servidor en un Ubuntu de GitHub y prueba los servicios en cada `push`.

Para probar todo de una vez:

```bash
bash servidor_linux/scripts/probar.sh
```

## 6. Comandos útiles

```bash
cd servidor_linux
docker compose ps                  # estado de los servicios
docker compose logs -f app         # registros de la app
docker stats                       # consumo en vivo de cada contenedor
docker compose restart app         # reiniciar un servicio
docker compose down                # apagar (los datos se conservan)
docker compose down -v             # apagar y BORRAR la base de datos
```

## 7. Problemas frecuentes

- **El enlace pide iniciar sesión en GitHub.** El puerto está en *Private*. En la pestaña PORTS: clic derecho → *Port Visibility* → *Public*.
- **Grafana aparece sin datos.** Espere 20 a 30 segundos después de arrancar e inicie la simulación desde Administración.
- **El cierre de caja da error de permisos.** Ejecute `chmod 777 servidor_linux/reportes`.
- **"no space left on device".** Ejecute `docker system prune -f`.

## Estructura

```
.devcontainer/devcontainer.json    Codespace: Ubuntu 24.04 + Docker + Tailscale + puertos
.github/workflows/servidor-linux.yml  Pipeline de GitHub Actions
servidor_linux/
  docker-compose.yml               Los 10 servicios
  app/                             App web (Node + Express) y Dockerfile sobre Debian
    server.js                      Taquillas, TAG, recargas, simulación, métricas, alertas
    public/                        Páginas: portal, taquillas, TAG, administración, ticket
  db/init.sql                      Tablas, tarifas INVÍAS 2026 y TAG de prueba
  nginx/default.conf               Proxy inverso
  monitoreo/                       Prometheus y Grafana (tablero ya configurado)
  reportes/                        Cierres de caja (compartidos por File Browser)
  documentos/                      Carpeta compartida para documentos
  scripts/iniciar.sh, probar.sh    Arranque y pruebas
```
