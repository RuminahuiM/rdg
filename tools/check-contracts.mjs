// Checks the data contracts:
//  1. every JSON schema in schemas/cosmos compiles (draft 2020-12, strict mode),
//  2. every fixture in tests/Fixtures/cosmos validates against the schema for its "type",
//  3. a set of deliberately broken documents is rejected (so the schemas actually constrain),
//  4. the OpenAPI file parses and references only defined components,
//  5. example API bodies in tests/Fixtures/api validate (or are rejected) as expected,
//  6. the API's copy of the contract (src/Api/Modules/DgApi/openapi.json) matches the YAML.
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { parse } from 'yaml';
import { openApiJsonPath, renderOpenApiJson } from './export-openapi.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const schemaDir = join(root, 'schemas', 'cosmos');
const fixtureDir = join(root, 'tests', 'Fixtures', 'cosmos');
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));

// strictRequired is off because conditional branches (if/then) require properties defined one level up.
const ajv = new Ajv2020({ allErrors: true, strict: true, strictRequired: false, allowUnionTypes: true });
addFormats(ajv);

let failures = 0;
const fail = (msg) => { failures++; console.error(`FAIL ${msg}`); };
const pass = (msg) => console.log(`ok   ${msg}`);

// 1. Compile schemas
for (const file of readdirSync(schemaDir).filter((f) => f.endsWith('.schema.json'))) {
  ajv.addSchema(readJson(join(schemaDir, file)));
}
const byType = {
  definition: 'definition', settings: 'settings', audit: 'audit', status: 'status',
  lock: 'lock', heartbeat: 'heartbeat', run: 'run', schema: 'schema-marker',
};
const validators = {};
const validatorFor = (type) => {
  const name = byType[type];
  if (!name) return null;
  if (!(name in validators)) {
    try { validators[name] = ajv.getSchema(`https://schemas.rdg.invalid/cosmos/${name}.schema.json`); }
    catch (e) { validators[name] = null; fail(`schema ${name}: ${e.message}`); }
  }
  return validators[name];
};
for (const [type, name] of Object.entries(byType)) {
  if (validatorFor(type)) pass(`schema ${name} compiles`);
}

// 2. Valid fixtures
const fixtures = {};
for (const file of readdirSync(fixtureDir).filter((f) => f.endsWith('.json'))) {
  const doc = readJson(join(fixtureDir, file));
  fixtures[file] = doc;
  const validate = validatorFor(doc.type);
  if (!validate) { fail(`${file}: unknown type "${doc.type}"`); continue; }
  if (validate(doc)) pass(`fixture ${file}`);
  else fail(`fixture ${file}: ${ajv.errorsText(validate.errors, { separator: '; ' })}`);
}

// 3. Broken documents must be rejected
const clone = (o) => structuredClone(o);
const broken = [
  ['definition without rule', () => { const d = clone(fixtures['definition.json']); delete d.rule; return d; }],
  ['definition with unknown field', () => ({ ...clone(fixtures['definition.json']), colour: 'blue' })],
  ['definition with bad id', () => ({ ...clone(fixtures['definition.json']), id: 'def-123' })],
  ['create target with groupId', () => { const d = clone(fixtures['definition-create.json']); d.target.groupId = '0b7d2c1e-5a4f-4e3b-9c8d-7f6e5d4c3b2a'; return d; }],
  ['existing target without groupId', () => { const d = clone(fixtures['definition.json']); delete d.target.groupId; return d; }],
  ['frequency below 3 minutes', () => ({ ...clone(fixtures['definition.json']), frequencyMinutes: 1 }) ],
  ['status with unknown result', () => ({ ...clone(fixtures['status.json']), lastResult: 'Fine' })],
  ['audit without ttl', () => { const d = clone(fixtures['audit.json']); delete d.ttl; return d; }],
  ['run with more than 500 added', () => { const d = clone(fixtures['run.json']); d.added = Array(501).fill(d.added[0]); return d; }],
  ['paused run with definition fields', () => ({ ...clone(fixtures['run-paused.json']), addedCount: 3 })],
  ['settings change limit 0', () => ({ ...clone(fixtures['settings.json']), changeLimitPercent: 0 })],
  ['lock for unknown runbook', () => ({ ...clone(fixtures['lock.json']), id: 'lock-Other' })],
];
for (const [label, make] of broken) {
  const doc = make();
  const validate = validatorFor(doc.type);
  if (!validate) continue;
  if (validate(doc)) fail(`broken doc accepted: ${label}`);
  else pass(`rejects ${label}`);
}

// 4. OpenAPI: parse and check every local $ref resolves
const apiPath = join(root, 'src', 'Api', 'openapi.yaml');
const api = parse(readFileSync(apiPath, 'utf8'));
const refs = [];
(function walk(node) {
  if (Array.isArray(node)) node.forEach(walk);
  else if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) {
      if (k === '$ref' && typeof v === 'string') refs.push(v);
      else walk(v);
    }
  }
})(api);
for (const ref of new Set(refs)) {
  const target = ref.replace(/^#\//, '').split('/').reduce((n, key) => n?.[key], api);
  if (target === undefined) fail(`openapi: unresolved ${ref}`);
}
const ops = Object.values(api.paths).flatMap((p) => Object.keys(p).filter((m) => ['get', 'post', 'put', 'delete', 'patch'].includes(m)));
const userFacing = ops.length - 1; // minus the internal /roles endpoint
if (userFacing !== 18) fail(`openapi: expected 18 user-facing operations, found ${userFacing}`);
else pass('openapi: 18 user-facing operations, all $refs resolve');

// 5. API examples validate against the OpenAPI component schemas (OpenAPI 3.1 = JSON Schema 2020-12).
//    Catches composition mistakes such as allOf + additionalProperties rejecting valid responses.
const apiAjv = new Ajv2020({ allErrors: true, strict: false, allowUnionTypes: true });
addFormats(apiAjv);
const componentsJson = JSON.stringify(api.components.schemas).replaceAll('#/components/schemas/', '#/$defs/');
apiAjv.addSchema({ $id: 'https://schemas.rdg.invalid/api.json', $defs: JSON.parse(componentsJson) });
const apiDir = join(root, 'tests', 'Fixtures', 'api');
for (const file of readdirSync(apiDir).filter((f) => f.endsWith('.json'))) {
  const { schema, valid, body } = readJson(join(apiDir, file));
  const validate = apiAjv.getSchema(`https://schemas.rdg.invalid/api.json#/$defs/${schema}`);
  if (!validate) { fail(`api ${file}: unknown schema ${schema}`); continue; }
  const ok = validate(body);
  if (ok === valid) pass(`api ${file} (${schema}, ${valid ? 'valid' : 'rejected'})`);
  else fail(`api ${file}: expected ${valid ? 'valid' : 'invalid'} for ${schema}${ok ? '' : `: ${apiAjv.errorsText(validate.errors, { separator: '; ' })}`}`);
}

// 6. The API's JSON copy of the contract is current
let current = '';
try { current = readFileSync(openApiJsonPath, 'utf8'); } catch { /* missing */ }
if (current.replace(/\r\n/g, '\n') === renderOpenApiJson()) pass('openapi.json matches openapi.yaml');
else fail('src/Api/Modules/DgApi/openapi.json is out of date; run npm run api:export');

if (failures) { console.error(`\n${failures} failure(s)`); process.exit(1); }
console.log('\nAll contract checks passed.');
