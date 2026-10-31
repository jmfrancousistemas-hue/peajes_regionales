function S = motor_paso(S)
%MOTOR_PASO Avanza el simulador híbrido un paso dt.
%   Orden dentro de cada paso (es el "acoplamiento híbrido"):
%     1. EVENTOS DISCRETOS programados con tiempo <= t+dt (llegadas y
%        fines de servicio), en orden cronológico.         -> Rol B
%     2. Ingreso de vehículos que esperan espacio en la entrada.
%     3. DINÁMICA CONTINUA: IDM para todos los vehículos en movimiento,
%        integración semi-implícita (Euler con regla trapezoidal en x). -> Rol A
%     4. EVENTOS DE ESTADO: un vehículo que llega detenido a una taquilla
%        libre dispara INICIO DE SERVICIO (lo detecta la parte continua y
%        lo programa la parte discreta); los que pasan xSalida salen.
%     5. Estadísticas y series.                              -> Rol C

    p = S.p;
    S.k = S.k + 1;
    tN = S.k * p.dt;

    % ---------- 1. Eventos discretos ----------
    while true
        [tc, kc] = min(S.cabina.tFin);
        if min(tc, S.tProxLlegada) > tN, break; end
        if S.tProxLlegada <= tc
            S = evento_llegada(S, S.tProxLlegada);
        else
            S = evento_fin_servicio(S, kc, tc);
        end
    end

    % ---------- 2. Ingreso desde la entrada ----------
    S = ingresar_pendientes(S, tN);

    % ---------- 3. Dinámica continua ----------
    V = S.V;
    n = S.nV;
    acc = zeros(n, 1);
    for k = 1:S.nCarriles
        ids = find(V.carril(1:n) == k & V.estado(1:n) >= 1 & V.estado(1:n) <= 3);
        [~, orden] = sort(V.x(ids), 'descend');
        ids = ids(orden);
        if ~p.modoFisico, continue; end
        for i = 1:numel(ids)
            id = ids(i);
            if V.estado(id) == 2, continue; end          % detenido pagando
            % Los que ya pagaron (estado 3) salen por el abanico de salida y
            % dejan de ser líderes de los que se aproximan
            if i == 1 || (V.estado(id) == 1 && V.estado(ids(i-1)) == 3)
                s = inf; dv = 0;
            else
                idL = ids(i-1);
                s = V.x(idL) - V.largo(idL) - V.x(id);
                dv = V.v(id) - V.v(idL);
            end
            ac = idm_aceleracion(V.v(id), V.v0(id), V.T(id), V.a(id), V.b(id), V.s0(id), s, dv, p.delta);
            if V.estado(id) == 1
                % Línea de pare virtual: obstáculo detenido en x = L + s0,
                % así el vehículo queda detenido justo en la taquilla (x = L)
                acStop = idm_aceleracion(V.v(id), V.v0(id), V.T(id), V.a(id), V.b(id), V.s0(id), ...
                                         p.L + V.s0(id) - V.x(id), V.v(id), p.delta);
                ac = min(ac, acStop);
            end
            acc(id) = max(ac, -p.aFrenadoMax);
        end
    end
    mov = find(p.modoFisico & (V.estado(1:n) == 1 | V.estado(1:n) == 3));
    vNueva = max(V.v(mov) + acc(mov) * p.dt, 0);
    V.x(mov) = V.x(mov) + 0.5 * (V.v(mov) + vNueva) * p.dt;
    V.v(mov) = vNueva;
    V.acc(1:n) = acc;
    S.V = V;

    % ---------- 4. Eventos de estado ----------
    for k = 1:S.nCarriles
        if S.cabina.ocupadaPor(k) ~= 0, continue; end
        ids = find(S.V.carril(1:n) == k & S.V.estado(1:n) == 1);
        if isempty(ids), continue; end
        [~, j] = max(S.V.x(ids));
        id = ids(j);
        if (p.L - S.V.x(id)) < 1.0 && S.V.v(id) < 1.0
            S = evento_inicio_servicio(S, id, k, tN);
        end
    end
    sal = find(S.V.estado(1:n) == 3 & (S.V.x(1:n) > p.xSalida | ~p.modoFisico));
    S.V.estado(sal) = 4;
    S.V.tSalida(sal) = tN;

    % ---------- 5. Estadísticas ----------
    ocup = S.cabina.ocupadaPor > 0;
    S.cabina.tOcupada = S.cabina.tOcupada + ocup * p.dt;
    cola = zeros(1, S.nCarriles);
    for k = 1:S.nCarriles
        cola(k) = sum(S.V.carril(1:n) == k & S.V.estado(1:n) == 1 & S.V.v(1:n) < 1.5);
    end
    S.colaAcum = S.colaAcum + cola * p.dt;
    S.ultimaCola = cola;
    S.t = tN;

    if mod(S.k, S.kMuestra) == 0
        S.iMuestra = S.iMuestra + 1;
        i = S.iMuestra;
        if i <= numel(S.serie.t)
            activos = S.V.estado(1:n) >= 1 & S.V.estado(1:n) <= 3;
            enMov = S.V.estado(1:n) == 1;
            S.serie.t(i) = tN;
            S.serie.cola(i, :) = cola;
            S.serie.ocupada(i, :) = ocup;
            S.serie.enSistema(i) = sum(activos) + numel(S.pendientes);
            if any(enMov)
                S.serie.velMedia(i) = mean(S.V.v(enMov)) * 3.6;
            else
                S.serie.velMedia(i) = 0;
            end
        end
    end
end

% ======================================================================
function S = evento_llegada(S, tA)
% LLEGADA: se crea el vehículo, se sortean categoría y TAG, se elige carril
% y se programa la siguiente llegada (tiempos entre llegadas exponenciales).
    p = S.p;
    id = S.nV + 1;
    S.nV = id;
    c   = S.rng.discreta(p.mezcla);
    tag = S.rng.bernoulli(p.propTag);

    if tag && p.carrilesTag > 0
        candidatos = find(S.esTag);
    elseif p.carrilesManuales > 0
        candidatos = find(~S.esTag);
    else
        candidatos = find(S.esTag);
    end
    % Regla de elección: carril con menos vehículos (empate: el de menor índice)
    n = S.nV;
    carga = zeros(size(candidatos));
    for j = 1:numel(candidatos)
        carga(j) = sum(S.V.carril(1:n) == candidatos(j) & ...
                      (S.V.estado(1:n) == -1 | S.V.estado(1:n) == 1 | S.V.estado(1:n) == 2));
    end
    [~, j] = min(carga);
    q = p.cat(c);

    S.V.cat(id) = c;
    S.V.tag(id) = tag;
    S.V.carril(id) = candidatos(j);
    S.V.estado(id) = -1;
    S.V.tLleg(id) = tA;
    S.V.v0(id) = q.v0 * p.factor_v0;
    S.V.T(id)  = q.T  * p.factor_T;
    S.V.a(id)  = q.a  * p.factor_a;
    S.V.b(id)  = q.b  * p.factor_b;
    S.V.s0(id) = q.s0;
    S.V.largo(id) = q.largo;
    S.pendientes(end+1, 1) = id;
    S.maxPendientes = max(S.maxPendientes, numel(S.pendientes));

    S.tProxLlegada = tA + S.rng.exponencial(3600 / p.lambda);
end

function S = evento_fin_servicio(S, k, tc)
% FIN DE SERVICIO: el vehículo pagó, se levanta la talanquera y sale.
    id = S.cabina.ocupadaPor(k);
    S.V.estado(id) = 3;
    S.V.tFinServ(id) = tc;
    S.cabina.ocupadaPor(k) = 0;
    S.cabina.tFin(k) = inf;
    S.cabina.atendidos(k) = S.cabina.atendidos(k) + 1;
end

function S = evento_inicio_servicio(S, id, k, t)
% INICIO DE SERVICIO (evento de estado): se sortea el tiempo de cobro y se
% programa el FIN DE SERVICIO en la lista de eventos futuros.
    p = S.p;
    c = S.V.cat(id);
    if S.esTag(k)
        media = p.servTag * p.cat(c).fServ;
        cv = p.cvTag;
    else
        media = p.servManual * p.cat(c).fServ;
        cv = p.cvManual;
    end
    serv = S.rng.lognormal(media, cv);
    S.V.estado(id) = 2;
    S.V.x(id) = p.L;
    S.V.v(id) = 0;
    S.V.tIni(id) = t;
    S.V.servicio(id) = serv;
    S.cabina.ocupadaPor(k) = id;
    S.cabina.tFin(k) = t + serv;
    S.recaudo = S.recaudo + p.cat(c).tarifa;
end

function S = ingresar_pendientes(S, t)
% Un vehículo entra al tramo en x = 0 solo si hay espacio detrás del último
% de su carril; si no, queda represado (cola que desborda el tramo).
    if isempty(S.pendientes), return; end
    if ~S.p.modoFisico
        % Modo discreto puro: el vehículo entra directo a la cola de su taquilla
        id = S.pendientes;
        S.V.estado(id) = 1; S.V.x(id) = S.p.L; S.V.v(id) = 0; S.V.tEntrada(id) = t;
        S.pendientes = zeros(0, 1);
        return;
    end
    n = S.nV;
    quedan = zeros(0, 1);
    bloqueado = false(1, S.nCarriles);
    for i = 1:numel(S.pendientes)
        id = S.pendientes(i);
        k = S.V.carril(id);
        if bloqueado(k)
            quedan(end+1, 1) = id; %#ok<AGROW>
            continue;
        end
        ids = find(S.V.carril(1:n) == k & S.V.estado(1:n) >= 1 & S.V.estado(1:n) <= 3);
        if isempty(ids)
            vEnt = S.V.v0(id);
            ok = true;
        else
            [~, j] = min(S.V.x(ids));
            ult = ids(j);
            hueco = S.V.x(ult) - S.V.largo(ult);
            ok = hueco >= S.V.s0(id) + 2;
            vEnt = min(S.V.v0(id), S.V.v(ult));
        end
        if ok
            S.V.estado(id) = 1;
            S.V.x(id) = 0;
            S.V.v(id) = vEnt;
            S.V.tEntrada(id) = t;
        else
            bloqueado(k) = true;
            quedan(end+1, 1) = id; %#ok<AGROW>
        end
    end
    S.pendientes = quedan;
end
