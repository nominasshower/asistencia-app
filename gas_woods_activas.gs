// ═══════════════════════════════════════════════════════════════════
// PEGAR ESTO EN EL Apps Script existente de Torres 1000
// ═══════════════════════════════════════════════════════════════════
//
// En doGet(e)  → agregar dentro del switch(accion):
//   case 'get_activas':
//     return respJSON(getActivas());
//
// En doPost(e) → agregar dentro del switch(accion):
//   case 'activar_area':
//     return respJSON(activarArea(data));
//
// ═══════════════════════════════════════════════════════════════════

function inicializarHojaActivas() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('ACTIVAS');
  if (!sheet) {
    sheet = ss.insertSheet('ACTIVAS');
    sheet.appendRow(['TORRE','PISO','DEPTO','AREA','ACTIVA','FECHA']);
    sheet.getRange(1,1,1,6).setFontWeight('bold');
  }
  return sheet;
}

function activarArea(data) {
  var sheet  = inicializarHojaActivas();
  var torre  = String(data.torre  || '').trim();
  var piso   = String(data.piso   || '').trim();
  var depto  = String(data.depto  || '').trim();
  var area   = String(data.area   || '').trim();
  var activa = data.activa === true || data.activa === 'true';

  var lastRow = sheet.getLastRow();
  var existingRow = -1;

  if (lastRow > 1) {
    var values = sheet.getRange(2, 1, lastRow - 1, 4).getValues();
    for (var i = 0; i < values.length; i++) {
      if (String(values[i][0]).trim() === torre &&
          String(values[i][1]).trim() === piso  &&
          String(values[i][2]).trim() === depto &&
          String(values[i][3]).trim() === area) {
        existingRow = i + 2;
        break;
      }
    }
  }

  if (!activa) {
    if (existingRow > -1) sheet.deleteRow(existingRow);
    return { ok: true, accion: 'eliminada' };
  }

  var fecha = new Date();
  if (existingRow > -1) {
    sheet.getRange(existingRow, 1, 1, 6).setValues([[torre, piso, depto, area, true, fecha]]);
    return { ok: true, accion: 'actualizada' };
  } else {
    sheet.appendRow([torre, piso, depto, area, true, fecha]);
    return { ok: true, accion: 'creada' };
  }
}

function getActivas() {
  var sheet   = inicializarHojaActivas();
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];
  var values  = sheet.getRange(2, 1, lastRow - 1, 4).getValues();
  return values
    .filter(function(r){ return r[0] !== ''; })
    .map(function(r){
      return { torre: String(r[0]), piso: String(r[1]), depto: String(r[2]), area: String(r[3]) };
    });
}
