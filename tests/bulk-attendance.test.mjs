import {test} from 'node:test';
import assert from 'node:assert/strict';
import {attendanceDraft} from '../public/bulk-attendance.js';
test('New attendance rows carry their snapshot and no invented times',()=>{assert.deepEqual(attendanceDraft({staff_id:'s1',source_hash:'v1',attendance:null}),{staff_id:'s1',source_hash:'v1',status:'present',in_time:'',out_time:'',late_minutes:0,early_minutes:0,calculate_shift:false,out_next_day:false,note:''});});
test('Existing rows preserve raw late minutes, status and overnight information without implicit recalculation',()=>{const d=attendanceDraft({staff_id:'s1',source_hash:'v2',attendance:{status:'half_day',in_time:'22:03:00',out_time:'06:00:00',raw_late_minutes:3,late_minutes:0,early_minutes:5,shift_snapshot:{out_next_day:true},note:'Reviewed'}});assert.equal(d.late_minutes,3);assert.equal(d.in_time,'22:03');assert.equal(d.status,'half_day');assert.equal(d.out_next_day,true);assert.equal(d.calculate_shift,false);assert.equal(d.note,'Reviewed');});
test('Legacy rows fall back to their reviewed late minutes',()=>{assert.equal(attendanceDraft({attendance:{late_minutes:7}}).late_minutes,7);});
