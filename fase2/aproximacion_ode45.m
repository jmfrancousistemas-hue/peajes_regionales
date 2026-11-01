function [t, y, te] = aproximacion_ode45(p, c, graficar)
%APROXIMACION_ODE45 Frenado de aproximación de UN vehículo con ode45 y eventos.
%   Responsable: Rol A. Sirve para contrastar el integrador de paso fijo del
%   motor y el modelo de Simulink con un integrador de paso variable.
%
%   Estado y = [x; v]
%       dx/dt = v
%       dv/dt = IDM(v, s = L + s0 - x, dv = v)     (obstáculo detenido)
%   Evento terminal: v cae por debajo de 0.05 m/s (vehículo detenido).
%
%   Resultado analítico para el tablero: el vehículo se detiene a una
%   distancia s0 del obstáculo, es decir en x = L (la taquilla).
%
%   Ejemplo:  aproximacion_ode45(parametros_peaje(), 1, true)

    if nargin < 1 || isempty(p), p = parametros_peaje(); end
    if nargin < 2, c = 1; end
    if nargin < 3, graficar = true; end
    q = p.cat(c);
    v0 = q.v0 * p.factor_v0; T = q.T * p.factor_T;
    a = q.a * p.factor_a;    b = q.b * p.factor_b;

    f = @(t, y) [ y(2);
                  max(idm_aceleracion(max(y(2),0), v0, T, a, b, q.s0, p.L + q.s0 - y(1), max(y(2),0), p.delta), ...
                      -p.aFrenadoMax) ];
    opciones = odeset('Events', @detenido, 'RelTol', 1e-8, 'AbsTol', 1e-8, 'MaxStep', 0.5);
    [t, y, te] = ode45(f, [0 300], [0; v0], opciones);

    if graficar
        figure('Name', 'Aproximación con ode45', 'Color', 'w');
        subplot(2,1,1); plot(t, y(:,1), 'LineWidth', 1.5); yline(p.L, 'r--', 'Taquilla');
        ylabel('x (m)'); grid on;
        title(sprintf('%s: se detiene en x = %.2f m a los %.1f s', q.nombre, y(end,1), t(end)));
        subplot(2,1,2); plot(t, y(:,2) * 3.6, 'LineWidth', 1.5);
        ylabel('v (km/h)'); xlabel('t (s)'); grid on;
    end

    function [valor, terminal, direccion] = detenido(~, y)
        valor = y(2) - 0.05;
        terminal = 1;
        direccion = -1;
    end
end
