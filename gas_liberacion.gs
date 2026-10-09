// ============================================================
//  LIBERACION PDA - Google Apps Script Backend
//  Pegar este código en: Extensions > Apps Script
//  Luego: Deploy > New deployment > Web app
//    - Execute as: Me
//    - Who has access: Anyone
//
//  IMPORTANTE: Para evitar arranque lento, crear un trigger:
//  Triggers (reloj) > + Agregar trigger
//    Función: keepAlive | Evento: Basado en tiempo | Cada 10 minutos
// ============================================================

var SPREADSHEET_ID    = '1yKxgCkw20mfm2d6Rh__WdrgusgYvkg1fyGDYiJIMwbs';
var FABRICACION_SHEET = 'Sistema fabricacion';
var LIBERACION_SHEET  = 'Sistema liberado';
var INSPECTORS_SHEET  = 'Inspector';   // columnas: id_inspector, Inspector, Linea, Estatus
var TIMEZONE          = 'America/Mexico_City';

function doGet(e) {
  var action = e.parameter.action;
  var result;
  try {
    if      (action === 'getInspectors') result = getInspectors();
    else if (action === 'searchPiece')   result = searchPiece(e.parameter.id);
    else if (action === 'liberarPieza')  result = liberarPieza(e.parameter);
    else result = { error: 'Acción no reconocida' };
  } catch (err) {
    result = { error: err.message };
  }
  return ContentService
    .createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}

// Mantiene el GAS caliente — asignar trigger cada 10 min
function keepAlive() {
  SpreadsheetApp.openById(SPREADSHEET_ID).getName();
}

// ------ Obtener lista de inspectores (solo los Activos) ------
function getInspectors() {
  var ss      = SpreadsheetApp.openById(SPREADSHEET_ID);
  var sheet   = ss.getSheetByName(INSPECTORS_SHEET);
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return { inspectors: [] };
  var data  = sheet.getRange(2, 1, lastRow - 1, 4).getValues();
  var names = [];
  for (var i = 0; i < data.length; i++) {
    if (String(data[i][3]).trim() === 'Activo' && data[i][1] !== '') names.push(String(data[i][1]).trim());
  }
  return { inspectors: names };
}

// ¿Ya existe en Sistema liberado? (AppSheet no marca Liberado en fabricación)
function yaLiberado(ss, idConect) {
  var lib = ss.getSheetByName(LIBERACION_SHEET);
  var last = lib.getLastRow();
  if (last < 2) return false;
  var ids = lib.getRange(2, 4, last - 1, 1).getValues();
  var s = String(idConect).trim().toUpperCase();
  for (var i = 0; i < ids.length; i++) if (String(ids[i][0]).trim().toUpperCase() === s) return true;
  return false;
}

// ------ Buscar pieza: solo lee columna A para localizar la fila ------
function searchPiece(idConect) {
  if (!idConect) return { error: 'ID no proporcionado' };

  var ss      = SpreadsheetApp.openById(SPREADSHEET_ID);
  var sheet   = ss.getSheetByName(FABRICACION_SHEET);
  var lastRow = sheet.getLastRow();

  // Lee solo la columna A (ID_CONECT) — mucho más rápido que toda la hoja
  var search   = idConect.trim().toUpperCase();
  var rowIndex = -1;

  // Índice en caché de los últimos IDs: casi no lee la hoja
  var idx = loadFabIndex(sheet, lastRow);
  var pos = idx.ids.lastIndexOf(search);
  if (pos >= 0) {
    rowIndex = idx.start + pos;
    // verificación barata: la celda sigue teniendo ese ID (si se movieron filas, se reconstruye)
    if (String(sheet.getRange(rowIndex, 1).getValue()).trim().toUpperCase() !== search) {
      CacheService.getScriptCache().remove('fabIdx');
      rowIndex = -1;
    }
  }
  // Más antiguo que el índice: búsqueda larga (solo piezas viejas o inexistentes)
  if (rowIndex === -1 && idx.start > 2) rowIndex = buscarFila(sheet, 2, idx.start - 1, search);

  if (rowIndex === -1) return { found: false, error: 'Pieza no encontrada en fabricación' };

  var cm  = getColMap(sheet);
  var col = cm.map;
  var row = sheet.getRange(rowIndex, 1, 1, cm.n).getValues()[0];

  var estatus = row[col['ESTATUS']];
  if (estatus === 'Liberado' || yaLiberado(ss, idConect)) {
    return { alreadyLiberated: true, error: '⚠️ Esta pieza ya fue liberada' };
  }

  return {
    found:    true,
    rowIndex: rowIndex,
    piece: {
      ID_CONECT:          String(row[col['ID_CONECT']]),
      FECHA:              formatDate(row[col['FECHA']]),
      HORA:               row[col['HORA']]               || '',
      DESCRIPCION_MODELO: row[col['DESCRIPCION_MODELO']] || '',
      Codigo_corto:       row[col['Codigo corto']]       || '',
      ESTATUS:            estatus                         || '',
      CANTIDAD:           row[col['CANTIDAD']]            || 1,
      LINEA:              row[col['LINEA']]               || '',
      PESO:               row[col['PESO']]                || ''
    }
  };
}

// Columnas de la hoja de fabricación en caché (6 h) para no leer encabezados en cada llamada
function getColMap(sheet) {
  var cache = CacheService.getScriptCache();
  var raw = cache.get('fabCols');
  if (raw) return JSON.parse(raw);
  var n = sheet.getLastColumn();
  var cm = { map: buildColMap(sheet.getRange(1, 1, 1, n).getValues()[0]), n: n };
  cache.put('fabCols', JSON.stringify(cm), 21600);
  return cm;
}

// Índice en caché de los IDs de las últimas MAX_IDX filas; solo lee las filas nuevas desde la última vez
var MAX_IDX = 3000;
function loadFabIndex(sheet, lastRow) {
  var cache = CacheService.getScriptCache();
  var raw = cache.get('fabIdx');
  var idx = raw ? JSON.parse(raw) : null;
  var changed = false;

  if (!idx || idx.start + idx.ids.length - 1 > lastRow) {
    var start = Math.max(2, lastRow - MAX_IDX + 1);
    var vals = sheet.getRange(start, 1, lastRow - start + 1, 1).getValues();
    idx = { start: start, ids: vals.map(function(v) { return String(v[0]).trim().toUpperCase(); }) };
    changed = true;
  } else {
    var have = idx.start + idx.ids.length - 1;
    if (have < lastRow) {
      var nuevos = sheet.getRange(have + 1, 1, lastRow - have, 1).getValues();
      for (var i = 0; i < nuevos.length; i++) idx.ids.push(String(nuevos[i][0]).trim().toUpperCase());
      changed = true;
    }
  }
  if (idx.ids.length > MAX_IDX) {
    var cut = idx.ids.length - MAX_IDX;
    idx.ids = idx.ids.slice(cut); idx.start += cut; changed = true;
  }
  if (changed) { try { cache.put('fabIdx', JSON.stringify(idx), 21600); } catch (e) {} }
  return idx;
}

// Busca search en columna A entre las filas desde..hasta, de abajo hacia arriba
function buscarFila(sheet, desde, hasta, search) {
  if (hasta < desde) return -1;
  var ids = sheet.getRange(desde, 1, hasta - desde + 1, 1).getValues();
  for (var i = ids.length - 1; i >= 0; i--) {
    if (String(ids[i][0]).trim().toUpperCase() === search) return desde + i;
  }
  return -1;
}

// ------ Liberar pieza ------
function liberarPieza(params) {
  var idConect  = params.id;
  var inspector = params.inspector;
  var rowIndex  = parseInt(params.rowIndex);

  if (!idConect || !inspector) return { error: 'Datos incompletos' };

  var ss       = SpreadsheetApp.openById(SPREADSHEET_ID);
  var fabSheet = ss.getSheetByName(FABRICACION_SHEET);
  var cm       = getColMap(fabSheet);
  var col      = cm.map;
  var fabRow   = fabSheet.getRange(rowIndex, 1, 1, cm.n).getValues()[0];

  if (String(fabRow[col['ID_CONECT']]).trim().toUpperCase() !== String(idConect).trim().toUpperCase()) {
    return { error: 'La fila no coincide con la pieza, vuelve a escanear' };
  }

  if (fabRow[col['ESTATUS']] === 'Liberado' || yaLiberado(ss, idConect)) {
    return { error: '⚠️ Esta pieza ya fue liberada por otro usuario' };
  }

  var descripcion = fabRow[col['DESCRIPCION_MODELO']] || '';
  var codigoCorto = fabRow[col['Codigo corto']]       || '';
  var cantidad    = fabRow[col['CANTIDAD']]            || 1;
  var linea       = fabRow[col['LINEA']]               || '';
  var fechaFab    = fabRow[col['FECHA']];

  var now        = new Date();
  var fecha      = Utilities.formatDate(now, TIMEZONE, 'M/d/yyyy');
  var hora       = Utilities.formatDate(now, TIMEZONE, 'HH:mm:ss');
  var idLiberado = idConect;   // igual que AppSheet: id_liberado = ID_CONECT
  var horaxhora  = parseInt(Utilities.formatDate(now, TIMEZONE, 'H'));
  var antiguedad = calcAntiguedad(fechaFab, now);

  var libSheet = ss.getSheetByName(LIBERACION_SHEET);
  libSheet.appendRow([
    idLiberado, fecha, hora, idConect,
    descripcion, codigoCorto, 'Liberado', cantidad,
    inspector, linea, formatDate(fechaFab), antiguedad, horaxhora,
    horaxhora >= 17 ? 'Tiempo Extra' : 'Tiempo Normal'
  ]);

  fabSheet.getRange(rowIndex, col['ESTATUS'] + 1).setValue('Liberado');

  return { success: true, message: 'Pieza liberada correctamente', idLiberado: idLiberado };
}

// ------ Helpers ------
function buildColMap(headers) {
  var map = {};
  for (var i = 0; i < headers.length; i++) map[headers[i]] = i;
  return map;
}

function formatDate(d) {
  if (!d) return '';
  if (typeof d === 'string') return d;
  try { return Utilities.formatDate(new Date(d), TIMEZONE, 'M/d/yyyy'); }
  catch(e) { return String(d); }
}

function calcAntiguedad(fechaFab, now) {
  try {
    var fab = new Date(fechaFab); fab.setHours(0,0,0,0);
    var hoy = new Date(now);     hoy.setHours(0,0,0,0);
    var dias = Math.round((hoy - fab) / 86400000);
    if (dias === 0) return 'Del dia';
    if (dias === 1) return 'Dia anterior';
    return 'Anteriores';
  } catch(e) { return 'Anteriores'; }
}
