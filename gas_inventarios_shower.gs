// ============================================================
//  INVENTARIOS SW — Google Apps Script Backend
//  Acciones: upsert_inv, upsert_fisico, upsert_merma, delete_fisico
//
//  Deploy:
//  1. script.google.com → Nuevo proyecto → pegar este código
//  2. Implementar > Nueva implementación > Aplicación web
//     - Ejecutar como: Yo  |  Acceso: Cualquier persona
//  3. Copiar URL → consumos.html → GAS_INV_URL
//  4. Trigger keepAlive: Basado en tiempo · Cada 10 min
// ============================================================

var SPREADSHEET_ID = '1N8cyjOwqXj2AZIl_sGLagyH-djM1pJTx7KRCv8VKt7c';
var INV_SHEET      = 'INVENTARIOS';
var FIS_SHEET      = 'FISICO_SW';
var MERMA_SHEET    = 'MERMA_SW';
var TIMEZONE       = 'America/Mexico_City';

// ── Supabase ──────────────────────────────────────────────────
var SUP_URL = 'https://xzwlbrirzfogbqhywtvj.supabase.co';
var SUP_KEY = 'sb_secret_ZnXarLQFvdNjafxPOLvikQ_M92BVTDw';

function supabaseUpsertFisico(fecha, linea, gc, but, res, nor, mar, obs) {
  try {
    var payload = JSON.stringify({
      fecha: fecha, linea: linea,
      gelcoat_kg: gc, butanox_kg: but, resina_kg: res,
      norox_kg: nor, marmolina_kg: mar, observaciones: obs
    });
    UrlFetchApp.fetch(SUP_URL + '/rest/v1/fisico_sw', {
      method: 'post',
      contentType: 'application/json',
      payload: payload,
      headers: {
        'apikey': SUP_KEY,
        'Authorization': 'Bearer ' + SUP_KEY,
        'Prefer': 'resolution=merge-duplicates'
      },
      muteHttpExceptions: true
    });
  } catch(e) {
    Logger.log('Supabase upsert error: ' + e.message);
  }
}

function supabaseDeleteFisico(fecha, linea) {
  try {
    UrlFetchApp.fetch(
      SUP_URL + '/rest/v1/fisico_sw?fecha=eq.' + encodeURIComponent(fecha) + '&linea=eq.' + encodeURIComponent(linea),
      {
        method: 'delete',
        headers: {
          'apikey': SUP_KEY,
          'Authorization': 'Bearer ' + SUP_KEY
        },
        muteHttpExceptions: true
      }
    );
  } catch(e) {
    Logger.log('Supabase delete error: ' + e.message);
  }
}

// ─────────────────────────────────────────────────────────────

function doPost(e) {
  var result;
  try {
    var data = JSON.parse(e.postData.contents);
    if      (data.action === 'upsert_inv')    result = upsertInventario(data.rows);
    else if (data.action === 'upsert_fisico') result = upsertFisico(data);
    else if (data.action === 'upsert_merma')  result = upsertMerma(data);
    else if (data.action === 'delete_fisico') result = deleteFisicoSW(data);
    else result = { ok: false, error: 'Accion no reconocida: ' + data.action };
  } catch(err) {
    result = { ok: false, error: err.message };
  }
  return ContentService
    .createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}

function doGet(e) {
  return ContentService
    .createTextOutput(JSON.stringify({ ok: true, msg: 'GAS SW activo' }))
    .setMimeType(ContentService.MimeType.JSON);
}

function keepAlive() {
  SpreadsheetApp.openById(SPREADSHEET_ID).getName();
}

// ── Upsert inventario ─────────────────────────────────────────────
// Clave única: semana + material + linea
function upsertInventario(rows) {
  if (!rows || rows.length === 0) return { ok: false, error: 'Sin filas' };
  var ss    = SpreadsheetApp.openById(SPREADSHEET_ID);
  var sheet = ss.getSheetByName(INV_SHEET);
  if (!sheet) {
    sheet = ss.insertSheet(INV_SHEET);
    var hdr = ['Semana','Fecha Inicio','Fecha Fin','Material','Línea',
               'Inv. Inicial (kg)','Inv. Final (kg)','Consumo Real (kg)',
               'Entradas Odoo (kg)','Teórico (kg)'];
    sheet.getRange(1, 1, 1, hdr.length).setValues([hdr]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, hdr.length)
      .setBackground('#1e2535').setFontColor('#ffffff').setFontWeight('bold');
  }
  var lastRow  = sheet.getLastRow();
  var existing = {};
  if (lastRow > 1) {
    sheet.getRange(2, 1, lastRow - 1, 5).getValues().forEach(function(r, i) {
      existing[String(r[0])+'|'+String(r[3])+'|'+String(r[4])] = i + 2;
    });
  }
  var updated = 0;
  rows.forEach(function(row) {
    var semana = String(row.semana || ''), mat = String(row.material || ''), linea = String(row.linea || '');
    var invIni = row.invIni !== '' ? Number(row.invIni) : '';
    var invFin = row.invFin !== '' ? Number(row.invFin) : '';
    var consumo = (invIni !== '' && invFin !== '') ? Math.round((invIni - invFin) * 100) / 100 : '';
    var key = semana + '|' + mat + '|' + linea;
    if (existing[key]) {
      sheet.getRange(existing[key], 6, 1, 3).setValues([[invIni, invFin, consumo]]);
    } else {
      sheet.appendRow([semana, String(row.fechaIni||''), String(row.fechaFin||''),
                       mat, linea, invIni, invFin, consumo, '', '']);
      existing[key] = ++lastRow;
    }
    updated++;
  });
  if (sheet.getLastRow() > 1)
    sheet.getRange(2, 6, sheet.getLastRow()-1, 5).setNumberFormat('0.00');
  return { ok: true, updated: updated };
}

// ── Upsert consumo físico Shower Walls ───────────────────────────
// POST: { action:'upsert_fisico', fecha, linea,
//         Gelcoat, Butanox, Resina, Norox, Marmolina, obs }
// Clave única: fecha + linea
function upsertFisico(data) {
  var ss    = SpreadsheetApp.openById(SPREADSHEET_ID);
  var sheet = ss.getSheetByName(FIS_SHEET);
  var HEADERS = ['Fecha','Linea',
    'Gelcoat (kg)','Butanox (kg)','Resina (kg)','Norox (kg)','Marmolina (kg)',
    'Observaciones'];

  if (!sheet) {
    sheet = ss.insertSheet(FIS_SHEET);
    sheet.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, HEADERS.length)
      .setBackground('#1e2535').setFontColor('#ffffff').setFontWeight('bold');
  }

  var fecha  = String(data.fecha   || '');
  var linea  = String(data.linea   || '');
  var gc     = Number(data['Gelcoat']   || 0);
  var but    = Number(data['Butanox']   || 0);
  var res    = Number(data['Resina']    || 0);
  var nor    = Number(data['Norox']     || 0);
  var mar    = Number(data['Marmolina'] || 0);
  var obs    = String(data.obs || '');
  var key    = fecha + '|' + linea;

  var lastRow  = sheet.getLastRow();
  var existing = -1;
  if (lastRow > 1) {
    sheet.getRange(2, 1, lastRow - 1, 2).getValues().forEach(function(r, i) {
      // Fix: Sheets auto-convierte fechas a Date objects
      var f = r[0] instanceof Date
        ? Utilities.formatDate(r[0], TIMEZONE, 'yyyy-MM-dd')
        : String(r[0]).slice(0, 10);
      if (f + '|' + String(r[1]) === key) existing = i + 2;
    });
  }

  var row = [fecha, linea, gc, but, res, nor, mar, obs];
  if (existing > 0) {
    sheet.getRange(existing, 1, 1, row.length).setValues([row]);
  } else {
    sheet.appendRow(row);
  }
  if (sheet.getLastRow() > 1)
    sheet.getRange(2, 3, sheet.getLastRow()-1, 5).setNumberFormat('0.00');

  // ── Sync a Supabase ──────────────────────────────────────────
  supabaseUpsertFisico(fecha, linea, gc, but, res, nor, mar, obs);

  return { ok: true, updated: 1 };
}

// ── Upsert merma ──────────────────────────────────────────────────
// POST: { action:'upsert_merma', fecha, linea, kg, obs }
function upsertMerma(data) {
  var ss    = SpreadsheetApp.openById(SPREADSHEET_ID);
  var sheet = ss.getSheetByName(MERMA_SHEET);
  if (!sheet) {
    sheet = ss.insertSheet(MERMA_SHEET);
    var hdr = ['Fecha','Linea','kg Merma','Observaciones'];
    sheet.getRange(1, 1, 1, hdr.length).setValues([hdr]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, hdr.length)
      .setBackground('#1e2535').setFontColor('#ffffff').setFontWeight('bold');
  }
  var fecha = String(data.fecha || ''), linea = String(data.linea || '');
  var kg    = Number(data.kg || 0), obs = String(data.obs || '');
  var key   = fecha + '|' + linea;
  var lastRow = sheet.getLastRow(), existing = -1;
  if (lastRow > 1) {
    sheet.getRange(2, 1, lastRow - 1, 2).getValues().forEach(function(r, i) {
      var f = r[0] instanceof Date
        ? Utilities.formatDate(r[0], TIMEZONE, 'yyyy-MM-dd')
        : String(r[0]).slice(0, 10);
      if (f + '|' + String(r[1]) === key) existing = i + 2;
    });
  }
  var row = [fecha, linea, kg, obs];
  if (existing > 0) sheet.getRange(existing, 1, 1, 4).setValues([row]);
  else sheet.appendRow(row);
  if (sheet.getLastRow() > 1)
    sheet.getRange(2, 3, sheet.getLastRow()-1, 1).setNumberFormat('0.000');
  return { ok: true, updated: 1 };
}

// ── Borrar consumo físico SW ──────────────────────────────────────
function deleteFisicoSW(data) {
  var ss    = SpreadsheetApp.openById(SPREADSHEET_ID);
  var sheet = ss.getSheetByName(FIS_SHEET);
  if (!sheet) return { ok: false, error: 'Hoja FISICO_SW no existe' };
  var fecha = String(data.fecha || '');
  var linea = String(data.linea || '');
  var key   = fecha + '|' + linea;
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return { ok: false, error: 'Sin registros' };
  var vals = sheet.getRange(2, 1, lastRow - 1, 2).getValues();
  var rowToDelete = -1;
  vals.forEach(function(r, i) {
    var f = r[0] instanceof Date
      ? Utilities.formatDate(r[0], TIMEZONE, 'yyyy-MM-dd')
      : String(r[0]).slice(0, 10);
    if (f + '|' + String(r[1]) === key) rowToDelete = i + 2;
  });
  if (rowToDelete < 0) return { ok: false, error: 'Registro no encontrado: ' + key };
  sheet.deleteRow(rowToDelete);

  // ── Sync a Supabase ──────────────────────────────────────────
  supabaseDeleteFisico(fecha, linea);

  return { ok: true, deleted: 1 };
}
