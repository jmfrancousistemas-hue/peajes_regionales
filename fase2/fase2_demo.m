%% FASE 2 - Núcleo matemático del simulador híbrido (backend)
% Proyecto Final - Modelos de Simulación (UNINTEP)
% Alternativa 1: Simulador Híbrido de Tráfico y Peajes Regionales
%
% 1. Corrida base con física (IDM + eventos discretos)
% 2. Verificación: modo discreto puro contra Erlang C (30 réplicas)
% 3. Efecto de la física: tiempo de avance a la taquilla
% 4. Gráficas de series de tiempo

clear; clc; close all;
raiz = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(raiz, 'fase1'), fullfile(raiz, 'fase2'));

%% 1. Corrida base
p = parametros_peaje();
tic; R = simular_peaje(p); fprintf('Corrida de %g s simulada en %.1f s reales\n', p.tFin, toc);
imprimir_resumen(R);

%% 2. Verificación del motor discreto (Rol B) con réplicas independientes
nRep = 30;
pv = parametros_peaje();
pv.modoFisico = false;     % sin dinámica continua: debe parecerse a M/G/c
pv.tFin = 4 * 3600;
W = zeros(nRep, 1); rho = zeros(nRep, 1);
for r = 1:nRep
    pv.semilla = 1000 + 7919 * r;
    Rv = simular_peaje(pv);
    W(r) = Rv.manual.Wq_sim;
    rho(r) = Rv.manual.rho_sim;
end
ic = 1.96 * std(W) / sqrt(nRep);
fprintf('\nVERIFICACIÓN (modo discreto puro, %d réplicas de 4 h):\n', nRep);
fprintf('  rho simulada %.3f vs teórica %.3f\n', mean(rho), Rv.manual.teoria.rho);
fprintf('  Wq  simulada %.2f ± %.2f s | M/G/c (cola común) %.2f s | M/M/c %.2f s\n', ...
        mean(W), ic, Rv.manual.teoria.Wq, Rv.manual.teoria.Wq_MMc);
fprintf('  Nota: con carriles separados (sin cambiar de fila) la espera es algo\n');
fprintf('  mayor que con una cola común, por eso Wq queda entre M/G/c y M/M/c.\n');

%% 3. Gráficas de la corrida base
s = R.serie;
figure('Name', 'Fase 2 - Series de tiempo', 'Color', 'w', 'Position', [80 80 1100 650]);
subplot(3,1,1);
plot(s.t/60, s.cola, 'LineWidth', 1);
ylabel('Vehículos en cola'); grid on;
legend([compose('Manual %d', 1:p.carrilesManuales), compose('TAG %d', 1:p.carrilesTag)], 'Location', 'northwest');
title(sprintf('Cola por carril (semilla %d, \\lambda = %g veh/h)', p.semilla, p.lambda));
subplot(3,1,2);
plot(s.t/60, cumsum(s.ocupada) ./ (1:numel(s.t))', 'LineWidth', 1.2); hold on;
yline(R.manual.teoria.rho, 'k--', '\rho teórica manual');
ylabel('Utilización acumulada'); grid on; ylim([0 1]);
title('La utilización converge a \rho = \lambda E[S] / c');
subplot(3,1,3);
plot(s.t/60, s.velMedia, 'LineWidth', 1);
ylabel('Velocidad media (km/h)'); xlabel('Tiempo (min)'); grid on;
title('Velocidad media de los vehículos que se aproximan');

figure('Name', 'Demora por vehículo', 'Color', 'w');
T = R.vehiculos;
histogram(T.demora(~T.tag), 30); hold on; histogram(T.demora(T.tag), 30);
xlabel('Demora por el peaje (s)'); ylabel('Vehículos'); legend('Manual', 'TAG');
title('Distribución de la demora');

%% 4. Exportar para la aplicación web
exportar_json(R, fullfile(raiz, 'web', 'corrida_matlab.json'));
