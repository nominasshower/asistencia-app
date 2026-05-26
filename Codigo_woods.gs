// ═══════════════════════════════════════════════════════════════════════════
// WOODS — Sistema de Producción Torres 1000
// Código.gs  — Google Apps Script completo y corregido
// SHEET_ID: 1Trjc5lNTRhiBkDqbDdguZ-GL15scwawjFwUAlMWlX18
// ═══════════════════════════════════════════════════════════════════════════

var SHEET_ID = '1Trjc5lNTRhiBkDqbDdguZ-GL15scwawjFwUAlMWlX18';

// ── Utilidades ────────────────────────────────────────────────────────────

function respJSON(data) {
  return ContentService
    .createTextOutput(JSON.stringify({ ok: true, data: data }))
    .setMimeType(ContentService.MimeType.JSON);
}

function respERR(msg) {
  return ContentService
    .createTextOutput(JSON.stringify({ ok: false, error: msg }))
    .setMimeType(ContentService.MimeType.JSON);
}

function getSheet(ss, nombre) {
  var s = ss.getSheetByName(nombre);
  if (!s) { s = ss.insertSheet(nombre); }
  return s;
}

// ── doGet ─────────────────────────────────────────────────────────────────

function doGet(e) {
  var ss     = SpreadsheetApp.openById(SHEET_ID);
  var params = e.parameter || {};
  var accion = params.accion || '';

  try {
    switch (accion) {

      case 'avance':
        return respJSON(getAvance(ss, params));

      case 'catalogo':
        return respJSON(getCatalogo(ss));

      case 'materiales':
        return respJSON(getMateriales(ss));

      case 'resumen':
        return respJSON(getResumen(ss));

      case 'get_activas':
        return respJSON(getActivas(ss));

      case 'get_checks':
        return respJSON(getChecksGAS(ss, params));

      case 'inicializar':
        inicializarHojas(ss);
        return respJSON({ mensaje: 'Hojas inicializadas' });

      default:
        return respERR('Acción GET desconocida: ' + accion);
    }
  } catch (err) {
    return respERR(err.toString());
  }
}

// ── doPost ────────────────────────────────────────────────────────────────

function doPost(e) {
  var ss   = SpreadsheetApp.openById(SHEET_ID);
  var body = {};

  try {
    body = JSON.parse(e.postData.contents);
  } catch (ex) {
    try { body = e.parameter; } catch (ex2) {}
  }

  var accion = body.accion || '';

  try {
    switch (accion) {

      case 'set_etapa':
        return respJSON(setEtapa(ss, body));

      case 'set_materiales':
        return respJSON(setMateriales(ss, body));

      case 'activar_area':
        return respJSON(activarArea(ss, body));

      case 'save_checks':
        return respJSON(saveChecksGAS(ss, body));

      case 'get_checks':
        return respJSON(getChecksGAS(ss, body));

      case 'log_gab':
        return respJSON(logGab(ss, body));

      case 'limpiar_checks':
        return respJSON(limpiarChecks(ss));

      case 'inicializar':
        inicializarHojas(ss);
        return respJSON({ mensaje: 'Hojas inicializadas' });

      default:
        return respERR('Acción POST desconocida: ' + accion);
    }
  } catch (err) {
    return respERR(err.toString());
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AVANCE — etapa actual por área
// Cols: ID | TORRE | NIVEL | TIPO_DEPTO | DEPTO_NUM | AREA | ETAPA |
//       FECHA | RESPONSABLE | NOTAS | TIMESTAMP
// ═══════════════════════════════════════════════════════════════════════════

function inicializarAvance(ss) {
  var s = getSheet(ss, 'AVANCE');
  if (s.getLastRow() === 0) {
    s.appendRow(['ID','TORRE','NIVEL','TIPO_DEPTO','DEPTO_NUM','AREA',
                 'ETAPA','FECHA','RESPONSABLE','NOTAS','TIMESTAMP']);
    s.getRange(1,1,1,11).setFontWeight('bold');
  }
  return s;
}

// Retorna todas las filas de AVANCE filtradas por torre y nivel
function getAvance(ss, params) {
  var s = inicializarAvance(ss);
  var last = s.getLastRow();
  if (last < 2) return [];

  var vals = s.getRange(2, 1, last - 1, 11).getValues();
  var torre = String(params.torre || '').trim().toUpperCase();
  var nivel = String(params.nivel || '').trim();

  return vals
    .filter(function(r) {
      if (!r[0]) return false; // fila vacía
      var matchTorre = !torre || String(r[1]).trim().toUpperCase() === torre;
      var matchNivel = !nivel || String(r[2]).trim() === nivel;
      return matchTorre && matchNivel;
    })
    .map(function(r) {
      return {
        ID:          String(r[0]),
        TORRE:       String(r[1]),
        NIVEL:       r[2],            // número
        TIPO_DEPTO:  String(r[3]),
        DEPTO_NUM:   String(r[4]),
        AREA:        String(r[5]),
        ETAPA:       String(r[6]),
        FECHA:       r[7] ? Utilities.formatDate(new Date(r[7]), 'America/Monterrey', 'dd/MM/yyyy HH:mm') : '',
        RESPONSABLE: String(r[8] || ''),
        NOTAS:       String(r[9] || ''),
        TIMESTAMP:   r[10] ? String(r[10]) : ''
      };
    });
}

// Upsert de etapa: actualiza si existe, inserta si no
function setEtapa(ss, body) {
  var s = inicializarAvance(ss);

  var torre     = String(body.torre      || '').trim();
  var nivel     = String(body.nivel      || '').trim();
  var tipoDepto = String(body.tipo_depto || '').trim();
  var deptoNum  = String(body.depto_num  || '').trim();
  var area      = String(body.area       || '').trim();  // e.g. 'cocina_0'
  var etapa     = String(body.etapa      || '').trim();
  var resp      = String(body.responsable|| '').trim();
  var notas     = String(body.notas      || '').trim();

  // ID único por combinación torre+nivel+tipo+deptoNum+area
  var rowId = torre + '_' + nivel + '_' + tipoDepto + '_' + deptoNum + '_' + area;
  var now   = new Date();

  var last = s.getLastRow();
  var existingRow = -1;

  if (last > 1) {
    var ids = s.getRange(2, 1, last - 1, 1).getValues();
    for (var i = 0; i < ids.length; i++) {
      if (String(ids[i][0]).trim() === rowId) {
        existingRow = i + 2;
        break;
      }
    }
  }

  var rowData = [rowId, torre, Number(nivel), tipoDepto, deptoNum, area,
                 etapa, now, resp, notas, now.toISOString()];

  if (existingRow > -1) {
    s.getRange(existingRow, 1, 1, 11).setValues([rowData]);
    return { accion: 'actualizado', id: rowId, etapa: etapa };
  } else {
    s.appendRow(rowData);
    return { accion: 'creado', id: rowId, etapa: etapa };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RESUMEN global
// ═══════════════════════════════════════════════════════════════════════════

function getResumen(ss) {
  var s    = inicializarAvance(ss);
  var last = s.getLastRow();
  if (last < 2) return { avance_pct: 0, total_areas: 0, por_etapa: {} };

  var vals = s.getRange(2, 1, last - 1, 7).getValues();
  var etapas = ['corte','armado','ensamble','empaque','embarque','sitio','lista'];
  var porEtapa = {};
  etapas.forEach(function(e){ porEtapa[e] = 0; });
  var totalConEtapa = 0;

  vals.forEach(function(r) {
    if (!r[0]) return;
    var e = String(r[6]).toLowerCase().trim();
    if (porEtapa[e] !== undefined) { porEtapa[e]++; totalConEtapa++; }
  });

  var score = 0;
  etapas.forEach(function(e,i){ score += (porEtapa[e]||0) * (i+1); });
  var pct = totalConEtapa > 0
    ? Math.round(score / (totalConEtapa * etapas.length) * 100) : 0;

  return { avance_pct: pct, total_areas: totalConEtapa, por_etapa: porEtapa };
}

// ═══════════════════════════════════════════════════════════════════════════
// CATÁLOGO DE DEPTOS
// ═══════════════════════════════════════════════════════════════════════════

function getCatalogo(ss) {
  var s    = getSheet(ss, 'CATALOGO_DEPTOS');
  var last = s.getLastRow();
  if (last < 2) return [];
  var vals = s.getRange(2, 1, last - 1, s.getLastColumn()).getValues();
  var hdrs = s.getRange(1, 1, 1, s.getLastColumn()).getValues()[0];
  return vals.filter(function(r){ return r[0] !== ''; }).map(function(r){
    var obj = {};
    hdrs.forEach(function(h,i){ obj[h] = r[i]; });
    return obj;
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// MATERIALES
// ═══════════════════════════════════════════════════════════════════════════

function getMateriales(ss) {
  var s    = getSheet(ss, 'MATERIALES');
  var last = s.getLastRow();
  if (last < 2) return [];
  var vals = s.getRange(2, 1, last - 1, s.getLastColumn()).getValues();
  var hdrs = s.getRange(1, 1, 1, s.getLastColumn()).getValues()[0];
  return vals.filter(function(r){ return r[0] !== ''; }).map(function(r){
    var obj = {};
    hdrs.forEach(function(h,i){ obj[h] = r[i]; });
    return obj;
  });
}

function setMateriales(ss, body) {
  var s    = getSheet(ss, 'MATERIALES');
  if (s.getLastRow() === 0) {
    s.appendRow(['ID','TORRE','NIVEL','TIPO_DEPTO','DEPTO_NUM','AREA',
                 'MATERIAL','M2','TABLEROS','FECHA','TIMESTAMP']);
    s.getRange(1,1,1,11).setFontWeight('bold');
  }
  var rows = body.rows || [];
  rows.forEach(function(r){
    s.appendRow([r.id||'', body.torre||'', body.nivel||'', body.tipo_depto||'',
                 body.depto_num||'', body.area||'', r.material||'',
                 r.m2||0, r.tableros||0, new Date(), new Date().toISOString()]);
  });
  return { guardados: rows.length };
}

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVAS — áreas en producción
// ═══════════════════════════════════════════════════════════════════════════

function inicializarActivas(ss) {
  var s = getSheet(ss, 'ACTIVAS');
  if (s.getLastRow() === 0) {
    s.appendRow(['TORRE','PISO','DEPTO','AREA','ACTIVA','FECHA']);
    s.getRange(1,1,1,6).setFontWeight('bold');
  }
  return s;
}

function activarArea(ss, body) {
  var s      = inicializarActivas(ss);
  var torre  = String(body.torre  || '').trim();
  var piso   = String(body.piso   || '').trim();
  var depto  = String(body.depto  || '').trim();
  var area   = String(body.area   || '').trim();
  var activa = (body.activa === true || body.activa === 'true');

  var last = s.getLastRow();
  var existingRow = -1;
  if (last > 1) {
    var vals = s.getRange(2, 1, last - 1, 4).getValues();
    for (var i = 0; i < vals.length; i++) {
      if (String(vals[i][0]).trim() === torre &&
          String(vals[i][1]).trim() === piso  &&
          String(vals[i][2]).trim() === depto &&
          String(vals[i][3]).trim() === area) {
        existingRow = i + 2;
        break;
      }
    }
  }

  if (!activa) {
    if (existingRow > -1) s.deleteRow(existingRow);
    return { accion: 'eliminada' };
  }

  var now = new Date();
  if (existingRow > -1) {
    s.getRange(existingRow, 1, 1, 6).setValues([[torre, piso, depto, area, true, now]]);
    return { accion: 'actualizada' };
  } else {
    s.appendRow([torre, piso, depto, area, true, now]);
    return { accion: 'creada' };
  }
}

function getActivas(ss) {
  var s    = inicializarActivas(ss);
  var last = s.getLastRow();
  if (last < 2) return [];
  var vals = s.getRange(2, 1, last - 1, 5).getValues();
  return vals
    .filter(function(r){ return r[0] !== '' && r[4] === true; })
    .map(function(r){
      return { torre: String(r[0]), piso: String(r[1]),
               depto: String(r[2]), area: String(r[3]) };
    });
}

// ═══════════════════════════════════════════════════════════════════════════
// CHECKS — estado de gabinetes por área
// ═══════════════════════════════════════════════════════════════════════════

function inicializarChecks(ss) {
  var s = getSheet(ss, 'CHECKS');
  if (s.getLastRow() === 0) {
    s.appendRow(['KEY','DATA','FECHA']);
    s.getRange(1,1,1,3).setFontWeight('bold');
  }
  return s;
}

function saveChecksGAS(ss, body) {
  var s   = inicializarChecks(ss);
  var key = String(body.key || '').trim();
  var data = typeof body.data === 'object'
               ? JSON.stringify(body.data)
               : String(body.data || '');
  var now = new Date();

  var last = s.getLastRow();
  var existingRow = -1;
  if (last > 1) {
    var keys = s.getRange(2, 1, last - 1, 1).getValues();
    for (var i = 0; i < keys.length; i++) {
      if (String(keys[i][0]).trim() === key) { existingRow = i + 2; break; }
    }
  }

  if (existingRow > -1) {
    s.getRange(existingRow, 1, 1, 3).setValues([[key, data, now]]);
  } else {
    s.appendRow([key, data, now]);
  }
  return { guardado: true, key: key };
}

function getChecksGAS(ss, params) {
  var s   = inicializarChecks(ss);
  var key = String(params.key || '').trim();
  var last = s.getLastRow();
  if (last < 2) return null;

  var vals = s.getRange(2, 1, last - 1, 2).getValues();
  for (var i = 0; i < vals.length; i++) {
    if (String(vals[i][0]).trim() === key) {
      try { return JSON.parse(vals[i][1]); } catch(e){ return vals[i][1]; }
    }
  }
  return null;
}

function limpiarChecks(ss) {
  var s = inicializarChecks(ss);
  var last = s.getLastRow();
  if (last > 1) s.deleteRows(2, last - 1);
  return { limpiado: true };
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORIAL — log de movimientos de gabinetes
// ═══════════════════════════════════════════════════════════════════════════

function inicializarHistorial(ss) {
  var s = getSheet(ss, 'HISTORIAL');
  if (s.getLastRow() === 0) {
    s.appendRow(['TIMESTAMP','TORRE','PISO','DEPTO','AREA',
                 'GAB_ID','GAB_NOMBRE','ETAPA','OPERADOR']);
    s.getRange(1,1,1,9).setFontWeight('bold');
  }
  return s;
}

function logGab(ss, body) {
  var s = inicializarHistorial(ss);
  s.appendRow([
    new Date().toISOString(),
    String(body.torre       || ''),
    String(body.piso        || ''),
    String(body.depto       || ''),
    String(body.area        || ''),
    String(body.gab_id      || ''),
    String(body.gab_nombre  || ''),
    String(body.etapa       || ''),
    String(body.operador    || '')
  ]);
  return { logged: true };
}

// ═══════════════════════════════════════════════════════════════════════════
// INICIALIZAR todas las hojas
// ═══════════════════════════════════════════════════════════════════════════

function inicializarHojas(ss) {
  inicializarAvance(ss);
  inicializarActivas(ss);
  inicializarChecks(ss);
  inicializarHistorial(ss);
  getSheet(ss, 'CATALOGO_DEPTOS');
  getSheet(ss, 'MATERIALES');
  getSheet(ss, 'LOG');
  return { ok: true };
}
