import {test} from 'node:test';
import assert from 'node:assert/strict';
import {romeDay,dayHours,dayStart} from '../lib/dates.ts';
test('Rome calendar day includes late UTC evening',()=>{
 assert.equal(romeDay('2026-11-24T23:30:00Z'),'2026-11-25');
 assert.equal(romeDay('2026-07-24T22:30:00Z'),'2026-07-25');
});
test('Historical day is bounded, including both daylight saving transitions',()=>{
 const future=Date.parse('2027-01-01T00:00:00Z');
 assert.equal(dayHours('2026-03-29',future),23);
 assert.equal(dayHours('2026-10-25',future),25);
 assert.equal(dayHours('2026-11-25',future),24);
});
test('Today uses elapsed hours in Rome and future days return zero',()=>{
 assert.equal(dayStart('2026-11-25'),Date.parse('2026-11-24T23:00:00Z'));
 assert.equal(dayHours('2026-11-25',Date.parse('2026-11-25T11:00:00Z')),12);
 assert.equal(dayHours('2026-11-26',Date.parse('2026-11-25T11:00:00Z')),0);
});
