import test from 'node:test';
import assert from 'node:assert/strict';
import {leaveOffice,leaveGroup,officeLabel} from '../public/leave-routing.js';
test('requested approval matrix and support spelling variants',()=>{
 for(const [title,office] of [['Teacher','principal'],['Staff','principal'],['Principal','director'],['Director','president'],['Substaff','hr'],['Sub Staff','hr'],['Aayah','hr'],['Aayahs','hr'],['Ayah','hr'],['Aaya','hr'],['Attender','hr'],['Attendant','hr'],['Security Guard','hr'],['Securty','hr']])assert.equal(leaveOffice({designation:title}),office,title);
});
test('classification uses employment category and department without title substring escalation',()=>{
 assert.equal(leaveOffice({department:'Substaff'}),'hr');assert.equal(leaveOffice({employment_category:'Aayahs'}),'hr');
 assert.equal(leaveOffice({designation:'Vice Principal'}),'principal');assert.equal(leaveOffice({designation:'Director Assistant'}),'principal');assert.equal(leaveOffice({designation:'Principal Teacher'}),'principal');
});
test('explicit reviewed group takes precedence and President needs a policy',()=>{
 assert.equal(leaveOffice({designation:'Teacher',leave_group:'director'}),'president');assert.equal(leaveOffice({designation:'Security',leave_group:'teacher_staff'}),'principal');
 assert.equal(leaveOffice({designation:'President'}),null);assert.equal(leaveGroup({designation:'  PRINCIPAL '}),'principal');assert.equal(officeLabel('hr'),'HR');
});
