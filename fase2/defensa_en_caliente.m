%% DEFENSA EN CALIENTE
% El docente cambia UNA línea de la sección "Cambio del docente" y el equipo
% ejecuta este script. Se comparan la corrida base y la modificada, y se
% imprime hacia qué valor debe estabilizarse cada indicador según la teoría.

clear; clc; close all;
raiz = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(raiz, 'fase1'), fullfile(raiz, 'fase2'));

base = parametros_peaje();
pm   = base;

%% ===== Cambio del docente (edite UNA línea) =====
pm.semilla  = 2026;     % otra semilla
% pm.factor_b = 0.5;    % frenado más suave
% pm.lambda   = 550;    % más tráfico
% pm.servManual = 25;   % cobro más lento
% pm.carrilesManuales = 2;
%% ================================================

Rb = simular_peaje(base);
Rm = simular_peaje(pm);

fprintf('%-34s %12s %12s\n', 'Indicador', 'Base', 'Modificado');
fila = @(n, a, b) fprintf('%-34s %12.3f %12.3f\n', n, a, b);
fila('Vehículos generados', Rb.generados, Rm.generados);
fila('Utilización manual (rho)', Rb.manual.rho_sim, Rm.manual.rho_sim);
fila('rho teórica = lambda*E[S]/c', Rb.manual.teoria.rho, Rm.manual.teoria.rho);
fila('Wq manual simulada (s)', Rb.manual.Wq_sim, Rm.manual.Wq_sim);
fila('Wq M/G/c con avance (s)', Rb.manual.teoriaCorregida.Wq, Rm.manual.teoriaCorregida.Wq);
fila('Lq manual simulada (veh)', Rb.manual.Lq_sim, Rm.manual.Lq_sim);
fila('Recorrido libre Auto (s)', Rb.tLibre(1), Rm.tLibre(1));
fila('Avance a taquilla Auto (s)', Rb.tAvance(1), Rm.tAvance(1));
fila('Recaudo (millones COP)', Rb.recaudo/1e6, Rm.recaudo/1e6);

fprintf('\nCómo explicarlo en el tablero:\n');
fprintf(' - La utilización se estabiliza en rho = lambda*E[S]/c = %.3f (no depende de la física\n', Rm.manual.teoria.rho);
fprintf('   ni de la semilla mientras rho_efectiva < 1).\n');
fprintf(' - Con avance, el servicio efectivo es E[S] + t_avance = %.1f + %.1f s,\n', ...
        Rm.manual.teoria.ES, sum(pm.mezcla/sum(pm.mezcla) .* Rm.tAvance));
fprintf('   rho efectiva = %.3f. Si se acerca a 1, la cola crece sin límite.\n', Rm.manual.teoriaCorregida.rho);
fprintf(' - Cada vehículo se detiene en x = L = %g m (distancia s0 al obstáculo virtual).\n', pm.L);

figure('Color', 'w', 'Name', 'Defensa en caliente');
plot(Rb.serie.t/60, sum(Rb.serie.cola(:, 1:base.carrilesManuales), 2)); hold on;
plot(Rm.serie.t/60, sum(Rm.serie.cola(:, 1:pm.carrilesManuales), 2));
xlabel('Tiempo (min)'); ylabel('Vehículos en cola (manuales)'); grid on;
legend('Base', 'Modificado'); title('Cola total en taquillas manuales');
