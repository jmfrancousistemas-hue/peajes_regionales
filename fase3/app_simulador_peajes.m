function app_simulador_peajes()
%APP_SIMULADOR_PEAJES Software interactivo (Fase 3) en MATLAB.
%   Interfaz con animación en tiempo real del simulador híbrido.
%   Responsable: Rol C (GUI y animación), usando el motor de los Roles A y B.
%
%   Ejecutar:  app_simulador_peajes
%   Funciona en MATLAB de escritorio y en MATLAB Online (navegador).
%   Para usarla desde App Designer: cree una app nueva y llame a
%   motor_inicializar / motor_paso / motor_resultados desde sus callbacks.

    raiz = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(raiz, 'fase1'), fullfile(raiz, 'fase2'));

    p = parametros_peaje();
    S = [];
    corriendo = false;
    colores = [0.13 0.47 0.71; 0.95 0.55 0.10; 0.80 0.15 0.15];   % Auto, Bus, Camión

    % ---------------- Ventana ----------------
    fig = uifigure('Name', 'Simulador Híbrido de Tráfico y Peajes - UNINTEP', ...
                   'Position', [60 60 1280 760], 'CloseRequestFcn', @cerrar);
    gl = uigridlayout(fig, [1 2]);
    gl.ColumnWidth = {280, '1x'};

    % ---------------- Panel de parámetros ----------------
    pnl = uipanel(gl, 'Title', 'Parámetros');
    g = uigridlayout(pnl, [17 2]);
    g.RowHeight = repmat({26}, 1, 17);
    g.ColumnWidth = {'1.3x', '1x'};
    uilabel(g, 'Text', 'Escenario');
    ddEsc = uidropdown(g, 'Items', {'Riofrío', 'Toro'}, 'ItemsData', {'riofrio', 'toro'}, ...
                       'Value', p.escenario, 'ValueChangedFcn', @cambiarEscenario);
    campos = { ...
        'semilla',          'Semilla',                 p.semilla;
        'lambda',           'Llegadas λ (veh/h)',      p.lambda;
        'carrilesManuales', 'Taquillas manuales',      p.carrilesManuales;
        'carrilesTag',      'Taquillas TAG',           p.carrilesTag;
        'propTag',          'Proporción con TAG',      p.propTag;
        'servManual',       'Cobro manual medio (s)',  p.servManual;
        'servTag',          'Cobro TAG medio (s)',     p.servTag;
        'factor_v0',        'Factor velocidad v0',     p.factor_v0;
        'factor_T',         'Factor brecha T',         p.factor_T;
        'factor_a',         'Factor aceleración a',    p.factor_a;
        'factor_b',         'Factor frenado b',        p.factor_b;
        'tFin',             'Duración (s)',            p.tFin};
    ed = struct();
    for i = 1:size(campos, 1)
        uilabel(g, 'Text', campos{i, 2});
        ed.(campos{i, 1}) = uieditfield(g, 'numeric', 'Value', campos{i, 3});
    end
    uilabel(g, 'Text', 'Velocidad animación');
    sldVel = uislider(g, 'Limits', [1 60], 'Value', 10);
    uilabel(g, 'Text', 'Modo físico (IDM)');  % cambios de parámetros aplican al Reiniciar
    chkFis = uicheckbox(g, 'Text', '', 'Value', true);
    btnIni = uibutton(g, 'Text', '▶ Iniciar', 'ButtonPushedFcn', @iniciar);
    btnPau = uibutton(g, 'Text', '⏸ Pausar', 'ButtonPushedFcn', @pausar);
    btnRes = uibutton(g, 'Text', '⟲ Reiniciar', 'ButtonPushedFcn', @reiniciar);
    btnExp = uibutton(g, 'Text', 'Exportar JSON', 'ButtonPushedFcn', @exportar);

    % ---------------- Panel de visualización ----------------
    der = uigridlayout(gl, [3 2]);
    der.RowHeight = {'1.3x', '1x', 90};
    axVia = uiaxes(der); axVia.Layout.Row = 1; axVia.Layout.Column = [1 2];
    axCola = uiaxes(der); axCola.Layout.Row = 2; axCola.Layout.Column = 1;
    axVel = uiaxes(der);  axVel.Layout.Row = 2;  axVel.Layout.Column = 2;
    txtKPI = uitextarea(der, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 13);
    txtKPI.Layout.Row = 3; txtKPI.Layout.Column = [1 2];

    hVeh = gobjects(0); hCab = gobjects(0); lnCola = gobjects(0); lnVel = gobjects(0);
    reiniciar();

    % ======================================================================
    function cambiarEscenario(~, ~)
        % Carga λ y la mezcla del escenario elegido y reinicia
        q = parametros_peaje(ddEsc.Value);
        ed.lambda.Value = q.lambda;
        reiniciar();
    end

    function leerParametros()
        p = parametros_peaje(ddEsc.Value);
        f = fieldnames(ed);
        for j = 1:numel(f), p.(f{j}) = ed.(f{j}).Value; end
        p.carrilesManuales = round(p.carrilesManuales);
        p.carrilesTag = round(p.carrilesTag);
        p.modoFisico = chkFis.Value;
    end

    function reiniciar(~, ~)
        corriendo = false;
        leerParametros();
        S = motor_inicializar(p);
        dibujarEscenario();
        actualizar();
    end

    function dibujarEscenario()
        nC = S.nCarriles;
        cla(axVia); hold(axVia, 'on');
        axVia.XLim = [0 p.xSalida]; axVia.YLim = [0.3 nC + 0.7];
        axVia.YTick = 1:nC;
        axVia.YTickLabel = [compose('Manual %d', 1:p.carrilesManuales), compose('TAG %d', 1:p.carrilesTag)];
        axVia.XLabel.String = 'Posición (m)';
        title(axVia, 'Vía de aproximación y plaza de peaje');
        for k = 1:nC
            plot(axVia, [0 p.xSalida], [k k], '-', 'Color', [0.85 0.85 0.85], 'LineWidth', 10);
        end
        xline(axVia, p.L, 'k-', 'LineWidth', 2);
        hCab = gobjects(1, nC);
        for k = 1:nC
            hCab(k) = rectangle(axVia, 'Position', [p.L - 3, k - 0.35, 6, 0.7], ...
                                'FaceColor', [0.3 0.75 0.3], 'EdgeColor', 'k');
        end
        hVeh = patch(axVia, 'Vertices', zeros(0, 2), 'Faces', zeros(0, 4), ...
                     'FaceVertexCData', zeros(0, 3), 'FaceColor', 'flat', 'EdgeColor', 'none');

        cla(axCola); hold(axCola, 'on'); grid(axCola, 'on');
        title(axCola, 'Vehículos en cola por carril'); xlabel(axCola, 'Tiempo (min)');
        lnCola = gobjects(1, nC);
        for k = 1:nC, lnCola(k) = animatedline(axCola, 'Color', lines_color(k), 'LineWidth', 1.2); end
        cla(axVel); hold(axVel, 'on'); grid(axVel, 'on');
        title(axVel, 'Velocidad media de aproximación (km/h)'); xlabel(axVel, 'Tiempo (min)');
        lnVel = animatedline(axVel, 'Color', [0.2 0.2 0.6], 'LineWidth', 1.2);
    end

    function c = lines_color(k)
        L = lines(max(k, 7)); c = L(k, :);
    end

    function iniciar(~, ~)
        if corriendo, return; end
        if isempty(S) || S.k >= round(p.tFin / p.dt), reiniciar(); end
        corriendo = true;
        nPasos = round(p.tFin / p.dt);
        while corriendo && S.k < nPasos && isvalid(fig)
            pasosPorCuadro = max(1, round(sldVel.Value));
            for j = 1:pasosPorCuadro
                S = motor_paso(S);
                if S.k >= nPasos, break; end
            end
            actualizar();
            drawnow limitrate;
        end
        corriendo = false;
        if isvalid(fig), mostrarResultados(); end
    end

    function pausar(~, ~)
        corriendo = false;
    end

    function actualizar()
        if ~isvalid(fig), return; end
        n = S.nV;
        act = find(S.V.estado(1:n) >= 1 & S.V.estado(1:n) <= 3);
        % Todos los vehículos en un solo patch (mucho más rápido que un objeto por vehículo)
        N = numel(act);
        x1 = S.V.x(act) - S.V.largo(act); x2 = S.V.x(act);
        y1 = S.V.carril(act) - 0.22;      y2 = S.V.carril(act) + 0.22;
        Vtx = zeros(4 * N, 2);
        Vtx(1:4:end, :) = [x1 y1]; Vtx(2:4:end, :) = [x2 y1];
        Vtx(3:4:end, :) = [x2 y2]; Vtx(4:4:end, :) = [x1 y2];
        if N > 0
            set(hVeh, 'Vertices', Vtx, 'Faces', reshape(1:4*N, 4, N)', ...
                'FaceVertexCData', colores(S.V.cat(act), :));
        else
            set(hVeh, 'Vertices', zeros(0, 2), 'Faces', zeros(0, 4), 'FaceVertexCData', zeros(0, 3));
        end
        for k = 1:S.nCarriles
            if S.cabina.ocupadaPor(k) > 0
                hCab(k).FaceColor = [0.85 0.2 0.2];
            else
                hCab(k).FaceColor = [0.3 0.75 0.3];
            end
        end
        tMin = S.t / 60;
        for k = 1:S.nCarriles, addpoints(lnCola(k), tMin, S.ultimaCola(k)); end
        mov = S.V.estado(1:n) == 1;
        if any(mov), addpoints(lnVel, tMin, mean(S.V.v(mov)) * 3.6); end
        rho = S.cabina.tOcupada / max(S.t, eps);
        txtKPI.Value = { ...
            sprintf('t = %6.1f s  |  generados %d  |  en vía %d  |  represados en entrada %d', ...
                    S.t, S.nV, numel(act), numel(S.pendientes)), ...
            sprintf('Utilización por taquilla: %s', mat2str(round(rho, 2))), ...
            sprintf('Atendidos por taquilla:   %s   |  Recaudo $%s COP', ...
                    mat2str(S.cabina.atendidos), num2str(S.recaudo, '%.0f'))};
        title(axVia, sprintf('Vía de aproximación y plaza de peaje   t = %.0f s', S.t));
    end

    function mostrarResultados()
        R = motor_resultados(S);
        lineas = txtKPI.Value;
        if R.manual.c > 0
            lineas{end+1} = sprintf('MANUAL: rho %.3f (teo %.3f) | Wq %.1f s (M/G/c %.1f, con avance %.1f) | Lq %.2f', ...
                R.manual.rho_sim, R.manual.teoria.rho, R.manual.Wq_sim, R.manual.teoria.Wq, ...
                R.manual.teoriaCorregida.Wq, R.manual.Lq_sim);
        end
        if R.tagGrupo.c > 0
            lineas{end+1} = sprintf('TAG:    rho %.3f (teo %.3f) | Wq %.1f s (M/G/c %.1f, con avance %.1f) | Lq %.2f', ...
                R.tagGrupo.rho_sim, R.tagGrupo.teoria.rho, R.tagGrupo.Wq_sim, R.tagGrupo.teoria.Wq, ...
                R.tagGrupo.teoriaCorregida.Wq, R.tagGrupo.Lq_sim);
        end
        txtKPI.Value = lineas;
    end

    function exportar(~, ~)
        R = motor_resultados(S);
        archivo = fullfile(raiz, 'web', 'corrida_matlab.json');
        exportar_json(R, archivo);
        uialert(fig, sprintf('Corrida guardada en:\n%s', archivo), 'Exportar', 'Icon', 'success');
    end

    function cerrar(~, ~)
        corriendo = false;
        delete(fig);
    end
end
