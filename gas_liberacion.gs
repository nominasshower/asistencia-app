// ============================================================
//  LIBERACION PDA - Google Apps Script Backend
//  Pegar este código en: Extensions > Apps Script
//  Luego: Deploy > New deployment > Web app
//    - Execute as: Me
//    - Who has access: Anyone
// ============================================================

var SPREADSHEET_ID   = '1yKxgCkw20mfm2d6Rh__WdrgusgYvkg1fyGDYiJIMwbs';
var FABRICACION_SHEET = 'Sistema fabricacion';
var LIBERACION_SHEET  = 'Sistema liberado';
var INSPECTORS_SHEET  = 'HISTORICO DE TRABAJO';
var TIMEZONE          = 'America/Mexico_City';

// Caché de headers para no releerlos en cada llamada
var _headers = null;
var _colMap  = null;

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

// ------ Obtener lista de inspectores ------
function getInspectors() {
  var ss    = SpreadsheetApp.openById(SPREADSHEET_ID);
  var sheet = ss.getSheetByName(INSPECTORS_SHEET);
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return { inspectors: [] };

  var data  = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
  var names = data.flat().filter(function(n) { return n !== '' && n !== null; });
  return { inspectors: names };
}

// ------ Buscar pieza por ID_CONECT (TextFinder = sin cargar toda la hoja) ------
function searchPiece(idConect) {
  if (!idConect) return { error: 'ID no proporcionado' };

  var ss    = SpreadsheetApp.openById(SPREADSHEET_ID);
  var sheet = ss.getSheetByName(FABRICACION_SHEET);

  // TextFinder busca directo en Sheets sin traer 91k filas a memoria
  var cell = sheet.createTextFinder(idConect.trim())
               .matchEntireCell(true)
               .findNext();

  if (!cell) return { found: false, error: 'Pieza no encontrada en fabricación' };

  var rowIndex = cell.getRow();

  // Solo leer headers (fila 1) y la fila encontrada
  var lastCol  = sheet.getLastColumn();
  var headers  = sheet.getRange(1, 1, 1, lastCol).getValues()[0];
  var row      = sheet.getRange(rowIndex, 1, 1, lastCol).getValues()[0];
  var col      = buildColMap(headers);

  var estatus = row[col['ESTATUS']];
  if (estatus === 'Liberado') {
    return { alreadyLiberated: true, error: '⚠️ Esta pieza ya fue liberada' };
  }

  return {
    found:    true,
    rowIndex: rowIndex,
    piece: {
      ID_CONECT:          String(row[col['ID_CONECT']]),
      FECHA:              formatDate(row[col['FECHA']]),
      HORA:               row[col['HORA']]              || '',
      DESCRIPCION_MODELO: row[col['DESCRIPCION_MODELO']]|| '',
      Codigo_corto:       row[col['Codigo corto']]      || '',
      ESTATUS:            estatus                        || '',
      CANTIDAD:           row[col['CANTIDAD']]           || 1,
      LINEA:              row[col['LINEA']]              || '',
      PESO:               row[col['PESO']]               || ''
    }
  };
}

// ------ Liberar pieza ------
function liberarPieza(params) {
  var idConect  = params.id;
  var inspector = params.inspector;
  var rowIndex  = parseInt(params.rowIndex);

  if (!idConect || !inspector) return { error: 'Datos incompletos' };

  var ss       = SpreadsheetApp.openById(SPREADSHEET_ID);
  var fabSheet = ss.getSheetByName(FABRICACION_SHEET);

  // Leer solo la fila necesaria (ya tenemos rowIndex del searchPiece)
  var lastCol = fabSheet.getLastColumn();
  var headers = fabSheet.getRange(1, 1, 1, lastCol).getValues()[0];
  var col     = buildColMap(headers);
  var fabRow  = fabSheet.getRange(rowIndex, 1, 1, lastCol).getValues()[0];

  if (fabRow[col['ESTATUS']] === 'Liberado') {
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
  var idLiberado = Utilities.formatDate(now, TIMEZONE, 'yyyyMMddHHmmssSSS');
  var horaxhora  = parseInt(Utilities.formatDate(now, TIMEZONE, 'H'));
  var antiguedad = calcAntiguedad(fechaFab, now);

  // Escribir en Sistema liberado
  var libSheet = ss.getSheetByName(LIBERACION_SHEET);
  libSheet.appendRow([
    idLiberado,
    fecha,
    hora,
    idConect,
    descripcion,
    codigoCorto,
    'Liberado',
    cantidad,
    inspector,
    linea,
    formatDate(fechaFab),
    antiguedad,
    horaxhora
  ]);

  // Actualizar solo la celda ESTATUS en fabricacion
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
