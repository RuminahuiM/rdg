// Writes src/Api/Modules/DgApi/openapi.json from src/Api/openapi.yaml.
// The API validates request bodies and checks roles against it, so the contract has one source.
// check-contracts.mjs fails when the JSON is out of date: run `npm run api:export` after editing the YAML.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
export const openApiJsonPath = join(root, 'src', 'Api', 'Modules', 'DgApi', 'openapi.json');
export const renderOpenApiJson = () =>
  JSON.stringify(parse(readFileSync(join(root, 'src', 'Api', 'openapi.yaml'), 'utf8')), null, 2) + '\n';

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  writeFileSync(openApiJsonPath, renderOpenApiJson());
  console.log(`wrote ${openApiJsonPath}`);
}
