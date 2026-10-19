import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseCSV} from '../public/domain.js';
import {biometricColumns,biometricExampleRows,biometricTemplateCSV,biometricSampleCSV} from '../public/biometric-csv.js';
test('Downloadable sample round-trips through the real importer parser',()=>{const rows=parseCSV(biometricSampleCSV());assert.deepEqual(rows,biometricExampleRows);assert.deepEqual(Object.keys(rows[0]),biometricColumns);});
test('Sample has a complete India-time in/out pair with distinct device event IDs',()=>{const keys=new Set();for(const r of parseCSV(biometricSampleCSV())){for(const k of biometricColumns)assert.ok(r[k]);assert.match(r.event_timestamp_iso8601,/\+05:30$/);assert.ok(Number.isFinite(Date.parse(r.event_timestamp_iso8601)));assert.ok(['in','out'].includes(r.punch_direction));assert.ok(!keys.has(r.device_id+'/'+r.event_id));keys.add(r.device_id+'/'+r.event_id);}assert.equal(biometricExampleRows[0].biometric_id,biometricExampleRows[1].biometric_id);assert.ok(Date.parse(biometricExampleRows[1].event_timestamp_iso8601)>Date.parse(biometricExampleRows[0].event_timestamp_iso8601));});
test('Blank template contains exactly the importer headings and no example punches',()=>{assert.equal(biometricTemplateCSV().trim(),biometricColumns.join(','));assert.deepEqual(parseCSV(biometricTemplateCSV()),[]);});
