function imprimir_resumen(R)
%IMPRIMIR_RESUMEN Muestra en consola los indicadores y la comparación con la teoría.
    p = R.p;
    fprintf('\n=========== RESUMEN DE LA CORRIDA ===========\n');
    fprintf('Escenario: %s\n', p.escenario);
    fprintf('Semilla %d | lambda = %g veh/h | %d manuales + %d TAG | modo físico: %d\n', ...
            p.semilla, p.lambda, p.carrilesManuales, p.carrilesTag, p.modoFisico);
    fprintf('Factores IDM: v0 %.2f  T %.2f  a %.2f  b %.2f\n', p.factor_v0, p.factor_T, p.factor_a, p.factor_b);
    fprintf('Tiempo simulado: %.0f s | generados %d | atendidos %d | en sistema al final %d\n', ...
            R.tSimulado, R.generados, R.atendidos, R.enSistemaFinal);
    fprintf('Recaudo: $%s COP | máx. represados en la entrada: %d\n', ...
            num2str(R.recaudo, '%.0f'), R.maxRepresados);
    fprintf('Recorrido libre por categoría (s): %s | avance a taquilla (s): %s\n', ...
            mat2str(R.tLibre, 3), mat2str(R.tAvance, 3));
    fprintf('Utilización por taquilla: %s\n', mat2str(R.utilizacion, 3));
    linea('Manual', R.manual);
    linea('TAG', R.tagGrupo);
end

function linea(nombre, G)
    if G.c == 0 || isempty(G.teoria), return; end
    fprintf('\n[%s] c = %d | n = %d\n', nombre, G.c, G.n);
    fprintf('   rho  simulada %.3f | teórica lambda*E[S]/c %.3f\n', G.rho_sim, G.teoria.rho);
    fprintf('   Wq   simulada %.1f s (IC95 ±%.1f) | M/G/c %.1f s | M/G/c con avance %.1f s\n', ...
            G.Wq_sim, G.Wq_ic95, G.teoria.Wq, G.teoriaCorregida.Wq);
    fprintf('   Lq   simulada %.2f veh | M/G/c %.2f | M/G/c con avance %.2f\n', ...
            G.Lq_sim, G.teoria.Lq, G.teoriaCorregida.Lq);
end
