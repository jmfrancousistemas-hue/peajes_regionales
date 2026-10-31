function exportar_json(R, archivo)
%EXPORTAR_JSON Guarda el resumen de una corrida para compararla en la app web.
%   exportar_json(R, 'corrida_matlab.json')
%   En la aplicación web: botón "Cargar corrida de MATLAB".
%   Responsable: Rol C (ingeniería de datos).

    J.origen = 'MATLAB';
    J.version = version();
    J.parametros = rmfield(R.p, 'cat');
    J.categorias = R.p.cat;
    J.resumen = struct('generados', R.generados, 'atendidos', R.atendidos, ...
        'recaudo', R.recaudo, 'maxRepresados', R.maxRepresados, ...
        'utilizacion', R.utilizacion, 'LqPorCarril', R.LqPorCarril, ...
        'tLibre', R.tLibre, 'tAvance', R.tAvance, ...
        'manual', resumirGrupo(R.manual), 'tag', resumirGrupo(R.tagGrupo));
    J.serie = struct('t', R.serie.t', 'cola', R.serie.cola, 'velMedia', R.serie.velMedia');
    texto = jsonencode(J);
    fid = fopen(archivo, 'w');
    fwrite(fid, texto, 'char');
    fclose(fid);
    fprintf('Corrida exportada a %s\n', archivo);
end

function g = resumirGrupo(G)
    if G.c == 0 || isempty(G.teoria)
        g = struct('c', G.c); return;
    end
    g = struct('c', G.c, 'n', G.n, 'Wq_sim', G.Wq_sim, 'Lq_sim', G.Lq_sim, ...
        'rho_sim', G.rho_sim, 'Wq_teo', G.teoria.Wq, 'Lq_teo', G.teoria.Lq, ...
        'rho_teo', G.teoria.rho, 'Wq_corr', G.teoriaCorregida.Wq);
end
