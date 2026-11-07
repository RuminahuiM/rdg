// @vitest-environment node
// The generated contract types must match src/Api/openapi.yaml (run `npm run api:types`).
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import openapiTS, { astToString } from 'openapi-typescript';

const spec = new URL('../../../Api/openapi.yaml', import.meta.url);
const generated = new URL('./schema.d.ts', import.meta.url);

describe('contract types', () => {
  it('schema.d.ts is current', async () => {
    const ast = await openapiTS(await readFile(fileURLToPath(spec), 'utf8'), { defaultNonNullable: false });
    const expected = astToString(ast);
    const actual = await readFile(fileURLToPath(generated), 'utf8');
    // The CLI adds a header comment; compare the code itself.
    const strip = (text: string) => text.replace(/^\/\*\*[\s\S]*?\*\/\s*/, '').trim();
    expect(strip(actual)).toBe(strip(expected));
  });
});
