const {test} = require('node:test');
const assert = require('node:assert/strict');
const core = require('../web/core.js');
test('preserves nested and Unicode data while formatting', () => {
  const source = '{"Tiếng Việt":{"array":[true,2,null,"✨"]}}';
  assert.deepEqual(JSON.parse(core.formatJSON(source)), JSON.parse(source));
});
test('rejects invalid JSON and non-object root', () => {
  for (const s of ['{bad}', 'null', '[]', '2']) assert.throws(() => core.parseJSON(s));
});
test('typed edits preserve other fields and reject invalid booleans and numbers', () => {
  const s = '{"other":{"a":2}}';
  assert.deepEqual(JSON.parse(core.setField(s,'enabled','boolean','false')), {other:{a:2},enabled:false});
  for (const v of ['Infinity','','NaN']) assert.throws(() => core.setField(s,'n','number',v));
  assert.throws(() => core.setField(s,'b','boolean','yes'));
});
test('prototype keys are ordinary data; package header and filenames are explicit', () => {
  const d = JSON.parse(core.setField('{}','__proto__','json','{"polluted":true}'));
  assert.equal(d.__proto__.polluted,true); assert.equal({}.polluted,undefined);
  assert.equal(core.outputName('fake.3105','json'),'fake.json');
  assert.equal(core.is3105(Buffer.from('3105PATCH\0abc')),true);
  assert.equal(core.is3105(Buffer.from('{"schemaVersion":9}')),false);
});
