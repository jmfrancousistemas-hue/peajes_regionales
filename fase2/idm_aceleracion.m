function acc = idm_aceleracion(v, v0, T, a, b, s0, s, dv, delta)
%IDM_ACELERACION Modelo de Conductor Inteligente (Treiber, Hennecke y Helbing, 2000).
%   Responsable: Rol A (modelado físico continuo).
%
%       dx/dt = v
%       dv/dt = a * [ 1 - (v/v0)^delta - (s*(v,dv)/s)^2 ]
%       s*(v,dv) = s0 + v*T + v*dv / (2*sqrt(a*b))
%
%   v   velocidad propia (m/s)        v0  velocidad deseada (m/s)
%   T   brecha temporal deseada (s)   a   aceleración máxima (m/s^2)
%   b   desaceleración cómoda (m/s^2) s0  distancia mínima de parada (m)
%   s   distancia libre al obstáculo o líder (m); Inf si la vía está libre
%   dv  v - v_lider (m/s), velocidad de aproximación
%
%   Interpretación para la sustentación:
%   - Vía libre (s -> Inf): el vehículo acelera hasta v0.
%   - Frente a un obstáculo detenido (dv = v): el término (s*/s)^2 crece y
%     frena; el vehículo se detiene a una distancia s0 del obstáculo.
%   - Si se baja b, el término v*dv/(2*sqrt(a*b)) aumenta: el conductor
%     empieza a frenar ANTES y con desaceleración más suave.

    if isinf(s)
        acc = a * (1 - (v / v0)^delta);
        return;
    end
    s = max(s, 0.01);
    sEstrella = s0 + max(0, v*T + v*dv / (2*sqrt(a*b)));
    acc = a * (1 - (v / v0)^delta - (sEstrella / s)^2);
end
