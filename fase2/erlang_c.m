function Q = erlang_c(lambda, ES, c, cs2)
%ERLANG_C Medidas analíticas de una cola M/M/c y aproximación M/G/c.
%   Q = erlang_c(lambda, ES, c)        lambda (veh/s), ES tiempo medio de servicio (s)
%   Q = erlang_c(lambda, ES, c, cs2)   cs2 = coef. de variación^2 del servicio
%
%   Sirve para VALIDAR el motor: la parte de colas del simulador debe dar
%   valores cercanos a estos (con diferencias explicables por la elección
%   de carril, la aproximación física y la duración finita de la corrida).
%
%   Erlang C con recursión estable de Erlang B:
%       A = lambda*ES (carga ofrecida),  rho = A/c
%       B(0) = 1,  B(k) = A*B(k-1) / (k + A*B(k-1))
%       C = c*B / (c - A*(1 - B))          probabilidad de esperar
%       Wq(M/M/c) = C / (c*mu - lambda),   Lq = lambda*Wq
%   Allen-Cunneen para servicio general (M/G/c):
%       Wq(M/G/c) ≈ Wq(M/M/c) * (1 + cs2)/2

    if nargin < 4, cs2 = 1; end
    mu = 1 / ES;
    A = lambda * ES;
    rho = A / c;
    Q.lambda = lambda; Q.ES = ES; Q.c = c; Q.rho = rho; Q.A = A;
    if rho >= 1
        Q.estable = false;
        Q.Pespera = 1; Q.Wq_MMc = inf; Q.Lq_MMc = inf; Q.Wq = inf; Q.Lq = inf;
        return;
    end
    B = 1;
    for k = 1:c
        B = A * B / (k + A * B);
    end
    C = c * B / (c - A * (1 - B));
    Q.estable = true;
    Q.Pespera = C;
    Q.Wq_MMc = C / (c * mu - lambda);
    Q.Lq_MMc = lambda * Q.Wq_MMc;
    Q.Wq = Q.Wq_MMc * (1 + cs2) / 2;   % M/G/c (Allen-Cunneen)
    Q.Lq = lambda * Q.Wq;
    Q.W  = Q.Wq + ES;
end
