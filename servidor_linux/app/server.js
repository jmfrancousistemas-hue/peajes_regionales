// Sistema de Peajes Regionales
// Taquillas 1 a 3 (cobro manual en efectivo), carril TAG (taquilla 4) y recargas de la tarjeta TAG.
// Expone métricas para Prometheus en /metrics y envía alertas por ntfy.

const express = require('express');
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const client = require('prom-client');

const PORT = Number(process.env.PORT || 3000);
const NTFY_URL = process.env.NTFY_URL || 'http://ntfy';
const NTFY_TOPIC = process.env.NTFY_TOPIC || 'peajes-alertas';
const REPORTES_DIR = process.env.REPORTES_DIR || path.join(__dirname, 'reportes');
const ADMIN_USER = process.env.ADMIN_USER || 'admin';
const ADMIN_PASS = process.env.ADMIN_PASS || 'admin123';
const SALDO_MINIMO = Number(process.env.SALDO_MINIMO || 30000);

const pool = new Pool({
  host: process.env.PGHOST || 'db',
  port: Number(process.env.PGPORT || 5432),
  user: process.env.PGUSER || 'peajes',
  password: process.env.PGPASSWORD || 'peajes',
  database: process.env.PGDATABASE || 'peajes',
  max: 10,
});

// ---------------------------------------------------------------- Métricas
const registro = new client.Registry();
client.collectDefaultMetrics({ register: registro, prefix: 'peajes_app_' });

const mTransacciones = new client.Counter({
  name: 'peaje_transacciones_total',
  help: 'Vehículos cobrados por taquilla, categoría y medio de pago',
  labelNames: ['taquilla', 'categoria', 'medio'],
  registers: [registro],
});
const mRecaudo = new client.Counter({
  name: 'peaje_recaudo_pesos_total',
  help: 'Dinero recaudado en pesos por taquilla',
  labelNames: ['taquilla', 'medio'],
  registers: [registro],
});
const mRechazos = new client.Counter({
  name: 'peaje_tag_rechazos_total',
  help: 'Pasos por el carril TAG rechazados',
  labelNames: ['motivo'],
  registers: [registro],
});
const mRecargas = new client.Counter({
  name: 'peaje_recargas_pesos_total',
  help: 'Valor total recargado en tarjetas TAG',
  labelNames: ['medio_pago'],
  registers: [registro],
});
const mSimulacion = new client.Gauge({
  name: 'peaje_simulacion_activa',
  help: '1 si la simulación de tráfico está corriendo',
  registers: [registro],
});
const mDuracion = new client.Histogram({
  name: 'peaje_http_duracion_segundos',
  help: 'Tiempo de respuesta de la API',
  labelNames: ['metodo', 'ruta', 'codigo'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2],
  registers: [registro],
});

// ---------------------------------------------------------------- Utilidades
const pesos = (v) => '$' + Number(v).toLocaleString('es-CO');
const limpiarPlaca = (p) => String(p || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 10);

let categoriasCache = null;
async function categorias() {
  if (!categoriasCache) {
    const r = await pool.query('SELECT * FROM categorias ORDER BY id');
    categoriasCache = r.rows;
  }
  return categoriasCache;
}
async function categoriaPorId(id) {
  return (await categorias()).find((c) => c.id === Number(id));
}

// Avisos por ntfy. Se limitan para no inundar el celular durante la simulación.
const ultimoAviso = new Map();
async function notificar({ clave, titulo, mensaje, tags = [], prioridad = 3 }) {
  if (clave) {
    const antes = ultimoAviso.get(clave) || 0;
    if (Date.now() - antes < 10 * 60 * 1000) return;
    ultimoAviso.set(clave, Date.now());
  }
  try {
    await fetch(NTFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ topic: NTFY_TOPIC, title: titulo, message: mensaje, tags, priority: prioridad }),
      signal: AbortSignal.timeout(3000),
    });
  } catch (e) {
    console.warn('No se pudo enviar la notificación a ntfy:', e.message);
  }
}

async function nuevoConsecutivo(db, taquillaId) {
  const r = await db.query("SELECT nextval('transacciones_id_seq') AS id");
  const id = Number(r.rows[0].id);
  const hoy = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Bogota' }).replace(/-/g, '');
  return { id, consecutivo: `T${taquillaId}-${hoy}-${String(id).padStart(6, '0')}` };
}

function registrarMetricas(taquillaId, categoria, medio, valor) {
  mTransacciones.inc({ taquilla: String(taquillaId), categoria: categoria.codigo, medio });
  mRecaudo.inc({ taquilla: String(taquillaId), medio }, valor);
}

// ---------------------------------------------------------------- Lógica de negocio
async function cobroManual(taquillaId, placaEntrada, categoriaId, simulada = false) {
  taquillaId = Number(taquillaId);
  if (![1, 2, 3].includes(taquillaId)) throw new ErrorNegocio('Las taquillas manuales son la 1, 2 y 3');
  const placa = limpiarPlaca(placaEntrada);
  if (placa.length < 5) throw new ErrorNegocio('Placa inválida');
  const cat = await categoriaPorId(categoriaId);
  if (!cat) throw new ErrorNegocio('Categoría inválida');

  const { id, consecutivo } = await nuevoConsecutivo(pool, taquillaId);
  const r = await pool.query(
    `INSERT INTO transacciones (id, consecutivo, taquilla_id, placa, categoria_id, valor, medio, simulada)
     VALUES ($1,$2,$3,$4,$5,$6,'EFECTIVO',$7) RETURNING *`,
    [id, consecutivo, taquillaId, placa, cat.id, cat.tarifa, simulada]
  );
  registrarMetricas(taquillaId, cat, 'EFECTIVO', cat.tarifa);
  return { ...r.rows[0], categoria: cat };
}

async function pasoTag(referencia, simulada = false) {
  const ref = String(referencia || '').trim().toUpperCase();
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    const t = await db.query(
      'SELECT * FROM tarjetas_tag WHERE numero_tag = $1 OR placa = $2 FOR UPDATE',
      [ref, limpiarPlaca(ref)]
    );
    const tarjeta = t.rows[0];
    let motivo = null;
    if (!tarjeta) motivo = 'TAG no registrado';
    else if (!tarjeta.activa) motivo = 'TAG inactivo';

    const cat = tarjeta ? await categoriaPorId(tarjeta.categoria_id) : null;
    if (!motivo && tarjeta.saldo < cat.tarifa) motivo = 'Saldo insuficiente';

    if (motivo) {
      await db.query('INSERT INTO rechazos_tag (referencia, motivo) VALUES ($1,$2)', [ref.slice(0, 20), motivo]);
      await db.query('COMMIT');
      mRechazos.inc({ motivo });
      if (tarjeta) {
        notificar({
          clave: 'rechazo-' + tarjeta.id,
          titulo: `Carril TAG: paso rechazado (${tarjeta.placa})`,
          mensaje: `${motivo}. Saldo ${pesos(tarjeta.saldo)}, tarifa ${pesos(cat.tarifa)}. Desviar a taquilla manual.`,
          tags: ['no_entry', 'oncoming_automobile'],
          prioridad: 4,
        });
      }
      return { aprobado: false, motivo, tarjeta: tarjeta || null };
    }

    const nuevoSaldo = tarjeta.saldo - cat.tarifa;
    await db.query('UPDATE tarjetas_tag SET saldo = $1 WHERE id = $2', [nuevoSaldo, tarjeta.id]);
    const { id, consecutivo } = await nuevoConsecutivo(db, 4);
    const r = await db.query(
      `INSERT INTO transacciones (id, consecutivo, taquilla_id, placa, categoria_id, valor, medio, tarjeta_id, simulada)
       VALUES ($1,$2,4,$3,$4,$5,'TAG',$6,$7) RETURNING *`,
      [id, consecutivo, tarjeta.placa, cat.id, cat.tarifa, tarjeta.id, simulada]
    );
    await db.query('COMMIT');
    registrarMetricas(4, cat, 'TAG', cat.tarifa);

    if (nuevoSaldo < SALDO_MINIMO) {
      notificar({
        clave: 'saldo-' + tarjeta.id,
        titulo: `Saldo bajo en TAG ${tarjeta.numero_tag}`,
        mensaje: `${tarjeta.propietario} (${tarjeta.placa}) quedó con ${pesos(nuevoSaldo)}. Recargue antes del próximo paso.`,
        tags: ['warning', 'credit_card'],
      });
    }
    return { aprobado: true, transaccion: { ...r.rows[0], categoria: cat }, saldo: nuevoSaldo, tarjeta: { ...tarjeta, saldo: nuevoSaldo } };
  } catch (e) {
    await db.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    db.release();
  }
}

class ErrorNegocio extends Error {}

// ---------------------------------------------------------------- Simulación de tráfico
// Llegadas Poisson con la mezcla del simulador de MATLAB (escenario Riofrío):
// 590 veh/h, 65 % Cat. I, 8 % Cat. II, 27 % Cat. III-V, 35 % con TAG.
const sim = { activa: false, vehiculosHora: 590, aceleracion: 10, temporizador: null, generados: 0 };

function poisson(lambda) {
  let k = 0, p = 1;
  const L = Math.exp(-lambda);
  do { k++; p *= Math.random(); } while (p > L);
  return k - 1;
}
function categoriaAleatoria() {
  const u = Math.random();
  return u < 0.65 ? 1 : u < 0.73 ? 2 : 3;
}
function placaAleatoria() {
  const L = 'ABCDEFGHJKLMNPRSTUVWXYZ';
  const l = () => L[Math.floor(Math.random() * L.length)];
  return l() + l() + l() + String(Math.floor(Math.random() * 1000)).padStart(3, '0');
}
async function pasoSimulacion() {
  const llegadas = poisson((sim.vehiculosHora / 3600) * sim.aceleracion);
  for (let i = 0; i < llegadas; i++) {
    try {
      if (Math.random() < 0.35) {
        // Solo la flota simulada (SIM-xxx), para no gastar el saldo de los TAG de la demo.
        const t = await pool.query("SELECT numero_tag FROM tarjetas_tag WHERE numero_tag LIKE 'SIM-%' ORDER BY random() LIMIT 1");
        if (t.rows[0]) await pasoTag(t.rows[0].numero_tag, true);
      } else {
        await cobroManual(1 + Math.floor(Math.random() * 3), placaAleatoria(), categoriaAleatoria(), true);
      }
      sim.generados++;
    } catch (e) {
      console.warn('Simulación:', e.message);
    }
  }
}
function iniciarSimulacion(vehiculosHora, aceleracion) {
  detenerSimulacion();
  sim.vehiculosHora = Math.min(Math.max(Number(vehiculosHora) || 590, 10), 5000);
  sim.aceleracion = Math.min(Math.max(Number(aceleracion) || 10, 1), 60);
  sim.generados = 0;
  sim.activa = true;
  sim.temporizador = setInterval(pasoSimulacion, 1000);
  mSimulacion.set(1);
}
function detenerSimulacion() {
  if (sim.temporizador) clearInterval(sim.temporizador);
  sim.temporizador = null;
  sim.activa = false;
  mSimulacion.set(0);
}

// ---------------------------------------------------------------- Servidor web
const app = express();
app.use(express.json());

app.use((req, res, next) => {
  const fin = mDuracion.startTimer();
  res.on('finish', () => {
    const ruta = req.route ? req.baseUrl + req.route.path : 'otra';
    fin({ metodo: req.method, ruta, codigo: res.statusCode });
  });
  next();
});

function soloAdmin(req, res, next) {
  const [tipo, cred] = (req.headers.authorization || '').split(' ');
  if (tipo === 'Basic' && cred) {
    const [u, p] = Buffer.from(cred, 'base64').toString().split(':');
    if (u === ADMIN_USER && p === ADMIN_PASS) return next();
  }
  res.set('WWW-Authenticate', 'Basic realm="Administracion Peajes"');
  res.status(401).send('Acceso restringido a administradores');
}

const envolver = (fn) => (req, res) =>
  fn(req, res).catch((e) => {
    if (e instanceof ErrorNegocio) return res.status(400).json({ error: e.message });
    console.error(e);
    res.status(500).json({ error: 'Error interno: ' + e.message });
  });

app.get('/health', envolver(async (req, res) => {
  await pool.query('SELECT 1');
  res.json({ estado: 'ok', hora: new Date().toISOString() });
}));

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', registro.contentType);
  res.end(await registro.metrics());
});

app.get('/api/categorias', envolver(async (req, res) => res.json(await categorias())));

app.post('/api/taquillas/:id/cobro', envolver(async (req, res) => {
  const t = await cobroManual(req.params.id, req.body.placa, req.body.categoria_id);
  res.status(201).json(t);
}));

app.post('/api/tag/paso', envolver(async (req, res) => {
  res.json(await pasoTag(req.body.referencia));
}));

app.get('/api/tag/:ref', envolver(async (req, res) => {
  const ref = req.params.ref.toUpperCase();
  const r = await pool.query(
    `SELECT t.*, c.codigo AS categoria_codigo, c.tarifa FROM tarjetas_tag t
     JOIN categorias c ON c.id = t.categoria_id WHERE numero_tag = $1 OR placa = $2`,
    [ref, limpiarPlaca(ref)]
  );
  if (!r.rows[0]) return res.status(404).json({ error: 'TAG o placa no registrada' });
  const mov = await pool.query(
    `(SELECT 'PASO' AS tipo, -valor AS valor, fecha FROM transacciones WHERE tarjeta_id = $1)
     UNION ALL (SELECT 'RECARGA', valor, fecha FROM recargas WHERE tarjeta_id = $1)
     ORDER BY fecha DESC LIMIT 10`,
    [r.rows[0].id]
  );
  res.json({ ...r.rows[0], movimientos: mov.rows });
}));

app.post('/api/tag', envolver(async (req, res) => {
  const placa = limpiarPlaca(req.body.placa);
  const propietario = String(req.body.propietario || '').trim();
  const cat = await categoriaPorId(req.body.categoria_id);
  if (placa.length < 5 || !propietario || !cat) throw new ErrorNegocio('Placa, propietario y categoría son obligatorios');
  const n = await pool.query(
    `SELECT 'TAG-' || lpad((coalesce(max(substring(numero_tag from 5)::int), 0) + 1)::text, 4, '0') AS numero
     FROM tarjetas_tag WHERE numero_tag ~ '^TAG-[0-9]+$'`
  );
  try {
    const r = await pool.query(
      `INSERT INTO tarjetas_tag (numero_tag, placa, categoria_id, propietario, telefono, saldo)
       VALUES ($1,$2,$3,$4,$5,0) RETURNING *`,
      [n.rows[0].numero, placa, cat.id, propietario.slice(0, 100), String(req.body.telefono || '').slice(0, 20)]
    );
    res.status(201).json(r.rows[0]);
  } catch (e) {
    if (e.code === '23505') throw new ErrorNegocio('Esa placa ya tiene un TAG registrado');
    throw e;
  }
}));

app.post('/api/tag/:ref/recarga', envolver(async (req, res) => {
  const valor = Math.round(Number(req.body.valor));
  const medio = ['EFECTIVO', 'TARJETA', 'PSE', 'NEQUI'].includes(req.body.medio_pago) ? req.body.medio_pago : 'EFECTIVO';
  if (!(valor >= 10000 && valor <= 2000000)) throw new ErrorNegocio('La recarga debe estar entre $10.000 y $2.000.000');
  const ref = req.params.ref.toUpperCase();
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    const t = await db.query(
      'UPDATE tarjetas_tag SET saldo = saldo + $1 WHERE numero_tag = $2 OR placa = $3 RETURNING *',
      [valor, ref, limpiarPlaca(ref)]
    );
    if (!t.rows[0]) { await db.query('ROLLBACK'); return res.status(404).json({ error: 'TAG o placa no registrada' }); }
    const tarjeta = t.rows[0];
    const r = await db.query(
      'INSERT INTO recargas (tarjeta_id, valor, medio_pago, saldo_resultante) VALUES ($1,$2,$3,$4) RETURNING *',
      [tarjeta.id, valor, medio, tarjeta.saldo]
    );
    await db.query('COMMIT');
    mRecargas.inc({ medio_pago: medio }, valor);
    ultimoAviso.delete('saldo-' + tarjeta.id);
    ultimoAviso.delete('rechazo-' + tarjeta.id);
    notificar({
      titulo: `Recarga TAG ${tarjeta.numero_tag}`,
      mensaje: `${pesos(valor)} por ${medio} a ${tarjeta.placa}. Nuevo saldo: ${pesos(tarjeta.saldo)}.`,
      tags: ['white_check_mark', 'moneybag'],
    });
    res.status(201).json({ recarga: r.rows[0], tarjeta });
  } catch (e) {
    await db.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    db.release();
  }
}));

app.get('/api/tickets/:consecutivo', envolver(async (req, res) => {
  const r = await pool.query(
    `SELECT t.*, c.codigo AS categoria_codigo, c.descripcion AS categoria_descripcion, q.nombre AS taquilla
     FROM transacciones t JOIN categorias c ON c.id = t.categoria_id JOIN taquillas q ON q.id = t.taquilla_id
     WHERE consecutivo = $1`,
    [req.params.consecutivo]
  );
  if (!r.rows[0]) return res.status(404).json({ error: 'Ticket no encontrado' });
  res.json(r.rows[0]);
}));

// ------------------------------- Administración (usuario y clave)
app.get('/admin.html', soloAdmin);
app.use('/api/admin', soloAdmin);

app.get('/api/admin/resumen', envolver(async (req, res) => {
  const porTaquilla = await pool.query(
    `SELECT q.id, q.nombre, q.tipo, count(t.id)::int AS vehiculos, coalesce(sum(t.valor),0)::int AS recaudo
     FROM taquillas q LEFT JOIN transacciones t ON t.taquilla_id = q.id AND t.fecha >= date_trunc('day', now())
     GROUP BY q.id ORDER BY q.id`
  );
  const porCategoria = await pool.query(
    `SELECT c.codigo, count(t.id)::int AS vehiculos FROM categorias c
     LEFT JOIN transacciones t ON t.categoria_id = c.id AND t.fecha >= date_trunc('day', now())
     GROUP BY c.id ORDER BY c.id`
  );
  const otros = await pool.query(
    `SELECT (SELECT count(*) FROM rechazos_tag WHERE fecha >= date_trunc('day', now()))::int AS rechazos,
            (SELECT coalesce(sum(valor),0) FROM recargas WHERE fecha >= date_trunc('day', now()))::int AS recargas,
            (SELECT count(*) FROM tarjetas_tag WHERE saldo < $1)::int AS tags_saldo_bajo`,
    [SALDO_MINIMO]
  );
  res.json({
    taquillas: porTaquilla.rows,
    categorias: porCategoria.rows,
    ...otros.rows[0],
    simulacion: { activa: sim.activa, vehiculosHora: sim.vehiculosHora, aceleracion: sim.aceleracion, generados: sim.generados },
  });
}));

app.get('/api/admin/transacciones', envolver(async (req, res) => {
  const limite = Math.min(Number(req.query.limite) || 25, 200);
  const r = await pool.query(
    `SELECT t.consecutivo, t.taquilla_id, t.placa, c.codigo AS categoria, t.valor, t.medio, t.simulada, t.fecha
     FROM transacciones t JOIN categorias c ON c.id = t.categoria_id ORDER BY t.id DESC LIMIT $1`,
    [limite]
  );
  res.json(r.rows);
}));

app.get('/api/admin/tags', envolver(async (req, res) => {
  const r = await pool.query(
    `SELECT t.numero_tag, t.placa, c.codigo AS categoria, t.propietario, t.telefono, t.saldo, t.activa
     FROM tarjetas_tag t JOIN categorias c ON c.id = t.categoria_id
     WHERE t.numero_tag NOT LIKE 'SIM-%' ORDER BY t.id`
  );
  res.json(r.rows);
}));

// Cierre de caja: genera un CSV en la carpeta compartida con File Browser.
app.post('/api/admin/cierre', envolver(async (req, res) => {
  const r = await pool.query(
    `SELECT t.consecutivo, q.nombre AS taquilla, t.placa, c.codigo AS categoria, t.valor, t.medio,
            to_char(t.fecha AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS') AS fecha, t.simulada
     FROM transacciones t JOIN taquillas q ON q.id = t.taquilla_id JOIN categorias c ON c.id = t.categoria_id
     WHERE t.fecha >= date_trunc('day', now()) ORDER BY t.id`
  );
  const resumen = await pool.query(
    `SELECT q.nombre, count(t.id)::int AS vehiculos, coalesce(sum(t.valor),0)::int AS recaudo
     FROM taquillas q LEFT JOIN transacciones t ON t.taquilla_id = q.id AND t.fecha >= date_trunc('day', now())
     GROUP BY q.id ORDER BY q.id`
  );
  fs.mkdirSync(REPORTES_DIR, { recursive: true });
  const sello = new Date().toLocaleString('sv-SE', { timeZone: 'America/Bogota' }).replace(/[: ]/g, '-');
  const archivo = `cierre_caja_${sello}.csv`;
  const filas = [
    'consecutivo;taquilla;placa;categoria;valor;medio;fecha;simulada',
    ...r.rows.map((x) => [x.consecutivo, x.taquilla, x.placa, x.categoria, x.valor, x.medio, x.fecha, x.simulada ? 'si' : 'no'].join(';')),
    '',
    'RESUMEN;vehiculos;recaudo',
    ...resumen.rows.map((x) => `${x.nombre};${x.vehiculos};${x.recaudo}`),
    `TOTAL;${resumen.rows.reduce((a, x) => a + x.vehiculos, 0)};${resumen.rows.reduce((a, x) => a + x.recaudo, 0)}`,
  ];
  // BOM UTF-8 y separador ';' para que Excel en Windows lo abra bien.
  fs.writeFileSync(path.join(REPORTES_DIR, archivo), '﻿' + filas.join('\r\n'));
  const total = resumen.rows.reduce((a, x) => a + x.recaudo, 0);
  notificar({ titulo: 'Cierre de caja generado', mensaje: `${archivo}: ${r.rows.length} vehículos, ${pesos(total)}. Disponible en File Browser.`, tags: ['page_facing_up'] });
  res.status(201).json({ archivo, vehiculos: r.rows.length, recaudo: total });
}));

app.post('/api/admin/simulacion', envolver(async (req, res) => {
  if (req.body.accion === 'iniciar') iniciarSimulacion(req.body.vehiculos_hora, req.body.aceleracion);
  else detenerSimulacion();
  res.json({ activa: sim.activa, vehiculosHora: sim.vehiculosHora, aceleracion: sim.aceleracion });
}));

app.post('/api/admin/notificacion-prueba', envolver(async (req, res) => {
  await notificar({ titulo: 'Prueba del sistema de peajes', mensaje: 'Si ve este mensaje, la mensajería funciona.', tags: ['bell'] });
  res.json({ enviada: true, topico: NTFY_TOPIC });
}));

app.use(express.static(path.join(__dirname, 'public')));

// Espera a la base de datos antes de aceptar tráfico.
async function arrancar() {
  for (let i = 1; i <= 30; i++) {
    try { await pool.query('SELECT 1 FROM categorias LIMIT 1'); break; }
    catch (e) {
      console.log(`Esperando PostgreSQL (${i}/30): ${e.message}`);
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
  app.listen(PORT, () => console.log(`Peajes Regionales escuchando en el puerto ${PORT}`));
}
process.on('SIGTERM', () => { detenerSimulacion(); pool.end().then(() => process.exit(0)); });
arrancar();
