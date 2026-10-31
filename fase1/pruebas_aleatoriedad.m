function R = pruebas_aleatoriedad(u, alfa, k)
%PRUEBAS_ALEATORIEDAD Batería de pruebas estadísticas para U(0,1).
%   R = pruebas_aleatoriedad(u)            alfa = 0.05, k = 10 intervalos
%   R = pruebas_aleatoriedad(u, alfa, k)
%
%   Responsable: Rol C (auditoría estadística de entrada) con apoyo del Rol B.
%   Implementadas "a mano" para no depender de toolboxes. Si existe la
%   Statistics and Machine Learning Toolbox, al final se comparan con
%   chi2gof, kstest y runstest.
%
%   Pruebas:
%     1. Medias           H0: E[U] = 1/2
%     2. Varianza         H0: Var[U] = 1/12
%     3. Chi-cuadrado     H0: las frecuencias por intervalo son uniformes
%     4. Kolmogorov-Smirnov  H0: F empírica = F(x) = x
%     5. Rachas arriba/abajo H0: los números son independientes
%     6. Autocorrelación (retardo 1)  H0: rho = 0

    if nargin < 2 || isempty(alfa), alfa = 0.05; end
    if nargin < 3 || isempty(k), k = 10; end
    u = u(:);
    n = numel(u);
    z = norminv_local(1 - alfa/2);

    % 1. Medias
    media = mean(u);
    li = 0.5 - z / sqrt(12*n);
    ls = 0.5 + z / sqrt(12*n);
    R.medias = struct('estadistico', media, 'lim_inf', li, 'lim_sup', ls, ...
                      'pasa', media >= li && media <= ls);

    % 2. Varianza (aprox. normal de chi-cuadrado para n grande)
    v = var(u);
    gl = n - 1;
    chiInf = gl * (1 - 2/(9*gl) - z*sqrt(2/(9*gl)))^3;  % Wilson-Hilferty
    chiSup = gl * (1 - 2/(9*gl) + z*sqrt(2/(9*gl)))^3;
    li = chiInf / (12*gl);
    ls = chiSup / (12*gl);
    R.varianza = struct('estadistico', v, 'lim_inf', li, 'lim_sup', ls, ...
                        'pasa', v >= li && v <= ls);

    % 3. Chi-cuadrado de bondad de ajuste
    bordes = linspace(0, 1, k+1);
    O = histcounts_local(u, bordes);
    E = n / k;
    chi2 = sum((O - E).^2 / E);
    critico = chi2inv_local(1 - alfa, k - 1);
    R.chi2 = struct('estadistico', chi2, 'critico', critico, ...
                    'observadas', O, 'esperada', E, 'pasa', chi2 < critico);

    % 4. Kolmogorov-Smirnov
    us = sort(u);
    i = (1:n)';
    Dmas = max(i/n - us);
    Dmenos = max(us - (i-1)/n);
    D = max(Dmas, Dmenos);
    critico = sqrt(-0.5 * log(alfa/2)) / sqrt(n);   % aproximación asintótica
    R.ks = struct('estadistico', D, 'critico', critico, 'pasa', D < critico);

    % 5. Rachas arriba y abajo
    s = sign(diff(u));
    s(s == 0) = 1;
    rachas = 1 + sum(s(2:end) ~= s(1:end-1));
    mu = (2*n - 1) / 3;
    sigma = sqrt((16*n - 29) / 90);
    Z = (rachas - mu) / sigma;
    R.rachas = struct('rachas', rachas, 'esperadas', mu, 'estadistico', Z, ...
                      'critico', z, 'pasa', abs(Z) < z);

    % 6. Autocorrelación de retardo 1
    um = u - mean(u);
    rho = sum(um(1:end-1) .* um(2:end)) / sum(um.^2);
    critico = z / sqrt(n);
    R.autocorrelacion = struct('estadistico', rho, 'critico', critico, ...
                               'pasa', abs(rho) < critico);

    R.n = n;
    R.alfa = alfa;
    R.todas_pasan = R.medias.pasa && R.varianza.pasa && R.chi2.pasa && ...
                    R.ks.pasa && R.rachas.pasa && R.autocorrelacion.pasa;

    % Comparación opcional con la toolbox de estadística
    R.toolbox = [];
    if exist('chi2gof', 'file') == 2 && exist('kstest', 'file') == 2
        try
            [hc, pc] = chi2gof(u, 'Edges', bordes, 'Expected', E*ones(1,k), 'Alpha', alfa);
            [hk, pk] = kstest(u, 'CDF', makedist('Uniform', 'Lower', 0, 'Upper', 1), 'Alpha', alfa);
            [hr, pr] = runstest(u, 0.5, 'Alpha', alfa);   % rachas sobre/bajo la mediana
            R.toolbox = struct('chi2gof_h', hc, 'chi2gof_p', pc, ...
                               'kstest_h', hk, 'kstest_p', pk, ...
                               'runstest_h', hr, 'runstest_p', pr);
        catch
            R.toolbox = [];
        end
    end
end

% ---------------- Funciones auxiliares sin toolbox ----------------
function O = histcounts_local(u, bordes)
    k = numel(bordes) - 1;
    idx = min(floor(u * k) + 1, k);
    O = accumarray(idx, 1, [k 1])';
end

function z = norminv_local(p)
    % Inversa de la normal estándar usando erfinv (MATLAB base)
    z = sqrt(2) * erfinv(2*p - 1);
end

function x = chi2inv_local(p, gl)
    % Percentil de chi-cuadrado: usa gammaincinv (MATLAB base)
    x = 2 * gammaincinv(p, gl/2);
end
