function R = motor_resultados(S)
%MOTOR_RESULTADOS Indicadores de desempeño y comparación con la teoría.
%   Responsable: Rol C (auditoría estadística de salida).

    p = S.p;
    n = S.nV;
    V = S.V;
    t = S.t;
    R.p = p;
    R.tSimulado = t;
    R.generados = n;
    R.atendidos = sum(~isnan(V.tIni(1:n)));
    R.salieron  = sum(V.estado(1:n) == 4);
    R.enSistemaFinal = sum(V.estado(1:n) >= 1 & V.estado(1:n) <= 3) + numel(S.pendientes);
    R.maxRepresados = S.maxPendientes;
    R.recaudo = S.recaudo;
    R.utilizacion = S.cabina.tOcupada / t;          % por taquilla
    R.atendidosPorCabina = S.cabina.atendidos;
    R.LqPorCarril = S.colaAcum / t;                 % promedio temporal de la cola
    R.serie = S.serie;
    R.serie.t = R.serie.t(1:S.iMuestra);
    R.serie.cola = R.serie.cola(1:S.iMuestra, :);
    R.serie.ocupada = R.serie.ocupada(1:S.iMuestra, :);
    R.serie.enSistema = R.serie.enSistema(1:S.iMuestra);
    R.serie.velMedia = R.serie.velMedia(1:S.iMuestra);

    % Demora por peaje = tiempo real hasta la taquilla - tiempo sin congestión
    serv = find(~isnan(V.tIni(1:n)));
    demora = V.tIni(serv) - V.tLleg(serv) - S.tLibre(V.cat(serv))';
    demora = max(demora, 0);
    esTagVeh = S.esTag(V.carril(serv))';
    R.vehiculos = table(serv, V.cat(serv), V.tag(serv), V.carril(serv), V.tLleg(serv), ...
                        V.tIni(serv), V.servicio(serv), demora, ...
                        'VariableNames', {'id','categoria','tag','carril','tLlegada', ...
                                          'tInicioServicio','tServicio','demora'});

    % ---------- Grupo manual ----------
    mezcla = p.mezcla(:)' / sum(p.mezcla);
    f = [p.cat.fServ];
    R.tLibre = S.tLibre;
    R.tAvance = S.tAvance;
    tAv = sum(mezcla .* S.tAvance);    % tiempo medio de avance a la taquilla
    R.manual = grupo(p.carrilesManuales, ~S.esTag, demora(~esTagVeh), V.servicio(serv(~esTagVeh)), ...
        R, t, lambdaGrupo(p, false), p.servManual * f, p.cvManual, mezcla, tAv);
    R.tagGrupo = grupo(p.carrilesTag, S.esTag, demora(esTagVeh), V.servicio(serv(esTagVeh)), ...
        R, t, lambdaGrupo(p, true), p.servTag * f, p.cvTag, mezcla, tAv);
end

function lam = lambdaGrupo(p, tag)
% Tasa de llegada (veh/s) que recibe cada grupo de taquillas
    lt = p.lambda / 3600;
    if p.carrilesTag == 0
        lam = lt * (~tag);
    elseif p.carrilesManuales == 0
        lam = lt * tag;
    elseif tag
        lam = lt * p.propTag;
    else
        lam = lt * (1 - p.propTag);
    end
end

function G = grupo(c, mascara, demora, servicios, R, t, lam, medias, cv, mezcla, tAv)
    G.c = c;
    G.n = numel(demora);
    if c == 0
        G.Wq_sim = NaN; G.Lq_sim = NaN; G.rho_sim = NaN; G.ES_sim = NaN; G.teoria = []; G.teoriaCorregida = []; return;
    end
    G.Wq_sim  = mean(demora);
    G.Wq_ic95 = 1.96 * std(demora) / sqrt(max(numel(demora), 1));
    G.Lq_sim  = sum(R.LqPorCarril(mascara));
    G.rho_sim = mean(R.utilizacion(mascara));
    G.ES_sim  = mean(servicios);
    G.lambda_sim = G.n / t;
    % Teoría: mezcla de lognormales -> E[S] y cs^2 de la mezcla
    ES  = sum(mezcla .* medias);
    ES2 = sum(mezcla .* medias.^2 * (1 + cv^2));
    cs2 = ES2 / ES^2 - 1;
    G.teoria = erlang_c(lam, ES, c, cs2);
    % Teoría corregida: la taquilla queda bloqueada también mientras el
    % siguiente vehículo avanza hasta ella -> servicio efectivo = ES + tAvance
    % (tAvance es casi determinístico, por eso la varianza no cambia)
    G.teoriaCorregida = erlang_c(lam, ES + tAv, c, cs2 * (ES / (ES + tAv))^2);
end
