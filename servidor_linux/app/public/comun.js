// Funciones compartidas por las páginas.
const pesos = (v) => '$' + Number(v || 0).toLocaleString('es-CO');

async function api(ruta, opciones = {}) {
  const r = await fetch(ruta, {
    ...opciones,
    headers: { 'Content-Type': 'application/json', ...(opciones.headers || {}) },
    body: opciones.body ? JSON.stringify(opciones.body) : undefined,
  });
  const datos = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(datos.error || `Error ${r.status}`);
  return datos;
}

// En Codespaces cada puerto tiene su propio dominio: nombre-8080.app.github.dev.
// Localmente se usa el mismo host con otro puerto.
function urlPuerto(puerto) {
  const h = location.hostname;
  const m = h.match(/^(.*)-(\d+)\.(app\.github\.dev|preview\.app\.github\.dev)$/);
  if (m) return `${location.protocol}//${m[1]}-${puerto}.${m[3]}/`;
  return `${location.protocol}//${h}:${puerto}/`;
}

function mostrar(el, ok, html) {
  el.className = 'resultado ' + (ok ? 'ok' : 'mal');
  el.innerHTML = html;
}

function marcarMenu() {
  document.querySelectorAll('header nav a').forEach((a) => {
    if (location.pathname.endsWith(a.getAttribute('href'))) a.classList.add('activo');
  });
}
document.addEventListener('DOMContentLoaded', marcarMenu);
