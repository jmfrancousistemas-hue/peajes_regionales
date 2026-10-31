function p = parametros_peaje(escenario)
%PARAMETROS_PEAJE Parámetros del simulador híbrido por escenario.
%   p = parametros_peaje()            escenario 'riofrio' (por defecto)
%   p = parametros_peaje('toro')      escenario Toro
%   Todo lo que el docente puede alterar en la "defensa en caliente" está
%   aquí. Ejemplo:
%       p = parametros_peaje('riofrio');
%       p.factor_b = 0.5;     % frenado más suave
%       p.semilla  = 777;     % otra semilla
%       R = simular_peaje(p);
%
%   Fuentes (ver sección "Parámetros y fuentes" del trabajo escrito):
%   - Llegadas: TPDM de datos.gov.co (ANI). lambda = TPDM / 24 h.
%       Riofrío: 13.500-15.000 veh/día -> 560-625 veh/h (se usa 590)
%       Toro:     6.500-8.000 veh/día  -> 270-333 veh/h (se usa 300)
%   - Mezcla de categorías: ANI, OETR.
%   - Cobro manual: Cat. I 12-15 s, Cat. II 18-22 s, Cat. III-V 25-35 s
%     (se usa el punto medio: 13,5 s / 20 s / 30 s). TAG: 4 s.
%   - Tarifas: PISA (Cat. I 13.400, II 17.400, III 41.000, IV 56.000, V 61.800).
%     El modelo agrupa III-V en "Camión" con la tarifa de la Cat. III.
%   - IDM: Treiber y Kesting, "Traffic Flow Dynamics" (2013).

    if nargin < 1 || isempty(escenario), escenario = 'riofrio'; end
    p.escenario = lower(char(escenario));

    % ---------------- Estocásticos (Rol B) ----------------
    p.semilla      = 12345;             % semilla del LCG Park-Miller
    switch p.escenario
        case 'riofrio'
            p.lambda = 590;                 % veh/h (TPDM 14.150 / 24 h)
            p.mezcla = [0.65 0.08 0.27];    % Auto / Bus / Camión
        case 'toro'
            p.lambda = 300;                 % veh/h (TPDM 7.250 / 24 h)
            p.mezcla = [0.60 0.05 0.35];
        otherwise
            error('Escenario desconocido: use ''riofrio'' o ''toro''.');
    end
    p.propTag      = 0.35;              % fracción con TAG (supuesto: no hay dato publicado)
    p.servManual   = 13.5;              % media del cobro manual de un auto, Cat. I (s)
    p.cvManual     = 0.30;              % coeficiente de variación del cobro manual
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
        'fServ',  {1.0,      20/13.5,  30/13.5}, ...   % Cat. II 20 s, Cat. III-V 30 s
        'tarifa', {13400,    17400,    41000});
end
