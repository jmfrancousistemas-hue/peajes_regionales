# Simulador Híbrido de Tráfico y Peajes Regionales

> **Proyecto Final de Sistemas Distribuidos: servidor Linux con Docker.** La carpeta [`servidor_linux/`](servidor_linux/README.md) tiene el sistema web de peajes (3 taquillas manuales, carril TAG y recargas) con mensajería, monitor de rendimiento, documentos compartidos y VPN. Se abre en GitHub Codespaces: **Code → Codespaces → Create codespace on main**.

Proyecto Final de Modelos de Simulación (UNINTEP), Alternativa 1. MATLAB R2021a o posterior; Simulink para el modelo de aproximación.

## Cómo correrlo

Abra MATLAB en esta carpeta y ejecute, en orden:

| Fase | Comando | Qué hace |
| --- | --- | --- |
| 1 | `run fase1/fase1_demo.m` | Genera 10.000 U(0,1) con Park–Miller, aplica 6 pruebas y grafica |
| 2 | `run fase2/fase2_demo.m` | Corrida de 1 h, verificación con 30 réplicas contra Erlang C, gráficas y exporta `web/corrida_matlab.json` |
| 2 | `run fase2/validar_simulink.m` | Construye `aproximacion_peaje.slx` y compara Simulink, ode45 y el motor |
| 3 | `run fase3/app_simulador_peajes.m` | App con animación en tiempo real |
| Defensa | `run fase2/defensa_en_caliente.m` | Corrida base contra corrida modificada por el usuario |

Versión web: abra `web/index.html` en el navegador (no necesita internet salvo las fuentes). Para publicarla, suba la carpeta `web/` a un repositorio de GitHub y active GitHub Pages.

## Estructura

```
fase1/  GeneradorLCG.m, pruebas_aleatoriedad.m, fase1_demo.m        (Roles B y C)
fase2/  parametros_peaje.m, idm_aceleracion.m                         (Rol A)
        motor_inicializar.m, motor_paso.m, simular_peaje.m, erlang_c.m (Rol B)
        motor_resultados.m, imprimir_resumen.m, exportar_json.m        (Rol C)
        aproximacion_ode45.m, construir_modelo_simulink.m, validar_simulink.m (Rol A)
        fase2_demo.m, defensa_en_caliente.m
fase3/  app_simulador_peajes.m                                         (Rol C)
web/    index.html, motor.js (gemelo del motor MATLAB)                 (Rol C)
docs/   informe de investigación con parámetros y fuentes
```

## Escenarios

| Escenario | Llamada | λ (veh/h) | Mezcla Auto/Bus/Camión |
| --- | --- | --- | --- |
| Riofrío (por defecto) | `parametros_peaje('riofrio')` | 590 | 65 / 8 / 27 % |
| Toro | `parametros_peaje('toro')` | 300 | 60 / 5 / 35 % |

Cobro manual: 13,5 s (Cat. I), 20 s (Cat. II), 30 s (Cat. III a V), CV 0,3. TAG: 4 s, 35 % de los vehículos. Tarifas INVÍAS 2026: 10.900 / 11.800 / 25.000 COP (Cat. III a V agrupadas). La app de MATLAB y la web tienen un selector de escenario.

## Notas

- Todos los parámetros que el usuario puede cambiar están en `fase2/parametros_peaje.m`.
- `p.modoFisico = false` apaga la dinámica continua; sirve para verificar el motor discreto contra M/G/c.
- Probado en MATLAB R2025b. El motor de la web (`web/motor.js`) es una traducción línea por línea del motor MATLAB.
- Con la misma semilla, MATLAB y la web consumen los números aleatorios en el mismo orden. Diferencias en el último decimal de `exp`, `log` o `^` entre lenguajes pueden, en casos raros, cambiar un evento; los promedios no cambian.
