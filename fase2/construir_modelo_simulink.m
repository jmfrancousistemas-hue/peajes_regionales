function mdl = construir_modelo_simulink(guardar)
%CONSTRUIR_MODELO_SIMULINK Genera por código el modelo Simulink de aproximación.
%   Responsable: Rol A. Construye 'aproximacion_peaje.slx':
%
%     [Constantes v0,T,a,b,s0,xObs,aMax] --> [MATLAB Function: IDM] --acc-->
%        [Integrador v (saturado en 0)] --v--> [Integrador x] --x--+
%              ^------------------- realimentación x, v -----------+
%
%   Los parámetros son variables del workspace base (v0, T, a, b, s0, xObs,
%   aMax, v_ini, tSim); validar_simulink.m los fija con Simulink.SimulationInput
%   y setVariable, que es lo que permite cambiarlos en vivo en la sustentación.
%
%   Ejecutar:  construir_modelo_simulink();  open_system('aproximacion_peaje')

    if nargin < 1, guardar = true; end
    mdl = 'aproximacion_peaje';
    if bdIsLoaded(mdl), close_system(mdl, 0); end
    new_system(mdl);
    open_system(mdl);

    % Valores por defecto en el workspace base (Auto)
    p = parametros_peaje(); q = p.cat(1);
    asignar('v0', q.v0); asignar('T', q.T); asignar('a', q.a); asignar('b', q.b);
    asignar('s0', q.s0); asignar('xObs', p.L + q.s0); asignar('aMax', p.aFrenadoMax);
    asignar('v_ini', q.v0); asignar('tSim', 60);

    % ---- Bloque MATLAB Function con el IDM ----
    blkIDM = [mdl '/IDM'];
    add_block('simulink/User-Defined Functions/MATLAB Function', blkIDM, ...
              'Position', [330 120 470 330]);
    codigo = sprintf([ ...
        'function acc = idm_frenado(x, v, v0, T, a, b, s0, xObs, aMax)\n' ...
        '%% Modelo de Conductor Inteligente frente a un obstáculo detenido en xObs\n' ...
        's = max(xObs - x, 0.01);\n' ...
        'sEst = s0 + max(0, v*T + v*v/(2*sqrt(a*b)));\n' ...
        'acc = a*(1 - (v/v0)^4 - (sEst/s)^2);\n' ...
        'acc = max(acc, -aMax);\n']);
    raizSF = sfroot;
    diagrama = raizSF.find('-isa', 'Simulink.BlockDiagram', 'Name', mdl);
    grafico = diagrama.find('-isa', 'Stateflow.EMChart', 'Path', blkIDM);
    grafico.Script = codigo;

    % ---- Constantes (entradas 3..9 del IDM) ----
    nombres = {'v0', 'T', 'a', 'b', 's0', 'xObs', 'aMax'};
    for i = 1:numel(nombres)
        y = 60 + 45 * i;
        add_block('simulink/Sources/Constant', [mdl '/C_' nombres{i}], ...
                  'Value', nombres{i}, 'Position', [200 y 260 y+25]);
        add_line(mdl, ['C_' nombres{i} '/1'], sprintf('IDM/%d', i + 2), 'autorouting', 'on');
    end

    % ---- Integradores ----
    add_block('simulink/Continuous/Integrator', [mdl '/Int_v'], ...
              'InitialCondition', 'v_ini', 'LimitOutput', 'on', ...
              'LowerSaturationLimit', '0', 'UpperSaturationLimit', 'inf', ...
              'Position', [540 210 580 250]);
    add_block('simulink/Continuous/Integrator', [mdl '/Int_x'], ...
              'InitialCondition', '0', 'Position', [650 210 690 250]);
    add_line(mdl, 'IDM/1', 'Int_v/1', 'autorouting', 'on');
    add_line(mdl, 'Int_v/1', 'Int_x/1', 'autorouting', 'on');
    add_line(mdl, 'Int_x/1', 'IDM/1', 'autorouting', 'on');
    add_line(mdl, 'Int_v/1', 'IDM/2', 'autorouting', 'on');

    % ---- Registro de señales ----
    add_block('simulink/Sinks/To Workspace', [mdl '/Log_x'], 'VariableName', 'x_sim', ...
              'SaveFormat', 'Array', 'Position', [780 140 850 170]);
    add_block('simulink/Sinks/To Workspace', [mdl '/Log_v'], 'VariableName', 'v_sim', ...
              'SaveFormat', 'Array', 'Position', [780 280 850 310]);
    add_block('simulink/Sinks/To Workspace', [mdl '/Log_acc'], 'VariableName', 'acc_sim', ...
              'SaveFormat', 'Array', 'Position', [780 360 850 390]);
    add_block('simulink/Sources/Clock', [mdl '/Reloj'], 'Position', [650 420 680 450]);
    add_block('simulink/Sinks/To Workspace', [mdl '/Log_t'], 'VariableName', 't_sim', ...
              'SaveFormat', 'Array', 'Position', [780 420 850 450]);
    add_line(mdl, 'Int_x/1', 'Log_x/1', 'autorouting', 'on');
    add_line(mdl, 'Int_v/1', 'Log_v/1', 'autorouting', 'on');
    add_line(mdl, 'IDM/1', 'Log_acc/1', 'autorouting', 'on');
    add_line(mdl, 'Reloj/1', 'Log_t/1', 'autorouting', 'on');

    % ---- Visualización ----
    add_block('simulink/Sinks/Scope', [mdl '/Scope_v'], 'Position', [780 210 810 240]);
    add_line(mdl, 'Int_v/1', 'Scope_v/1', 'autorouting', 'on');

    % ---- Solver ----
    set_param(mdl, 'Solver', 'ode45', 'StopTime', 'tSim', 'MaxStep', '0.05', ...
              'RelTol', '1e-6', 'ReturnWorkspaceOutputs', 'on');
    try
        Simulink.BlockDiagram.arrangeSystem(mdl);
    catch
        % versiones antiguas sin arrangeSystem: se conserva la posición manual
    end
    if guardar
        save_system(mdl, fullfile(fileparts(mfilename('fullpath')), [mdl '.slx']));
    end
    fprintf('Modelo %s construido.\n', mdl);
end

function asignar(nombre, valor)
    assignin('base', nombre, valor);
end
