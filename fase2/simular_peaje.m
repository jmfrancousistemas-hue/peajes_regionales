function [R, S] = simular_peaje(p, alPaso)
%SIMULAR_PEAJE Corre el simulador híbrido completo.
%   R = simular_peaje()            parámetros por defecto
%   R = simular_peaje(p)           parámetros personalizados
%   R = simular_peaje(p, @f)       llama f(S) en cada paso (para animar);
%                                  f debe devolver true para seguir o false para detener
%
%   Ejemplo de "defensa en caliente":
%       p = parametros_peaje(); p.semilla = 2026; p.factor_b = 0.6;
%       R = simular_peaje(p); imprimir_resumen(R)

    if nargin < 1 || isempty(p), p = parametros_peaje(); end
    if nargin < 2, alPaso = []; end
    S = motor_inicializar(p);
    nPasos = round(p.tFin / p.dt);
    for k = 1:nPasos
        S = motor_paso(S);
        if ~isempty(alPaso)
            seguir = alPaso(S);
            if isequal(seguir, false), break; end
        end
    end
    R = motor_resultados(S);
end
