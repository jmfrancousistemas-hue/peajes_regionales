%% FASE 1 - Generador de números pseudoaleatorios U(0,1)
% Proyecto Final - Modelos de Simulación
% Alternativa 1: Simulador Híbrido de Tráfico y Peajes Regionales
%
% Ejecutar con F5. Cambie la semilla para la "defensa en caliente".

clear; clc; close all;
addpath(fileparts(mfilename('fullpath')));

semilla = 256;     % Valor de semilla
n       = 10000;     % tamaño de la muestra
alfa    = 0.05;

g = GeneradorLCG(semilla);
u = g.muestra(n);

fprintf('Generador Park-Miller  a = %d,  m = %d,  semilla = %d\n', g.a, g.m, semilla);
fprintf('Primeros 5 números: %s\n\n', mat2str(u(1:5)', 6));

% Verificación clásica de Park-Miller: con X0 = 1, X(10000) debe ser 1043618065
gv = GeneradorLCG(1);
for i = 1:10000, gv.siguienteEntero(); end
fprintf('Verificación Park-Miller X(10000) = %d (esperado 1043618065) -> %s\n\n', ...
        gv.estado, string(gv.estado == 1043618065));

R = pruebas_aleatoriedad(u, alfa);
etiquetas = {'NO PASA', 'PASA'};
txt = @(b) etiquetas{double(b) + 1};
fprintf('%-18s %14s %14s   %s\n', 'Prueba', 'Estadístico', 'Crítico/Lím.', 'Resultado');
fprintf('%-18s %14.5f %6.4f-%6.4f   %s\n', 'Medias', R.medias.estadistico, R.medias.lim_inf, R.medias.lim_sup, txt(R.medias.pasa));
fprintf('%-18s %14.5f %6.4f-%6.4f   %s\n', 'Varianza', R.varianza.estadistico, R.varianza.lim_inf, R.varianza.lim_sup, txt(R.varianza.pasa));
fprintf('%-18s %14.4f %14.4f   %s\n', 'Chi-cuadrado', R.chi2.estadistico, R.chi2.critico, txt(R.chi2.pasa));
fprintf('%-18s %14.5f %14.5f   %s\n', 'Kolmogorov-Smirnov', R.ks.estadistico, R.ks.critico, txt(R.ks.pasa));
fprintf('%-18s %14.4f %14.4f   %s\n', 'Rachas (Z)', R.rachas.estadistico, R.rachas.critico, txt(R.rachas.pasa));
fprintf('%-18s %14.5f %14.5f   %s\n', 'Autocorrelación', R.autocorrelacion.estadistico, R.autocorrelacion.critico, txt(R.autocorrelacion.pasa));
if ~isempty(R.toolbox)
    fprintf('\nToolbox: chi2gof p = %.4f | kstest p = %.4f | runstest p = %.4f\n', ...
            R.toolbox.chi2gof_p, R.toolbox.kstest_p, R.toolbox.runstest_p);
end

%% Gráficas
figure('Name', 'Fase 1 - Generador U(0,1)', 'Color', 'w', 'Position', [100 100 1100 380]);
subplot(1,3,1);
bar((0.05:0.1:0.95), R.chi2.observadas, 1, 'FaceColor', [0.2 0.45 0.7]); hold on;
yline(R.chi2.esperada, 'r--', 'Esperado', 'LineWidth', 1.5);
title('Histograma (10 intervalos)'); xlabel('U'); ylabel('Frecuencia');

subplot(1,3,2);
plot(u(1:end-1), u(2:end), '.', 'MarkerSize', 3);
axis square; title('Dispersión U_i vs U_{i+1}'); xlabel('U_i'); ylabel('U_{i+1}');

subplot(1,3,3);
us = sort(u);
stairs(us, (1:n)'/n, 'LineWidth', 1.2); hold on;
plot([0 1], [0 1], 'r--');
title(sprintf('K-S: D = %.4f', R.ks.estadistico)); xlabel('x'); ylabel('F(x)');
legend('Empírica', 'Teórica U(0,1)', 'Location', 'northwest');

%% De U(0,1) a variables del peaje (vista previa de la Fase 2)
lambda = 450;                       % vehículos por hora
g.reiniciar(semilla);
t_entre = arrayfun(@(~) g.exponencial(3600/lambda), 1:2000);
fprintf('\nTiempo medio entre llegadas simulado: %.2f s (teórico %.2f s)\n', mean(t_entre), 3600/lambda);
figure('Name', 'Tiempos entre llegadas', 'Color', 'w');
histogram(t_entre, 40, 'Normalization', 'pdf'); hold on;
tt = linspace(0, max(t_entre), 200);
plot(tt, (lambda/3600) * exp(-(lambda/3600) * tt), 'r', 'LineWidth', 2);
title('Transformada inversa: exponencial con \lambda = 450 veh/h');
xlabel('Tiempo entre llegadas (s)'); ylabel('Densidad'); legend('Simulado', 'Teórico');
