# Component Design: Web App

Oct 9, 2026 · @Dodoe

The web app is the dashboard IT uses to manage definitions and check runs; it holds no logic of its own. Part of Doc.

## Decisions

The web app is a static single-page app with no logic of its own: every rule check, preview and permission decision comes from the API. That keeps it small and easy to replace.

| Topic | Choice | Why |
| --- | --- | --- |
| Framework | React 18 + TypeScript, built with Vite | Static files only; no server rendering, no framework upgrade churn |
| Components | Fluent UI React v9 | Looks like the Microsoft admin portals; covers tables, forms, dialogs, pickers, toasts |
| Rule editor | CodeMirror 6 via @uiw/react-codemirror | Roughly 50–200 kB instead of several MB for Monaco; custom highlighting and lint markers are simple |
| Data fetching | TanStack Query | Caching, retries, polling for sync status, ETag handling in one place |
| Routing | React Router | Deep links to a group, e.g. /groups/{id} |
| Forms | React Hook Form | Validation without re-rendering the whole form |
| API types | Generated from the API's OpenAPI file (openapi-typescript) | UI and API cannot drift apart unnoticed |
| Versions | All pinned; Renovate pull requests in Azure DevOps | Updates only after CI passes |

## Screen map

&#91;embedded content: screen map · 4 navigation items, 2 detail views\]

The four navigation items are always visible; Edit group and the run details panel are reached from Groups and Activity. The Automation job opens in the Azure portal for deep debugging.

## Screens

Five screens behind a left navigation (Groups, Activity, Audit, Settings); Edit group opens from the Groups list. Readers see the same screens with every edit control hidden.

**Groups** (start page)

- Table: name, type, target group, frequency, last result (badge), members, added/removed last run, last sync.
- Filters: type, result, enabled; search by name; a "Needs attention" quick filter (Blocked, Error, waiting for approval).
- Header: counts per result and a banner when syncing is paused.
- Admin actions: New group; per row: Sync now, Disable/Enable.

**Edit group** (`/groups/{id}`, also used for New)

- Basics: name, group type, target (create new, pick existing, or adopt), frequency, enabled.
- Rule: rule editor, plus includes and excludes (people pickers), IncludeDisabled and IncludeGuests switches.
- Safety: change limit override, AllowEmpty.
- Preview panel: member count, first 200 members, excluded users with reason, diff to the target group, whether the change limit would block.
- Status panel: last result, last error, link to this group's runs.
- Admin actions: Save (dry run stays on until switched off), Sync now, Approve (when waiting), Delete.

**Activity**

- Latest runs across all groups, newest first: time, group, result, added, removed, skipped, warnings.
- A run opens a side panel with the added and removed users, warnings, error text and a link to the Automation job.

**Audit**

- Every change: when, who, action, group, and the changed fields as old → new. Filters by group, person and date.

**Settings** (admin only for changes)

- Pause all syncing, verbose logging, change limit default, nested members, frequency options, naming prefix/suffix, marker attribute, audit retention (days).

## Rule editor

The rule editor is a CodeMirror 6 field that feels like the Entra rule text box, plus live feedback.

- **Highlighting:** properties, operators, strings, `null`, lists, parentheses in distinct colours (a small custom grammar, not the full engine parser).
- **Live check:** 400 ms after typing stops, the editor sends the rule to `/api/rules/validate`; errors appear as red underlines at the returned position and in a list below the editor.
- **Autocomplete:** after `user.` the list of supported properties; after a property the operators allowed for its type; inside `group.objectId -in [...]` a group search.
- **Group IDs readable:** group IDs in memberOf show the group name as a hint next to the line.
- **Paste from Entra:** pasting an existing Entra rule works as is; a "Copy from Entra group" button comes in a later version.
- **Read-only for readers.**

## Pickers

Two pickers, both Fluent v9 TagPicker with async search against the API.

| Picker | Used for | Search | Shows |
| --- | --- | --- | --- |
| People | Includes, excludes | `/api/directory/users`, from 2 characters, 300 ms debounce | Name, UPN, department; disabled and guest users marked |
| Groups | Target, adopt, memberOf | `/api/directory/groups` | Name, type (Security, M365, mail-enabled, distribution), "on-prem synced" and "managed by this tool" badges |

Groups that cannot be a target (on-prem synced, role-assignable, already linked to another definition) stay visible but disabled, with the reason as a tooltip.

## States

Every screen handles these states the same way, so nothing ever shows a blank page or a raw error.

| State | What the user sees |
| --- | --- |
| Loading | Skeleton rows in tables, spinner on buttons; never a blank page |
| Empty | Groups: "No groups yet" with a New group button (admins) and a link to the rule reference; Activity: "No runs yet" |
| Error | Message bar with the problem title and detail from the API; field errors next to the field; 500 errors show the correlation ID to copy |
| Conflict (412) | Dialog: "Changed by X at 14:02" with Reload or Show differences; local edits are kept until the user decides |
| Unsaved changes | Leaving Edit group with changes asks for confirmation |
| Paused | Yellow banner on every page: "Syncing is paused since 10:15 by X" with a Resume button for admins |
| Sync running | After Sync now the status panel shows "Requested…", then the result; polling every 5 seconds, stops after 5 minutes |
| Session expired | Redirect to sign-in, then back to the same page |

## Architecture

- **Hosting:** static files in the Static Web App; `staticwebapp.config.json` holds route rules (roles per path), navigation fallback to index.html for deep links, and security headers (Content-Security-Policy, no framing).
- **Sign-in:** `/.auth/login/aad`; the app reads the user and roles from `/api/me` on start and keeps them in a React context; role checks only hide controls, the API enforces them.
- **Data:** one typed API client generated from the OpenAPI file; TanStack Query per resource (definitions, runs, audit, settings), ETag kept with each cached definition and sent as If-Match on save.
- **No secrets in the browser:** no tokens handled in JavaScript; the Static Web App's session cookie carries the sign-in.
- **Configuration:** none at build time except the version; everything else comes from the API.

## Quality and structure

- **Accessibility:** Fluent components are keyboard and screen-reader ready; status badges always carry text, never colour alone.
- **Language:** English only; no translations planned, since the audience is admins. Strings still live in one file, which keeps wording consistent.
- **Theme:** light and dark follow the operating system, using Fluent's web light and dark themes.
- **Layout:** desktop first (1280 px and up); usable on a tablet; no phone layout in the MVP.
- **Tests:** Vitest and Testing Library for components; Playwright end-to-end tests against a mocked API (MSW) for the main flows: create group, preview, save, conflict, approve, pause.

```text
src/Web/
  staticwebapp.config.json
  src/
    api/          generated client and types, query hooks
    auth/         user and role context
    components/   RuleEditor, PeoplePicker, GroupPicker, StatusBadge, PreviewPanel
    pages/        Groups, EditGroup, Activity, Audit, Settings
    strings/      en.json
  tests/          unit, e2e, mocks
```

## Additions after component design

- **Read-only installation:** a permanent banner "Read-only installation: nothing is changed in the tenant". Approve buttons are disabled with a tooltip explaining why.
- **Compare group:** an optional group picker on Edit group. The group page gets a "Comparison" card with two lists, "only in RDG" and "only in compare group", and a green state when both are empty.
- **Adopting a Microsoft dynamic group:** the adopt screen marks it as "Dynamic (Microsoft)", pre-fills the rule from it, and the approval dialog says the group will be switched to assigned membership.

## Implementation notes (Phase 4)

The app in `src/Web` covers all 14 mockup screens and runs without a tenant on an in-browser mock API (`npm run dev:mock`). Choices made while building it:

| Topic | What was done |
| --- | --- |
| Mock API | MSW handlers in `src/mocks` follow `openapi.yaml`: roles, If-Match (428/412 with who changed it), problems with correlation IDs, paging, 409 on delete with referencedBy. A simulated engine handles Sync now and approvals after a short delay; a small rule evaluator gives plausible previews. Scenarios via URL: `?mockRole=reader`, `mockPaused`, `mockReadOnly`, `mockEmpty`. Invented contoso.org data only. |
| Names of users and groups | Definitions store only IDs. `GET /definitions/{id}` now also returns `includeUsers`, `excludeUsers` and `compareGroup` (read-only, one Graph `directoryObjects/getByIds` call); without them the app shows the IDs. Writes return the definition without names, so the form keeps the names it has. Target groups chosen in the picker send their display name in `target.displayName`; the list shows it. |
| Rule editor | CodeMirror 6 with RDG's own tokenizer for colours, autocomplete from `src/rules/properties.json` (generated from the engine by `tools/Export-RuleProperties.ps1`, a Pester test keeps it current) and operators per property type. Validity is decided only by `POST /rules/validate`, 400 ms after typing stops; errors are underlined at their position and a suggestion is a link that fixes the text. memberOf groups show which definition manages them. |
| Target group | The segmented switch is locked once the engine created the group (create) or an adoption was approved. For existing and adopt the group type follows the chosen group. Rename on adopt shows the result as prefix + current group name + suffix, which is what the engine does (the mockup showed the definition name). A Microsoft dynamic group fills an empty rule with its membership rule. |
| Delete | The dialog lists definitions whose rules reference the group (from the list, or the API's 409) and says those rules keep working because they read the group live; confirming with the name deletes with `force=true`. |
| Conflicts | Every save sends If-Match. A 412 loads the saved version and shows the fields that differ; "Reload latest version" replaces the form, overwriting is not offered. The same applies to Settings. Leaving a page with unsaved changes asks first. |
| Sync now | After 202 the app polls the definitions every 3 s until `status.handledSyncRequestAt` reaches `requestedAt` (gives up after 10 minutes) and shows "Syncing…" meanwhile. |
| Sign-in and roles | `/api/me` on start; a 401 or a redirect from the Static Web App sends the browser to `/.auth/login/aad`; 403 or no role shows Access denied with the name from `/.auth/me`. Readers see the reader view, disabled Settings and no write buttons. |
| Hosting | `public/staticwebapp.config.json`: custom Entra provider with `rolesSource /api/roles` (`__TENANT_ID__` is replaced at deployment), `/api/health` anonymous, everything else signed in, navigation fallback, CSP with `script-src 'self'` (styles need `'unsafe-inline'` for Fluent UI's runtime CSS). The production build contains no mock code; the group page (CodeMirror) loads on first use. |
| Quality | TypeScript strict, ESLint (typescript-eslint strict, hooks rules), Prettier, all texts in `src/strings/en.ts`. 47 Vitest tests (helpers, editor, mock API rules, whole-app flows in jsdom, contract types current, SWA config) and 16 Playwright flows against the mock build; CI job `web`. |
| Dependencies | Exact versions at least two weeks old; React 18 and react-router 6 on purpose. npm 10 crashes resolving vitest's optional peers, so `.npmrc` sets `legacy-peer-deps` and the peers are listed explicitly. |

## Open questions

- [x] UI language: English only; no multi-language support planned.
- [x] Copy from Entra group: later version.
- [x] Branding: fixed in the MVP.

## Later versions

- **Visual rule builder:** click conditions together (property, operator, value, and/or groups) instead of typing; it writes the same rule text, so both views stay interchangeable.
- **Copy from Entra group:** load the rule of an existing Entra dynamic group into the editor (one more API endpoint, Group.Read.All for "api").
- **Branding:** own logo and product name per organisation.
- **AI helper (far future):** describe a group in plain words and get a rule suggestion; the organisation connects its own AI endpoint and credentials, nothing built in.
