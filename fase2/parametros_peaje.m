function p = parametros_peaje()
%PARAMETROS_PEAJE Parámetros por defecto del simulador híbrido.
%   Todo lo que el docente puede alterar en la "defensa en caliente" está
%   aquí. Ejemplo:
%       p = parametros_peaje();
%       p.factor_b = 0.5;     % frenado más suave
%       p.semilla  = 777;     % otra semilla
%       R = simular_peaje(p);
%
%   Fuentes de los valores (ver informe de investigación):
%   - IDM: Treiber y Kesting, "Traffic Flow Dynamics" (2013).
%   - Tiempos de cobro manual ~20 s y TAG ~4 s: estudios de campo de peajes.
%   - Tarifas: peajes INVÍAS Riofrío y Toro (Vía Panorama, Roldanillo),
%     Resolución INVÍAS enero 2024 (Cat. I subió a 10.900 en ago-2024). Verificar la resolución vigente antes de sustentar.

    % ---------------- Estocásticos (Rol B) ----------------
    p.semilla      = 12345;             % semilla del LCG Park-Miller
    p.lambda       = 450;               % tasa de arribo total (veh/h), proceso de Poisson
    p.mezcla       = [0.70 0.10 0.20];  % proporción Auto / Bus / Camión
    p.propTag      = 0.35;              % fracción de vehículos con TAG (pago electrónico)
    p.servManual   = 20;                % media del cobro manual de un auto (s)
    p.cvManual     = 0.40;              % coeficiente de variación del cobro manual
    p.servTag      = 4;                 % lectura del TAG y apertura de talanquera (s)
    p.cvTag        = 0.25;

    % ---------------- Infraestructura ----------------
    p.carrilesManuales = 3;
    p.carrilesTag      = 1;
    p.L       = 600;    % longitud del tramo de aproximación; la taquilla está en x = L (m)
    p.xSalida = 750;    % el vehículo sale del modelo en este punto (m)

    % ---------------- Físicos (Rol A) ----------------
    % Factores multiplicativos sobre los parámetros IDM de cada categoría
    p.factor_v0 = 1.0;  % velocidad deseada
    p.factor_T  = 1.0;  % brecha temporal / tiempo de reacción
    p.factor_a  = 1.0;  % aceleración máxima
    p.factor_b  = 1.0;  % desaceleración cómoda
    p.delta     = 4;    % exponente de aceleración del IDM
    p.aFrenadoMax = 9;  % límite físico de frenado (m/s^2, ~0.9 g)

    % ---------------- Numéricos ----------------
    p.dt       = 0.1;   % paso de integración (s)
    p.tFin     = 3600;  % horizonte de simulación (s)
    p.muestreo = 1;     % cada cuántos segundos se guardan las series
    p.modoFisico = true; % false = modo discreto puro (sin dinámica continua),
                         % sirve para verificar el motor contra Erlang C

    % ---------------- Categorías vehiculares ----------------
    % v0 (m/s), T (s), a (m/s^2), b (m/s^2), s0 (m), largo (m),
    % fServ = factor sobre el tiempo de cobro, tarifa (COP)
    p.cat = struct( ...
        'nombre', {'Auto',   'Bus',    'Camión'}, ...
        'v0',     {80/3.6,   70/3.6,   60/3.6}, ...
        'T',      {1.5,      1.8,      2.0}, ...
        'a',      {1.0,      0.7,      0.5}, ...
        'b',      {1.5,      1.5,      1.2}, ...
        's0',     {2.0,      3.0,      3.0}, ...
        'largo',  {4.5,      12.0,     16.0}, ...
        'fServ',  {1.0,      1.3,      1.5}, ...
        'tarifa', {10400,    11200,    24100});
end
