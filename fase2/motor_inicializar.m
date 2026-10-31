function S = motor_inicializar(p)
%MOTOR_INICIALIZAR Crea el estado inicial del simulador híbrido.
%   Responsable: Rol B (motor de simulación).
%
%   Estado S:
%     S.k, S.t          contador de pasos y reloj de simulación (t = k*dt)
%     S.V               matriz de datos de vehículos (estructura de arreglos)
%     S.cabina          estado de cada taquilla (servidor)
%     S.tProxLlegada    próximo evento de LLEGADA
%     S.cabina.tFin     próximos eventos de FIN DE SERVICIO (Inf = libre)
%   La LISTA DE EVENTOS FUTUROS es [S.tProxLlegada, S.cabina.tFin];
%   el siguiente evento es su mínimo.
%
%   Estados de un vehículo (V.estado):
%     0 sin crear | -1 en la entrada esperando espacio | 1 aproximándose/en cola
%     2 en servicio en la taquilla | 3 saliendo | 4 fuera del sistema

    if nargin < 1, p = parametros_peaje(); end
    S.p = p;
    S.rng = GeneradorLCG(p.semilla);
    S.k = 0;
    S.t = 0;

    nC = p.carrilesManuales + p.carrilesTag;
    S.nCarriles = nC;
    S.esTag = [false(1, p.carrilesManuales), true(1, p.carrilesTag)];

    cap = ceil(p.lambda * p.tFin / 3600 * 1.5) + 200;
    z = zeros(cap, 1);
    S.V = struct('x', z, 'v', z, 'acc', z, 'cat', z, 'tag', false(cap,1), ...
                 'carril', z, 'estado', z, 'tLleg', nan(cap,1), 'tEntrada', nan(cap,1), ...
                 'tIni', nan(cap,1), 'tFinServ', nan(cap,1), 'tSalida', nan(cap,1), ...
                 'servicio', nan(cap,1), 'v0', z, 'T', z, 'a', z, 'b', z, 's0', z, 'largo', z);
    S.nV = 0;
    S.pendientes = zeros(0, 1);   % FIFO de vehículos bloqueados en la entrada

    S.cabina.ocupadaPor = zeros(1, nC);
    S.cabina.tFin       = inf(1, nC);
    S.cabina.tOcupada   = zeros(1, nC);
    S.cabina.atendidos  = zeros(1, nC);
    S.colaAcum          = zeros(1, nC);   % integral de la longitud de cola (para Lq)
    S.ultimaCola        = zeros(1, nC);
    S.recaudo = 0;
    S.maxPendientes = 0;

    % Primer evento de llegada (primer número aleatorio consumido)
    S.tProxLlegada = S.rng.exponencial(3600 / p.lambda);

    % Series de tiempo para gráficas
    nM = floor(p.tFin / p.muestreo) + 1;
    S.serie.t         = nan(nM, 1);
    S.serie.cola      = nan(nM, nC);
    S.serie.ocupada   = nan(nM, nC);
    S.serie.enSistema = nan(nM, 1);
    S.serie.velMedia  = nan(nM, 1);
    S.iMuestra = 0;
    S.kMuestra = round(p.muestreo / p.dt);

    % Tiempo de recorrido sin congestión por categoría (referencia de demora)
    % y tiempo de avance desde la posición de espera hasta la taquilla
    S.tLibre  = zeros(1, numel(p.cat));
    S.tAvance = zeros(1, numel(p.cat));
    for c = 1:numel(p.cat)
        if p.modoFisico
            S.tLibre(c)  = tiempo_recorrido(p, c, 0, p.cat(c).v0 * p.factor_v0);
            S.tAvance(c) = tiempo_recorrido(p, c, p.L - p.cat(1).largo - p.cat(c).s0, 0);
        end
    end
end

function t = tiempo_recorrido(p, c, x, v)
% Un vehículo solo, desde (x, v) hasta detenerse en la taquilla, con el
% mismo integrador y la misma condición de llegada que el motor.
%   tLibre:  desde x = 0 a velocidad deseada (recorrido sin congestión)
%   tAvance: desde la posición de espera detrás de un auto en servicio
    q = p.cat(c);
    v0 = q.v0 * p.factor_v0; T = q.T * p.factor_T;
    a = q.a * p.factor_a;    b = q.b * p.factor_b;
    k = 0;
    while k < 1e6
        acc = idm_aceleracion(v, v0, T, a, b, q.s0, p.L + q.s0 - x, v, p.delta);
        acc = max(acc, -p.aFrenadoMax);
        vN = max(v + acc * p.dt, 0);
        x = x + 0.5 * (v + vN) * p.dt;
        v = vN;
        k = k + 1;
        if (p.L - x) < 1.0 && v < 1.0, break; end
    end
    t = k * p.dt;
end
