# Web app

The admin and reader interface of RDG: groups, rule editor, approvals, activity, audit and
settings. React 18, TypeScript, Vite, Fluent UI v9, TanStack Query, React Router, React Hook
Form and CodeMirror 6. It talks only to the RDG API (`/api`, see `src/Api/openapi.yaml`)
through the Static Web App, which signs users in with Entra ID.

## Run it

```bash
cd src/Web
npm ci
npm run dev:mock     # http://localhost:5173 with the in-browser mock API, no tenant needed
npm run dev          # against the local API host (tools/Start-ApiLocal.ps1, port 7071)
```

Mock scenarios, set once per browser tab with URL parameters:

| Parameter           | Effect                                                               |
| ------------------- | -------------------------------------------------------------------- |
| `?mockRole=reader`  | signed in as reader (`admin`, `none` for Access denied, `signedOut`) |
| `?mockPaused=1`     | syncing is paused (banner)                                           |
| `?mockReadOnly=1`   | read-only installation (banner, approvals refused)                   |
| `?mockEmpty=1`      | no definitions yet (empty state)                                     |
| `?mockEngineMs=300` | how long the simulated engine takes to handle Sync now and approvals |

The mock data is invented (contoso.org). In the browser console, `__rdgMock.touch(id, { frequencyMinutes: 30 })`
simulates another admin saving a group, which shows the conflict dialog on the next save.

## Scripts

| Script                 | What it does                                                                     |
| ---------------------- | -------------------------------------------------------------------------------- |
| `npm run typecheck`    | TypeScript, strict                                                               |
| `npm run format:check` | Prettier                                                                         |
| `npm run lint`         | ESLint (typescript-eslint strict, React hooks)                                   |
| `npm test`             | Vitest: helpers, rule editor, mock API, whole-app tests against the mock (jsdom) |
| `npm run build`        | production build to `dist/` (no mock code, includes `staticwebapp.config.json`)  |
| `npm run build:mock`   | mock build to `dist-mock/`                                                       |
| `npm run test:e2e`     | Playwright against the mock build (`vite preview` on port 4173)                  |
| `npm run api:types`    | regenerates `src/api/schema.d.ts` from `../Api/openapi.yaml`                     |

A test fails when `src/api/schema.d.ts` is older than the contract. `src/rules/properties.json`
(the property names and types the editor suggests) comes from the engine:
run `tools/Export-RuleProperties.ps1` after changing the engine's property map; a Pester test
checks that it is current.

Where Playwright can't download its browser, point it at an installed Chromium:
`PLAYWRIGHT_CHROMIUM=/path/to/chromium npm run test:e2e`.

## Layout

```
src/
  api/          contract types (generated), fetch client (ETag, problems), query hooks
  auth/         /api/me on start: sign-in redirect, Access denied, admin or reader
  layout/       header, navigation, paused and read-only banners, toasts
  pages/        Groups, Activity (+ run panel), Audit, Settings, error screens
  pages/group/  the group page: form (new / edit / adopt), reader view, form conversions
  dialogs/      approve once, conflict (412), delete
  components/   badges, pickers, preview, status card, Sync now tracking
  rules/        tokenizer, autocomplete and the CodeMirror editor
  strings/en.ts every user-facing text
  mocks/        MSW handlers, invented tenant, a small rule evaluator for previews
public/staticwebapp.config.json   routes, roles source, CSP and other headers
mock-public/                      the MSW service worker (mock mode only)
e2e/                              Playwright flows
```

## Notes

- Light and dark follow the operating system. Desktop first; the layout stacks below 1100 px.
- Every save sends `If-Match`; a 412 opens the conflict dialog with the fields that differ.
- The rule is checked by the engine (`POST /rules/validate`) 400 ms after typing stops; the
  editor only colours and suggests, it never decides validity itself.
- `staticwebapp.config.json` contains `__TENANT_ID__` (issuer URL) and `__KEY_VAULT_NAME__` (the sign-in
  certificate's Key Vault reference); the deployment replaces both. The Static Web App reads the
  certificate with its system-assigned identity; the client ID comes from the `AAD_CLIENT_ID` app setting.
- npm 10 crashes on the optional vitest peer set; `.npmrc` sets `legacy-peer-deps` and the
  needed peers are listed in `package.json`.
