import {csvText} from './domain.js';
export const biometricColumns=['device_id','event_id','biometric_id','event_timestamp_iso8601','punch_direction'];
export const biometricExampleRows=[
 {device_id:'DEVICE-01',event_id:'EXAMPLE-IN-001',biometric_id:'BIO-001',event_timestamp_iso8601:'2026-10-19T08:05:00+05:30',punch_direction:'in'},
 {device_id:'DEVICE-01',event_id:'EXAMPLE-OUT-001',biometric_id:'BIO-001',event_timestamp_iso8601:'2026-10-19T14:30:00+05:30',punch_direction:'out'}
];
export const biometricTemplateCSV=()=>biometricColumns.join(',')+'\r\n';
export const biometricSampleCSV=()=>csvText(biometricExampleRows);
