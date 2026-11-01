classdef GeneradorLCG < handle
%GENERADORLCG Generador congruencial lineal multiplicativo (Park-Miller).
%   Proyecto Final - Modelos de Simulación (UNINTEP)
%   Alternativa 1: Simulador Híbrido de Tráfico y Peajes Regionales
%   Responsable: Rol B (motor estocástico)
%
%   Recurrencia:   X(n+1) = mod(a * X(n), m)
%                  U(n+1) = X(n+1) / m        -> U ~ U(0,1)
%   Parámetros "estándar mínimo" de Park y Miller (1988):
%       a = 16807 (7^5),  m = 2^31 - 1 = 2147483647 (primo),  c = 0
%   Periodo completo: m - 1 = 2.147.483.646 números.
%
%   ¿Por qué no hay desbordamiento en MATLAB?
%   a*X < 16807 * 2^31 ≈ 3.6e13 < 2^53 ≈ 9.0e15, así que el producto se
%   representa EXACTO en double y mod() devuelve el entero correcto.
%
%   Uso:
%       g = GeneradorLCG(12345);
%       u = g.uniforme();          % un número en (0,1)
%       U = g.muestra(1000);       % vector columna de 1000 números
%       e = g.exponencial(8);      % tiempo entre llegadas, media 8 s
%
%   El mismo algoritmo está en la aplicación web (motor.js), por eso una
%   misma semilla produce la misma secuencia en MATLAB y en el navegador.

    properties (Constant)
        a = 16807;
        m = 2147483647;
    end

    properties (SetAccess = private)
        semilla   % semilla inicial X0
        estado    % último entero generado X(n)
        contador  % cuántos U(0,1) se han consumido
    end

    methods
        function obj = GeneradorLCG(semilla)
            if nargin < 1, semilla = 12345; end
            obj.reiniciar(semilla);
        end

        function reiniciar(obj, semilla)
            if nargin < 2, semilla = obj.semilla; end
            semilla = floor(double(semilla));
            % La semilla debe estar en 1..m-1 (0 dejaría al generador en 0 para siempre)
            semilla = mod(semilla, obj.m);
            if semilla == 0, semilla = 1; end
            obj.semilla = semilla;
            obj.estado = semilla;
            obj.contador = 0;
        end

        function x = siguienteEntero(obj)
            obj.estado = mod(obj.a * obj.estado, obj.m);
            obj.contador = obj.contador + 1;
            x = obj.estado;
        end

        function u = uniforme(obj)
            % Nunca devuelve 0 ni 1 porque X está en 1..m-1
            u = obj.siguienteEntero() / obj.m;
        end

        function U = muestra(obj, n)
            U = zeros(n, 1);
            for i = 1:n
                U(i) = obj.uniforme();
            end
        end

        % ---------- Variables aleatorias por transformada inversa ----------
        function t = exponencial(obj, media)
            % F(t) = 1 - exp(-t/media)  =>  t = -media*ln(1-U); como 1-U ~ U,
            % se usa -media*ln(U). Tiempos entre llegadas de un proceso de Poisson.
            t = -media * log(obj.uniforme());
        end

        function k = discreta(obj, probabilidades)
            % Devuelve el índice k con probabilidad p(k) (categoría vehicular)
            u = obj.uniforme();
            acum = cumsum(probabilidades(:)') / sum(probabilidades);
            k = find(u <= acum, 1, 'first');
            if isempty(k), k = numel(probabilidades); end
        end

        function b = bernoulli(obj, p)
            % true con probabilidad p (¿el vehículo tiene TAG?)
            b = obj.uniforme() < p;
        end

        function z = normal(obj)
            % Box-Muller: consume dos uniformes y devuelve una N(0,1)
            u1 = obj.uniforme();
            u2 = obj.uniforme();
            z = sqrt(-2 * log(u1)) * cos(2 * pi * u2);
        end

        function s = lognormal(obj, media, cv)
            % Lognormal con media y coeficiente de variación dados
            % (tiempo de cobro en taquilla: siempre positivo y sesgado a la derecha)
            s2 = log(1 + cv^2);
            mu = log(media) - s2 / 2;
            s = exp(mu + sqrt(s2) * obj.normal());
        end
    end
end
