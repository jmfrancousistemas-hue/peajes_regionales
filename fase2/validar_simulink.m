%% VALIDACIÓN CRUZADA DEL MODELO CONTINUO (Rol A)
% Compara la aproximación y frenado de un vehículo calculada de tres formas:
%   1. Simulink (aproximacion_peaje.slx, ode45 de paso variable)
%   2. ode45 en MATLAB con función de eventos
%   3. Integrador de paso fijo del motor híbrido (dt = 0.1 s)
% Si las tres curvas coinciden, el paso dt = 0.1 s es suficiente.
%
% Defensa en caliente: cambie factor_b (o la categoría) y vuelva a correr.

clear; clc; close all;
raiz = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(raiz, 'fase1'), fullfile(raiz, 'fase2'));

p = parametros_peaje();
p.factor_b = 1.0;      % <-- coeficiente que el docente puede alterar
c = 1;                 % 1 Auto, 2 Bus, 3 Camión
q = p.cat(c);
v0 = q.v0 * p.factor_v0; T = q.T * p.factor_T; a = q.a * p.factor_a; b = q.b * p.factor_b;

%% 1. Simulink
mdl = 'aproximacion_peaje';
if ~exist(fullfile(raiz, 'fase2', [mdl '.slx']), 'file')
    construir_modelo_simulink(true);
end
load_system(mdl);
in = Simulink.SimulationInput(mdl);
in = in.setVariable('v0', v0);   in = in.setVariable('T', T);
in = in.setVariable('a', a);     in = in.setVariable('b', b);
in = in.setVariable('s0', q.s0); in = in.setVariable('xObs', p.L + q.s0);
in = in.setVariable('aMax', p.aFrenadoMax);
in = in.setVariable('v_ini', v0); in = in.setVariable('tSim', 80);
out = sim(in);
tS = out.t_sim(:); xS = out.x_sim(:); vS = out.v_sim(:); aS = out.acc_sim(:);

%% 2. ode45 con eventos
[tO, yO] = aproximacion_ode45(p, c, false);

%% 3. Paso fijo del motor
x = 0; v = v0; k = 0; tE = 0; xE = 0; vE = v0;
while k < 2000
    acc = max(idm_aceleracion(v, v0, T, a, b, q.s0, p.L + q.s0 - x, v, p.delta), -p.aFrenadoMax);
    vN = max(v + acc * p.dt, 0); x = x + 0.5 * (v + vN) * p.dt; v = vN; k = k + 1;
    tE(end+1) = k * p.dt; xE(end+1) = x; vE(end+1) = v; %#ok<SAGROW>
    if tE(end) >= 80, break; end
end

%% Comparación
fprintf('%s con factor_b = %.2f (b = %.2f m/s^2)\n', q.nombre, p.factor_b, b);
fprintf('  Posición final  Simulink %.2f m | ode45 %.2f m | paso fijo %.2f m | teoría L = %g m\n', ...
        xS(end), yO(end,1), xE(end), p.L);
fprintf('  Frenado máximo  Simulink %.2f m/s^2\n', min(aS));
idx = find(vS < 0.5, 1);
if ~isempty(idx), fprintf('  Tiempo hasta v < 0.5 m/s (Simulink): %.1f s\n', tS(idx)); end

figure('Name', 'Validación cruzada del modelo continuo', 'Color', 'w', 'Position', [100 100 900 600]);
subplot(2,1,1);
plot(tS, xS, 'LineWidth', 2); hold on; plot(tO, yO(:,1), '--', 'LineWidth', 1.5);
plot(tE, xE, ':', 'LineWidth', 2); yline(p.L, 'r--', 'Taquilla');
ylabel('Posición x (m)'); grid on; legend('Simulink', 'ode45', 'Motor dt = 0.1 s', 'Location', 'southeast');
title(sprintf('Aproximación y frenado (%s, b = %.2f m/s^2)', q.nombre, b));
subplot(2,1,2);
plot(tS, vS * 3.6, 'LineWidth', 2); hold on; plot(tO, yO(:,2) * 3.6, '--', 'LineWidth', 1.5);
plot(tE, vE * 3.6, ':', 'LineWidth', 2);
ylabel('Velocidad (km/h)'); xlabel('t (s)'); grid on;
