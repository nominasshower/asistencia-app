"""KPIs Calidad: calculo de los datos (SOLO LECTURA en ConnectIT). Sin dependencias externas: lo usan
generar_kpis_calidad.py (desde esta PC, por SSH) y kpis_calidad_sync.py (en ares, mysql local).
Criterios (alineados con el reporte de vaciados): piezas vaciadas = process_log Vaciado (ws 3),
sin recuperacion_log y sin defectos 76,77,83,85,86,87,88,92. Grado C = piece_status SCRAP (6)
entre esas piezas, fechado por dia de vaciado."""
import datetime as dt

# Retrabajo MENOR = defecto que se arregla con lijado/resane/pulido (propuesta, por confirmar con calidad).
# Todo defecto que no este aqui cuenta como MAYOR (rehacer gelcoat, mal vaciada, quebrados, etc.). Ajustar aqui.
MENOR = ('despostillado', 'espesor delgado', 'espesor grueso', 'pando', 'mal resanada',
         'marca de dedo', 'marca de molde', 'marcas de molde', 'manchas de molde', 'molde rayado')
EXCL = "76,77,83,85,86,87,88,92"


# Misma clasificacion de motivos que CalidadController::clasificarMotivo (Reporte de Calidad en ares); la primera que
# haga match gana, y lo que no cae en ninguna es 'produccion'.
CATEGORIAS = (
    ('recuperacion', ('recupera', 'no encontrada', 'no utilizada')),
    ('redimension', ('redimen', 'offset')),
    ('horno', ('rechazo de gelcoat',)),
    ('excedentes', ('stock de inventario',)),
    ('inventario', ('inventario',)),
    ('sistema', ('etiqueta', 'duplicad', 'molde vacio', 'generaci', 'cambio de orden', 'mal asignado',
                 'modelo antiguo', 'sobrante', 'acumulado', 'retrabajo', 'pruebas de sistema')),
    ('muestras', ('muestra', 'prueba')),
)


def clasificar_motivo(motivo):
    m = (motivo or '').lower()
    for cat, kws in CATEGORIAS:
        if any(w in m for w in kws):
            return cat
    return 'produccion'


def calcular(run, dias=70):
    """run(sql) -> lista de filas (listas de str). Devuelve el dict listo para JSON."""
    desde = (dt.date.today() - dt.timedelta(days=dias)).strftime('%Y-%m-%d')
    base = f"""
DROP TEMPORARY TABLE IF EXISTS v;
CREATE TEMPORARY TABLE v AS SELECT pl.sku, MIN(DATE(pl.created_at)) d FROM process_log pl
 WHERE pl.workstation_id=3 AND pl.created_at>='{desde}' GROUP BY pl.sku;
DROP TEMPORARY TABLE IF EXISTS vn;
CREATE TEMPORARY TABLE vn AS SELECT v.sku, v.d, p.id piece_id, p.piece_status_id, pt.name tipo
 FROM v JOIN piece p ON p.sku=v.sku JOIN product pr ON pr.id=p.product_id JOIN product_type pt ON pt.id=pr.product_type_id
 WHERE v.sku NOT IN (SELECT sku FROM recuperacion_log)
   AND p.id NOT IN (SELECT piece_id FROM piece_defect WHERE active=1 AND defect_id IN ({EXCL}));
"""
    if True:
        q = lambda s: run(base + s)
        prod = q("SELECT d, tipo, COUNT(*) FROM vn GROUP BY d, tipo;")
        # Grado C = pieza MANDADA a Grado C ese dia (fecha del registro 'scrap piece', como el Reporte de Calidad de
        # ConnectIT), solo categoria Produccion (sin sistema/horno/redimension/muestras/inventario/recuperacion).
        gc_rows = run(f"""SELECT DATE(MAX(scrap.created_at)), pt.name, GROUP_CONCAT(DISTINCT df.name SEPARATOR '|')
                      FROM piece p JOIN product pr ON pr.id=p.product_id JOIN product_type pt ON pt.id=pr.product_type_id
                      JOIN piece_defect scrap ON scrap.piece_id=p.id AND LOWER(scrap.details)='scrap piece'
                      LEFT JOIN defect df ON df.id=scrap.defect_id
                      WHERE scrap.created_at>='{desde}' GROUP BY p.id, pt.name;""")
        insp = q(f"SELECT DATE(created_at), COUNT(DISTINCT sku) FROM process_log WHERE workstation_id=12 AND created_at>='{desde}' GROUP BY 1;")
        # inspeccionadas ese dia con algun defecto registrado ese mismo dia
        insp_def = q(f"""SELECT DATE(pl.created_at), COUNT(DISTINCT pl.sku) FROM process_log pl JOIN piece p ON p.sku=pl.sku
                         JOIN piece_defect pd ON pd.piece_id=p.id AND pd.active=1 AND DATE(pd.created_at)=DATE(pl.created_at)
                         WHERE pl.workstation_id=12 AND pl.created_at>='{desde}' GROUP BY 1;""")
        rw = q(f"SELECT DATE(created_at), COUNT(*), SUM(release_date IS NOT NULL) FROM rework WHERE created_at>='{desde}' GROUP BY 1;")
        # defectos registrados al mismo momento en que la pieza se manda a Retrabajo (+-2 min); una fila por (retrabajo, defecto); la clasificacion menor/mayor se hace abajo por tipo de defecto
        rw_def = q(f"""SELECT DATE(r.created_at), r.id, df.name FROM rework r JOIN piece p ON p.sku=r.sku
                         JOIN piece_defect pd ON pd.piece_id=p.id AND pd.active=1
                           AND ABS(TIMESTAMPDIFF(SECOND, r.created_at, pd.created_at))<=120
                         JOIN defect df ON df.id=pd.defect_id
                         WHERE r.created_at>='{desde}' GROUP BY 1,2,3;""")
    days = {}
    def D(d): return days.setdefault(d, {'fecha': d, 'vaciadas': 0, 'pared': 0, 'piso': 0, 'otros': 0,
        'gc': 0, 'gc_pared': 0, 'gc_piso': 0, 'gc_otros': 0, 'inspeccionadas': 0, 'insp_con_defecto': 0,
        'retrabajos': 0, 'retrabajos_liberados': 0, 'retrabajo_mayor': 0, 'defectos_gc': {}, 'defectos_rw': {}})
    k = {'Pared': 'pared', 'Piso': 'piso'}
    for d, t, n in prod:
        x = D(d); n = int(n); x['vaciadas'] += n; x[k.get(t, 'otros')] += n
    for d, t, motivo in gc_rows:
        if clasificar_motivo(motivo.replace('|', ', ')) != 'produccion': continue
        x = D(d); x['gc'] += 1; x['gc_' + k.get(t, 'otros')] += 1
        for nm in motivo.split('|'):
            x['defectos_gc'][nm] = x['defectos_gc'].get(nm, 0) + 1
    for d, n in insp: D(d)['inspeccionadas'] = int(n)
    for d, n in insp_def: D(d)['insp_con_defecto'] = int(n)
    for d, n, l in rw: x = D(d); x['retrabajos'] = int(n); x['retrabajos_liberados'] = int(l or 0)
    por_rw = {}
    for d, rid, nm in rw_def:
        e = por_rw.setdefault(rid, [d, set()]); e[1].add(nm)
        x = D(d); x['defectos_rw'][nm] = x['defectos_rw'].get(nm, 0) + 1
    for rid, (d, nms) in por_rw.items():
        if not all(n.lower().startswith(MENOR) for n in nms): D(d)['retrabajo_mayor'] += 1
    out = {'generado': dt.datetime.now().strftime('%Y-%m-%d %H:%M'), 'desde': desde, 'meta_gc': 0.015,
           'dias': [days[d] for d in sorted(days)]}
    return {'generado': dt.datetime.now().strftime('%Y-%m-%d %H:%M'), 'desde': desde, 'meta_gc': 0.015,
            'dias': [days[d] for d in sorted(days)]}
