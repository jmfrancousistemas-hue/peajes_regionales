/*
 * motor.js — Núcleo del simulador híbrido de tráfico y peajes (gemelo de MATLAB)
 * Proyecto Final - Modelos de Simulación (UNINTEP) - Alternativa 1
 *
 * Es una traducción línea a línea de:
 *   fase1/GeneradorLCG.m, fase2/idm_aceleracion.m, motor_inicializar.m,
 *   motor_paso.m, motor_resultados.m, erlang_c.m
 * Mismo generador (Park-Miller), mismo orden de consumo de números
 * aleatorios y mismo integrador: con la misma semilla debe reproducir
 * las corridas de MATLAB.
 */
(function (global) {
  'use strict';

  // ---------------- Fase 1: LCG Park-Miller ----------------
  class GeneradorLCG {
    constructor(semilla = 12345) { this.a = 16807; this.m = 2147483647; this.reiniciar(semilla); }
    reiniciar(semilla) {
      semilla = Math.floor(Number(semilla)) % this.m;
      if (semilla <= 0) semilla = semilla < 0 ? semilla + this.m : 1;
      if (semilla === 0) semilla = 1;
      this.semilla = semilla; this.estado = semilla; this.contador = 0;
    }
    siguienteEntero() { this.estado = (this.a * this.estado) % this.m; this.contador++; return this.estado; }
    uniforme() { return this.siguienteEntero() / this.m; }
    exponencial(media) { return -media * Math.log(this.uniforme()); }
    discreta(prob) {
      const u = this.uniforme(); const tot = prob.reduce((s, x) => s + x, 0);
      let acc = 0;
      for (let k = 0; k < prob.length; k++) { acc += prob[k] / tot; if (u <= acc) return k; }
      return prob.length - 1;
    }
    bernoulli(p) { return this.uniforme() < p; }
    normal() { const u1 = this.uniforme(), u2 = this.uniforme(); return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2); }
    lognormal(media, cv) { const s2 = Math.log(1 + cv * cv); const mu = Math.log(media) - s2 / 2; return Math.exp(mu + Math.sqrt(s2) * this.normal()); }
  }

  // ---------------- Parámetros ----------------
  function parametrosPeaje() {
    return {
      semilla: 12345, lambda: 450, mezcla: [0.70, 0.10, 0.20], propTag: 0.35,
      servManual: 20, cvManual: 0.40, servTag: 4, cvTag: 0.25,
      carrilesManuales: 3, carrilesTag: 1, L: 600, xSalida: 750,
      factor_v0: 1, factor_T: 1, factor_a: 1, factor_b: 1, delta: 4, aFrenadoMax: 9,
      dt: 0.1, tFin: 3600, muestreo: 1, modoFisico: true,
      cat: [
        { nombre: 'Auto',   v0: 80 / 3.6, T: 1.5, a: 1.0, b: 1.5, s0: 2.0, largo: 4.5,  fServ: 1.0, tarifa: 10400 },
        { nombre: 'Bus',    v0: 70 / 3.6, T: 1.8, a: 0.7, b: 1.5, s0: 3.0, largo: 12.0, fServ: 1.3, tarifa: 11200 },
        { nombre: 'Camión', v0: 60 / 3.6, T: 2.0, a: 0.5, b: 1.2, s0: 3.0, largo: 16.0, fServ: 1.5, tarifa: 24100 },
      ],
    };
  }

  // ---------------- Rol A: IDM ----------------
  function idm(v, v0, T, a, b, s0, s, dv, delta) {
    if (!isFinite(s)) return a * (1 - Math.pow(v / v0, delta));
    s = Math.max(s, 0.01);
    const sE = s0 + Math.max(0, v * T + v * dv / (2 * Math.sqrt(a * b)));
    return a * (1 - Math.pow(v / v0, delta) - Math.pow(sE / s, 2));
  }

  // Recorrido de un vehículo solo desde (x, v) hasta detenerse en la taquilla
  function tiempoRecorrido(p, c, x, v) {
    const q = p.cat[c];
    const v0 = q.v0 * p.factor_v0, T = q.T * p.factor_T, a = q.a * p.factor_a, b = q.b * p.factor_b;
    let k = 0;
    while (k < 1e6) {
      let acc = idm(v, v0, T, a, b, q.s0, p.L + q.s0 - x, v, p.delta);
      acc = Math.max(acc, -p.aFrenadoMax);
      const vN = Math.max(v + acc * p.dt, 0);
      x = x + 0.5 * (v + vN) * p.dt; v = vN; k++;
      if ((p.L - x) < 1.0 && v < 1.0) break;
    }
    return k * p.dt;
  }

  // ---------------- Rol B: motor ----------------
  class Motor {
    constructor(p) {
      this.p = p; this.rng = new GeneradorLCG(p.semilla);
      this.k = 0; this.t = 0;
      const nC = p.carrilesManuales + p.carrilesTag;
      this.nCarriles = nC;
      this.esTag = []; for (let i = 0; i < nC; i++) this.esTag.push(i >= p.carrilesManuales);
      this.V = [];                // vehículos (objetos)
      this.pendientes = [];
      this.cab = { ocupadaPor: new Array(nC).fill(null), tFin: new Array(nC).fill(Infinity),
                   tOcupada: new Array(nC).fill(0), atendidos: new Array(nC).fill(0) };
      this.colaAcum = new Array(nC).fill(0);
      this.ultimaCola = new Array(nC).fill(0);
      this.recaudo = 0; this.maxPendientes = 0;
      this.tProxLlegada = this.rng.exponencial(3600 / p.lambda);
      this.serie = { t: [], cola: [], ocupada: [], enSistema: [], velMedia: [] };
      this.kMuestra = Math.round(p.muestreo / p.dt);
      // Sin física (modo discreto puro) no hay tiempo de recorrido
      this.tLibre = p.cat.map((q, c) => p.modoFisico ? tiempoRecorrido(p, c, 0, q.v0 * p.factor_v0) : 0);
      this.tAvance = p.cat.map((q, c) => p.modoFisico ? tiempoRecorrido(p, c, p.L - p.cat[0].largo - q.s0, 0) : 0);
      this.activos = [];           // vehículos con estado 1..3
    }

    get terminado() { return this.k >= Math.round(this.p.tFin / this.p.dt); }

    paso() {
      const p = this.p;
      this.k++; const tN = this.k * p.dt;
      // 1. eventos discretos
      for (;;) {
        let tc = Infinity, kc = -1;
        for (let k = 0; k < this.nCarriles; k++) if (this.cab.tFin[k] < tc) { tc = this.cab.tFin[k]; kc = k; }
        if (Math.min(tc, this.tProxLlegada) > tN) break;
        if (this.tProxLlegada <= tc) this.llegada(this.tProxLlegada); else this.finServicio(kc, tc);
      }
      // 2. ingreso
      this.ingresarPendientes(tN);
      // 3. dinámica continua
      const porCarril = [];
      for (let k = 0; k < this.nCarriles; k++) porCarril.push([]);
      for (const veh of this.activos) porCarril[veh.carril].push(veh);
      for (let k = 0; k < this.nCarriles; k++) {
        porCarril[k].sort((A, B) => B.x - A.x || A.id - B.id);
        if (!p.modoFisico) continue;
        const ids = porCarril[k];
        for (let i = 0; i < ids.length; i++) {
          const ve = ids[i]; ve.acc = 0;
          if (ve.estado === 2) continue;
          let s = Infinity, dv = 0;
          // Líder: el vehículo inmediatamente adelante. Los que ya pagaron (estado 3)
          // salen por el abanico de salida y dejan de ser líderes de los que se aproximan.
          if (i > 0 && !(ve.estado === 1 && ids[i - 1].estado === 3)) {
            const L = ids[i - 1]; s = L.x - L.largo - ve.x; dv = ve.v - L.v;
          }
          let ac = idm(ve.v, ve.v0, ve.T, ve.a, ve.b, ve.s0, s, dv, p.delta);
          if (ve.estado === 1) {
            const acS = idm(ve.v, ve.v0, ve.T, ve.a, ve.b, ve.s0, p.L + ve.s0 - ve.x, ve.v, p.delta);
            ac = Math.min(ac, acS);
          }
          ve.acc = Math.max(ac, -p.aFrenadoMax);
        }
      }
      for (const ve of this.activos) {
        if (p.modoFisico && (ve.estado === 1 || ve.estado === 3)) {
          const vN = Math.max(ve.v + ve.acc * p.dt, 0);
          ve.x = ve.x + 0.5 * (ve.v + vN) * p.dt; ve.v = vN;
        }
      }
      // 4. eventos de estado
      for (let k = 0; k < this.nCarriles; k++) {
        if (this.cab.ocupadaPor[k] !== null) continue;
        let best = null;
        for (const ve of porCarril[k]) if (ve.estado === 1 && (best === null || ve.x > best.x)) best = ve;
        if (best && (p.L - best.x) < 1.0 && best.v < 1.0) this.inicioServicio(best, k, tN);
      }
      for (const ve of this.activos) if (ve.estado === 3 && (ve.x > p.xSalida || !p.modoFisico)) { ve.estado = 4; ve.tSalida = tN; }
      this.activos = this.activos.filter(ve => ve.estado !== 4);
      // 5. estadísticas
      const cola = new Array(this.nCarriles).fill(0);
      for (const ve of this.activos) if (ve.estado === 1 && ve.v < 1.5) cola[ve.carril]++;
      for (let k = 0; k < this.nCarriles; k++) {
        if (this.cab.ocupadaPor[k] !== null) this.cab.tOcupada[k] += p.dt;
        this.colaAcum[k] += cola[k] * p.dt;
      }
      this.ultimaCola = cola; this.t = tN;
      if (this.k % this.kMuestra === 0) {
        const mov = this.activos.filter(v => v.estado === 1);
        this.serie.t.push(tN); this.serie.cola.push(cola.slice());
        this.serie.ocupada.push(this.cab.ocupadaPor.map(x => x !== null ? 1 : 0));
        this.serie.enSistema.push(this.activos.length + this.pendientes.length);
        this.serie.velMedia.push(mov.length ? mov.reduce((s, v) => s + v.v, 0) / mov.length * 3.6 : 0);
      }
    }

    llegada(tA) {
      const p = this.p;
      const c = this.rng.discreta(p.mezcla);
      const tag = this.rng.bernoulli(p.propTag);
      let cand = [];
      for (let k = 0; k < this.nCarriles; k++) {
        if (tag && p.carrilesTag > 0) { if (this.esTag[k]) cand.push(k); }
        else if (p.carrilesManuales > 0) { if (!this.esTag[k]) cand.push(k); }
        else if (this.esTag[k]) cand.push(k);
      }
      let mejor = cand[0], cargaMin = Infinity;
      for (const k of cand) {
        let carga = 0;
        for (const ve of this.activos) if (ve.carril === k && (ve.estado === 1 || ve.estado === 2)) carga++;
        for (const ve of this.pendientes) if (ve.carril === k) carga++;
        if (carga < cargaMin) { cargaMin = carga; mejor = k; }
      }
      const q = p.cat[c];
      const ve = { id: this.V.length + 1, cat: c, tag, carril: mejor, estado: -1, tLleg: tA,
        tEntrada: NaN, tIni: NaN, tFinServ: NaN, tSalida: NaN, servicio: NaN, x: 0, v: 0, acc: 0,
        v0: q.v0 * p.factor_v0, T: q.T * p.factor_T, a: q.a * p.factor_a, b: q.b * p.factor_b, s0: q.s0, largo: q.largo };
      this.V.push(ve); this.pendientes.push(ve);
      this.maxPendientes = Math.max(this.maxPendientes, this.pendientes.length);
      this.tProxLlegada = tA + this.rng.exponencial(3600 / p.lambda);
    }

    finServicio(k, tc) {
      const ve = this.cab.ocupadaPor[k];
      ve.estado = 3; ve.tFinServ = tc;
      this.cab.ocupadaPor[k] = null; this.cab.tFin[k] = Infinity; this.cab.atendidos[k]++;
    }

    inicioServicio(ve, k, t) {
      const p = this.p, q = p.cat[ve.cat];
      const media = (this.esTag[k] ? p.servTag : p.servManual) * q.fServ;
      const cv = this.esTag[k] ? p.cvTag : p.cvManual;
      const serv = this.rng.lognormal(media, cv);
      ve.estado = 2; ve.x = p.L; ve.v = 0; ve.tIni = t; ve.servicio = serv;
      this.cab.ocupadaPor[k] = ve; this.cab.tFin[k] = t + serv; this.recaudo += q.tarifa;
    }

    ingresarPendientes(t) {
      if (!this.pendientes.length) return;
      if (!this.p.modoFisico) {
        // Modo discreto puro: el vehículo entra directo a la cola de su taquilla
        for (const ve of this.pendientes) { ve.estado = 1; ve.x = this.p.L; ve.v = 0; ve.tEntrada = t; this.activos.push(ve); }
        this.pendientes = []; return;
      }
      const quedan = [], bloq = new Array(this.nCarriles).fill(false);
      for (const ve of this.pendientes) {
        const k = ve.carril;
        if (bloq[k]) { quedan.push(ve); continue; }
        let ult = null;
        for (const o of this.activos) if (o.carril === k && (ult === null || o.x < ult.x || (o.x === ult.x && o.id < ult.id))) ult = o;
        let ok, vEnt;
        if (!ult) { ok = true; vEnt = ve.v0; }
        else { ok = (ult.x - ult.largo) >= ve.s0 + 2; vEnt = Math.min(ve.v0, ult.v); }
        if (ok) { ve.estado = 1; ve.x = 0; ve.v = vEnt; ve.tEntrada = t; this.activos.push(ve); }
        else { bloq[k] = true; quedan.push(ve); }
      }
      this.pendientes = quedan;
    }

    resultados() {
      const p = this.p, t = this.t;
      const R = { tSimulado: t, generados: this.V.length, recaudo: this.recaudo, maxRepresados: this.maxPendientes };
      R.utilizacion = this.cab.tOcupada.map(x => x / t);
      R.LqPorCarril = this.colaAcum.map(x => x / t);
      R.atendidosPorCabina = this.cab.atendidos.slice();
      const serv = this.V.filter(v => !isNaN(v.tIni));
      R.atendidos = serv.length;
      R.salieron = this.V.filter(v => v.estado === 4).length;
      const tot = p.mezcla.reduce((s, x) => s + x, 0);
      const mezcla = p.mezcla.map(x => x / tot), f = p.cat.map(c => c.fServ);
      const lt = p.lambda / 3600;
      const tAv = mezcla.reduce((s, m, i) => s + m * this.tAvance[i], 0);
      R.tLibre = this.tLibre.slice(); R.tAvance = this.tAvance.slice();
      const lam = tag => p.carrilesTag === 0 ? lt * (!tag) : p.carrilesManuales === 0 ? lt * tag : tag ? lt * p.propTag : lt * (1 - p.propTag);
      const grupo = (tag) => {
        const c = tag ? p.carrilesTag : p.carrilesManuales;
        const G = { c };
        if (c === 0) return G;
        const vs = serv.filter(v => this.esTag[v.carril] === tag);
        const dem = vs.map(v => Math.max(v.tIni - v.tLleg - this.tLibre[v.cat], 0));
        G.n = vs.length;
        G.Wq_sim = dem.reduce((s, x) => s + x, 0) / Math.max(dem.length, 1);
        G.Lq_sim = R.LqPorCarril.filter((_, k) => this.esTag[k] === tag).reduce((s, x) => s + x, 0);
        const us = R.utilizacion.filter((_, k) => this.esTag[k] === tag);
        G.rho_sim = us.reduce((s, x) => s + x, 0) / us.length;
        G.ES_sim = vs.reduce((s, v) => s + v.servicio, 0) / Math.max(vs.length, 1);
        const medias = f.map(fi => (tag ? p.servTag : p.servManual) * fi);
        const cv = tag ? p.cvTag : p.cvManual;
        const ES = mezcla.reduce((s, m, i) => s + m * medias[i], 0);
        const ES2 = mezcla.reduce((s, m, i) => s + m * medias[i] * medias[i] * (1 + cv * cv), 0);
        const cs2 = ES2 / (ES * ES) - 1;
        G.teoria = erlangC(lam(tag), ES, c, cs2);
        G.teoriaCorregida = erlangC(lam(tag), ES + tAv, c, cs2 * Math.pow(ES / (ES + tAv), 2));
        return G;
      };
      R.manual = grupo(false); R.tagGrupo = grupo(true);
      return R;
    }
  }

  function erlangC(lambda, ES, c, cs2 = 1) {
    const mu = 1 / ES, A = lambda * ES, rho = A / c;
    const Q = { lambda, ES, c, rho, A };
    if (rho >= 1) return Object.assign(Q, { estable: false, Pespera: 1, Wq: Infinity, Lq: Infinity, Wq_MMc: Infinity });
    let B = 1; for (let k = 1; k <= c; k++) B = A * B / (k + A * B);
    const C = c * B / (c - A * (1 - B));
    Q.estable = true; Q.Pespera = C; Q.Wq_MMc = C / (c * mu - lambda); Q.Lq_MMc = lambda * Q.Wq_MMc;
    Q.Wq = Q.Wq_MMc * (1 + cs2) / 2; Q.Lq = lambda * Q.Wq; Q.W = Q.Wq + ES;
    return Q;
  }

  const API = { GeneradorLCG, parametrosPeaje, idm, Motor, erlangC, tiempoRecorrido };
  if (typeof module !== 'undefined' && module.exports) module.exports = API; else global.Peaje = API;
})(typeof window !== 'undefined' ? window : globalThis);
