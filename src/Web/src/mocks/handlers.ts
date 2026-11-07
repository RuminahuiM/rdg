// Mock RDG API for `npm run dev:mock`, the e2e tests and the unit tests (MSW handlers).
// Follows openapi.yaml: roles, ETags (428/412), problems with correlation IDs, paging, and a
// simulated engine that handles Sync now and approvals a moment later.
import { delay, http, HttpResponse, type HttpHandler } from 'msw';
import type {
  AuditEntry,
  Definition,
  DefinitionInput,
  DirectoryGroup,
  PreviewResult,
  Problem,
  Run,
  RuleValidationResult,
  Settings,
  SettingsInput,
  UserRef,
} from '../api/types';
import { ADMIN_UPN, READER_UPN, createData, type MockData, type MockGroup } from './data';
import { checkRule, type MockUser } from './evaluate';
import { desiredMembers as engineDesired, diffHash, type DesiredInput } from './engine';

export interface Scenario {
  role: 'admin' | 'reader' | 'none' | 'signedOut';
  readOnly: boolean;
  paused: boolean;
  empty: boolean;
  /** Milliseconds before the simulated engine handles Sync now and approvals. */
  engineDelayMs: number;
}

export const defaultScenario: Scenario = { role: 'admin', readOnly: false, paused: false, empty: false, engineDelayMs: 2500 };

export interface MockApi {
  data: MockData;
  scenario: Scenario;
  handlers: HttpHandler[];
  /** Simulates another admin saving a definition (for the conflict dialog). */
  touch: (id: string, change: Partial<DefinitionInput>, by?: string) => void;
  /** Answers the next `times` requests to `path` with this status (error page tests). */
  failNext: (path: string, status: number, times?: number) => void;
  reset: (scenario?: Partial<Scenario>) => void;
}

let counter = 0;
const uuid = () => {
  counter += 1;
  return `4f2a9c1e-7b3d-4e11-9a0c-${counter.toString(16).padStart(12, '0')}`;
};
const nowIso = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const newEtag = () => `"${uuid()}"`;

function problem(status: number, title: string, extra: Partial<Problem> = {}) {
  const body: Problem = {
    type: `https://rdg.invalid/problems/${title.toLowerCase().replace(/[^a-z]+/g, '-')}`,
    title,
    status,
    correlationId: uuid(),
    ...extra,
  };
  return HttpResponse.json(body, { status, headers: { 'Content-Type': 'application/problem+json' } });
}

const crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
function newDefinitionId(): string {
  let text = '';
  for (let i = 0; i < 26; i += 1) text += crockford.charAt(Math.floor(Math.random() * 32));
  return `def-${text}`;
}

function page<T>(items: T[], token: string | null): { items: T[]; continuationToken: string | null } {
  const start = token ? Number.parseInt(token, 10) || 0 : 0;
  const slice = items.slice(start, start + 50);
  return { items: slice, continuationToken: start + 50 < items.length ? String(start + 50) : null };
}

export function createMockApi(initial: Partial<Scenario> = {}): MockApi {
  const scenario: Scenario = { ...defaultScenario, ...initial };
  let data = createData(new Date(), { empty: scenario.empty, paused: scenario.paused });
  const failures = new Map<string, { status: number; times: number }>();

  const upn = () => (scenario.role === 'reader' ? READER_UPN : ADMIN_UPN);
  const userRef = (user: MockUser): UserRef => ({ id: user.id, upn: user.userPrincipalName, displayName: user.displayName });
  const findUser = (id: string) => data.users.find((u) => u.id === id.toLowerCase());
  const findGroup = (id: string | null | undefined) => (id ? data.groups.find((g) => g.id === id.toLowerCase()) : undefined);
  const findDefinition = (id: string) => data.definitions.find((d) => d.id === id);

  function guard(request: Request, needAdmin: boolean): Response | null {
    const path = new URL(request.url).pathname;
    const failure = failures.get(path);
    if (failure) {
      if (failure.times <= 1) failures.delete(path);
      else failure.times -= 1;
      return problem(failure.status, failure.status === 500 ? 'Internal error' : 'Simulated failure');
    }
    if (scenario.role === 'signedOut') return problem(401, 'Not signed in');
    if (scenario.role === 'none') return problem(403, 'No role in this app');
    if (needAdmin && scenario.role !== 'admin') return problem(403, 'This needs the admin role');
    return null;
  }

  function audit(entry: Omit<AuditEntry, 'id' | 'at' | 'by'>) {
    data.audit.unshift({ id: `aud-${uuid()}`, at: nowIso(), by: upn(), ...entry });
  }

  /** Only GET /definitions/{id} adds names, as the real API does. */
  function withNames(definition: Definition): Definition {
    const compare = findGroup(definition.compareGroupId);
    return {
      ...definition,
      includeUsers: definition.includeUserIds
        .map(findUser)
        .filter((u): u is MockUser => Boolean(u))
        .map(userRef),
      excludeUsers: definition.excludeUserIds
        .map(findUser)
        .filter((u): u is MockUser => Boolean(u))
        .map(userRef),
      ...(compare ? { compareGroup: { id: compare.id, displayName: compare.displayName } } : {}),
    };
  }

  function toDirectoryGroup(group: MockGroup): DirectoryGroup {
    const owner = group.managedByDefinitionId ? findDefinition(group.managedByDefinitionId) : undefined;
    return {
      id: group.id,
      displayName: group.displayName,
      mail: group.mail,
      groupType: group.groupType,
      memberCount: group.members.length,
      isDynamic: group.isDynamic,
      membershipRule: group.membershipRule,
      onPremisesSynced: group.onPremisesSynced,
      isAssignableToRole: group.isAssignableToRole,
      managedByDefinitionId: owner ? owner.id : null,
      linkedToName: owner ? owner.name : null,
    };
  }

  /** Checks a definition body roughly as the API does; returns field errors. */
  function validateInput(input: DefinitionInput, selfId?: string) {
    const errors: { field: string; message: string; position?: number; line?: number; column?: number }[] = [];
    if (!input.name?.trim()) errors.push({ field: 'name', message: 'enter a name' });
    if (!input.rule?.trim()) errors.push({ field: 'rule', message: 'enter a rule' });
    else {
      const check = checkRule(input.rule);
      for (const e of check.errors)
        errors.push({ field: 'rule', message: e.message, position: e.position, line: e.line, column: e.column });
      for (const id of check.groupIds)
        if (!findGroup(id)) errors.push({ field: 'rule', message: `the memberOf group ${id} doesn't exist` });
    }
    const target = input.target;
    if (target.mode === 'create') {
      if (!target.displayName?.trim()) errors.push({ field: 'target.displayName', message: 'enter a name for the new group' });
    } else {
      const group = findGroup(target.groupId);
      if (!group) errors.push({ field: 'target.groupId', message: `the group ${target.groupId ?? ''} doesn't exist` });
      else {
        if (group.onPremisesSynced)
          errors.push({ field: 'target.groupId', message: 'the group is synced from on-premises AD; RDG cannot manage it' });
        if (group.isAssignableToRole)
          errors.push({ field: 'target.groupId', message: 'the group is role-assignable; RDG does not manage those' });
        if (group.groupType !== input.groupType)
          errors.push({ field: 'groupType', message: `the group is a ${group.groupType} group, not ${input.groupType}` });
        if (group.isDynamic && target.mode !== 'adopt')
          errors.push({ field: 'target.mode', message: 'the group has dynamic membership; adopt it to let RDG take it over' });
      }
    }
    if (input.compareGroupId && !findGroup(input.compareGroupId))
      errors.push({ field: 'compareGroupId', message: "the compare group doesn't exist" });
    const owner = target.groupId
      ? data.definitions.find((d) => d.id !== selfId && d.target.groupId === target.groupId?.toLowerCase())
      : undefined;
    return { errors, owner };
  }

  const desiredMembers = (definition: DesiredInput) => engineDesired(data.users, definition);

  function preview(definition: DefinitionInput & { compareGroupId?: string | null }, groupId: string | null | undefined): PreviewResult {
    const { members, excluded } = desiredMembers({
      rule: definition.rule,
      includeUserIds: definition.includeUserIds ?? [],
      excludeUserIds: definition.excludeUserIds ?? [],
      includeDisabled: definition.includeDisabled ?? false,
      includeGuests: definition.includeGuests ?? false,
      groupType: definition.groupType,
    });
    const memberIds = new Set(members.map((m) => m.id));
    const group = findGroup(groupId);
    const limitPercent = definition.changeLimitPercent ?? data.settings.changeLimitPercent;
    let diff: PreviewResult['diff'] = null;
    let changes = 0;
    let current = 0;
    if (group) {
      const currentIds = new Set(group.members);
      current = currentIds.size;
      const adds = members.filter((m) => !currentIds.has(m.id));
      const removes = group.members
        .filter((id) => !memberIds.has(id))
        .map(findUser)
        .filter((u): u is MockUser => Boolean(u));
      changes = adds.length + removes.length;
      diff = {
        addCount: adds.length,
        removeCount: removes.length,
        adds: adds.slice(0, 200).map(userRef),
        removes: removes.slice(0, 200).map(userRef),
      };
    }
    const percentValue = current > 0 ? (changes / current) * 100 : 0;
    const compareGroup = findGroup(definition.compareGroupId);
    let compare: PreviewResult['compare'] = null;
    if (compareGroup) {
      const other = new Set(compareGroup.members);
      const onlyInRdg = members.filter((m) => !other.has(m.id));
      const onlyInCompare = compareGroup.members
        .filter((id) => !memberIds.has(id))
        .map(findUser)
        .filter((u): u is MockUser => Boolean(u));
      compare = {
        onlyInRdgCount: onlyInRdg.length,
        onlyInCompareCount: onlyInCompare.length,
        onlyInRdg: onlyInRdg.slice(0, 200).map(userRef),
        onlyInCompare: onlyInCompare.slice(0, 200).map(userRef),
      };
    }
    return {
      memberCount: members.length,
      members: members.slice(0, 200).map(userRef),
      excluded: excluded.slice(0, 200),
      excludedCounts: {
        disabled: excluded.filter((e) => e.reason === 'disabled').length,
        guest: excluded.filter((e) => e.reason === 'guest').length,
        excludeList: excluded.filter((e) => e.reason === 'excludeList').length,
        noExchangeRecipient: excluded.filter((e) => e.reason === 'noExchangeRecipient').length,
      },
      emptyResult: {
        wouldBlock: Boolean(group) && members.length === 0 && current > 0 && !definition.allowEmpty,
        currentMembers: current,
        allowEmpty: Boolean(definition.allowEmpty),
      },
      diff,
      changeLimit: {
        wouldBlock:
          Boolean(group) &&
          changes >= data.settings.changeLimitMinChanges &&
          percentValue > limitPercent &&
          !(definition.target.mode === 'create'),
        percent: Math.round(percentValue * 10) / 10,
        limitPercent,
      },
      compare,
      warnings: [],
    };
  }

  /** The simulated engine: one run for a definition, as the runbook would do it. */
  function engineRun(definition: Definition, mode: 'Scheduled' | 'SyncNow', requestedAt?: string) {
    let group = findGroup(definition.target.groupId ?? definition.status?.groupId);
    if (!group && definition.target.mode === 'create') {
      const prefix = data.settings.naming.prefix.enabled ? data.settings.naming.prefix.text : '';
      const suffix = data.settings.naming.suffix.enabled ? data.settings.naming.suffix.text : '';
      group = {
        id: `0b7d2c1e-0000-4e3b-9c8d-${(500 + data.groups.length).toString().padStart(12, '0')}`,
        displayName: `${prefix}${definition.target.displayName ?? definition.name}${suffix}`,
        mail: null,
        groupType: definition.groupType,
        isDynamic: false,
        membershipRule: null,
        onPremisesSynced: false,
        isAssignableToRole: false,
        managedByDefinitionId: definition.id,
        members: [],
      };
      data.groups.push(group);
    }
    if (!group) return;
    const { members, excluded } = desiredMembers(definition);
    const memberIds = members.map((m) => m.id);
    const adds = memberIds.filter((id) => !group.members.includes(id));
    const removes = group.members.filter((id) => !memberIds.includes(id));
    const approved = definition.approval?.diffHash === diffHash(adds, removes);
    const pendingAdopt = definition.target.mode === 'adopt' && !definition.target.adopted;
    const dryRunReason = scenario.readOnly ? 'readOnly' : pendingAdopt && !approved ? 'adoption' : definition.dryRun ? 'definition' : null;
    const percentValue = group.members.length ? ((adds.length + removes.length) / group.members.length) * 100 : 0;
    const limit = definition.changeLimitPercent ?? data.settings.changeLimitPercent;
    const blocked =
      !dryRunReason &&
      !approved &&
      group.members.length > 0 &&
      adds.length + removes.length >= data.settings.changeLimitMinChanges &&
      percentValue > limit;
    const write = !dryRunReason && !blocked;
    const hash = diffHash(adds, removes);
    const result: Run['result'] = dryRunReason === 'adoption' ? 'WaitingForApproval' : dryRunReason ? 'DryRun' : blocked ? 'Blocked' : 'OK';
    if (write) {
      group.members = memberIds;
      if (definition.target.mode === 'adopt') {
        definition.target = { ...definition.target, adopted: true };
        group.isDynamic = false;
      }
    }
    const pendingApproval =
      result === 'Blocked' || result === 'WaitingForApproval'
        ? {
            kind: (result === 'Blocked' ? 'changeLimit' : 'adopt') as 'changeLimit' | 'adopt',
            diffHash: hash,
            adds: adds.length,
            removes: removes.length,
            percent: Math.round(percentValue * 10) / 10,
            detectedAt: nowIso(),
          }
        : null;
    const runId = `run-${uuid()}`;
    const toRefs = (list: string[]) =>
      list
        .map(findUser)
        .filter((u): u is MockUser => Boolean(u))
        .map(userRef);
    data.runs.unshift({
      id: runId,
      definitionId: definition.id,
      definitionName: definition.name,
      groupId: group.id,
      jobId: uuid(),
      runbook: ['MailEnabledSecurity', 'Distribution'].includes(definition.groupType) ? 'Exchange' : 'Entra',
      mode,
      startedAt: nowIso(),
      durationMs: 2400,
      engineVersion: '0.1.0',
      result,
      dryRun: Boolean(dryRunReason),
      dryRunReason,
      addedCount: write ? adds.length : 0,
      removedCount: write ? removes.length : 0,
      skippedCount: 0,
      added: toRefs(adds),
      removed: toRefs(removes),
      skipped: [],
      excluded: {
        disabled: excluded.filter((e) => e.reason === 'disabled').length,
        guests: excluded.filter((e) => e.reason === 'guest').length,
      },
      approval: pendingApproval,
      warnings: [],
      error: blocked ? 'Blocked by the change limit.' : null,
    });
    definition.status = {
      groupId: group.id,
      lastSyncUtc: nowIso(),
      lastResult: result,
      dryRunReason,
      memberCount: group.members.length,
      added: write ? adds.length : dryRunReason ? adds.length : 0,
      removed: write ? removes.length : dryRunReason ? removes.length : 0,
      skipped: 0,
      excluded: {
        disabled: excluded.filter((e) => e.reason === 'disabled').length,
        guests: excluded.filter((e) => e.reason === 'guest').length,
      },
      warnings: [],
      lastError: blocked
        ? `Blocked by the change limit: ${adds.length + removes.length} changes are ${Math.round(percentValue)} % of ${group.members.length} members (limit ${limit} %).`
        : null,
      lastRunId: runId,
      handledSyncRequestAt: requestedAt ?? definition.status?.handledSyncRequestAt ?? null,
      pendingApproval,
      manualChangeDetected: false,
      compare: null,
    };
    if (write && approved) definition.approval = null;
    group.managedByDefinitionId = definition.id;
  }

  function settingsBody(): Settings {
    return data.settings;
  }

  const api = '/api';
  const handlers: HttpHandler[] = [
    http.get('/.auth/me', () =>
      HttpResponse.json({
        clientPrincipal:
          scenario.role === 'signedOut' ? null : { userDetails: scenario.role === 'none' ? 'marco.rossi@contoso.org' : upn() },
      }),
    ),

    http.get(`${api}/me`, async ({ request }) => {
      await delay();
      if (scenario.role === 'none') return problem(403, 'No role in this app');
      const blocked = guard(request, false);
      if (blocked) return blocked;
      return HttpResponse.json({
        upn: upn(),
        roles: [scenario.role === 'admin' ? 'admin' : 'reader'],
        accessMode: scenario.readOnly ? 'read-only' : 'read-write',
        version: '0.1.0',
      });
    }),

    http.get(`${api}/definitions`, async ({ request }) => {
      await delay();
      const blocked = guard(request, false);
      if (blocked) return blocked;
      const url = new URL(request.url);
      const search = url.searchParams.get('search')?.toLowerCase();
      const groupType = url.searchParams.get('groupType');
      const result = url.searchParams.get('result');
      const enabled = url.searchParams.get('enabled');
      const items = data.definitions.filter(
        (d) =>
          (!search || d.name.toLowerCase().includes(search) || (d.target.displayName ?? '').toLowerCase().includes(search)) &&
          (!groupType || d.groupType === groupType) &&
          (!result || d.status?.lastResult === result) &&
          (enabled === null || String(d.enabled) === enabled),
      );
      return HttpResponse.json(page(items, url.searchParams.get('continuationToken')));
    }),

    http.post(`${api}/definitions`, async ({ request }) => {
      await delay();
      const blocked = guard(request, true);
      if (blocked) return blocked;
      const input = (await request.json()) as DefinitionInput;
      const { errors, owner } = validateInput(input);
      if (errors.length) return problem(400, 'The definition is not valid', { errors });
      if (owner) return problem(409, 'The group is already managed', { detail: `“${owner.name}” already manages this group.` });
      const at = nowIso();
      const group = findGroup(input.target.groupId);
      const definition: Definition = {
        id: newDefinitionId(),
        etag: newEtag(),
        name: input.name.trim(),
        groupType: input.groupType,
        target: {
          ...input.target,
          groupId: input.target.groupId?.toLowerCase(),
          ...(input.target.mode === 'adopt'
            ? { renameOnAdopt: Boolean(input.target.renameOnAdopt), convertFromDynamic: Boolean(group?.isDynamic), adopted: false }
            : {}),
        },
        rule: input.rule,
        includeUserIds: input.includeUserIds ?? [],
        excludeUserIds: input.excludeUserIds ?? [],
        includeDisabled: input.includeDisabled ?? false,
        includeGuests: input.includeGuests ?? false,
        frequencyMinutes: input.frequencyMinutes ?? 15,
        enabled: input.enabled ?? true,
        dryRun: input.dryRun ?? false,
        changeLimitPercent: input.changeLimitPercent ?? null,
        allowEmpty: input.allowEmpty ?? false,
        compareGroupId: input.compareGroupId ?? null,
        createdAt: at,
        createdBy: upn(),
        updatedAt: at,
        updatedBy: upn(),
        syncRequest: null,
        approval: null,
        status: null,
      };
      if (definition.target.mode === 'create') delete definition.target.groupId;
      data.definitions.push(definition);
      if (group) group.managedByDefinitionId = definition.id;
      audit({
        definitionId: definition.id,
        definitionName: definition.name,
        action: input.target.mode === 'adopt' ? 'adopt' : 'create',
        changes: Object.entries(input).map(([field, value]) => ({ field, old: null, new: value })),
      });
      return HttpResponse.json(definition, {
        status: 201,
        headers: { ETag: definition.etag, Location: `/api/definitions/${definition.id}` },
      });
    }),

    http.get(`${api}/definitions/:id`, async ({ request, params }) => {
      await delay();
      const blocked = guard(request, false);
      if (blocked) return blocked;
      const definition = findDefinition(String(params.id));
      if (!definition) return problem(404, 'Definition not found');
      return HttpResponse.json(withNames(definition), { headers: { ETag: definition.etag } });
    }),

    http.put(`${api}/definitions/:id`, async ({ request, params }) => {
      await delay();
      const blocked = guard(request, true);
      if (blocked) return blocked;
      const definition = findDefinition(String(params.id));
      if (!definition) return problem(404, 'Definition not found');
      const ifMatch = request.headers.get('If-Match');
      if (!ifMatch) return problem(428, 'If-Match is required');
      if (ifMatch !== definition.etag) {
        return problem(412, 'Changed by someone else', {
          current: { etag: definition.etag, updatedAt: definition.updatedAt, updatedBy: definition.updatedBy },
        });
      }
      const input = (await request.json()) as DefinitionInput;
      const { errors, owner } = validateInput(input, definition.id);
      if (errors.length) return problem(400, 'The definition is not valid', { errors });
      if (owner) return problem(409, 'The group is already managed', { detail: `“${owner.name}” already manages this group.` });
      const changes: AuditEntry['changes'] = [];
      const record = definition as unknown as Record<string, unknown>;
      for (const [field, value] of Object.entries(input)) {
        if (field === 'target') continue;
        if (JSON.stringify(record[field]) !== JSON.stringify(value)) changes.push({ field, old: record[field], new: value });
      }
      const target = { ...definition.target, ...input.target, groupId: input.target.groupId?.toLowerCase() ?? definition.target.groupId };
      if (
        JSON.stringify({ ...definition.target, adopted: undefined, convertFromDynamic: undefined }) !==
        JSON.stringify({ ...target, adopted: undefined, convertFromDynamic: undefined })
      ) {
        changes.push({ field: 'target', old: definition.target, new: target });
      }
      if (changes.length === 0) return HttpResponse.json(definition, { headers: { ETag: definition.etag } });
      Object.assign(definition, input, { target, etag: newEtag(), updatedAt: nowIso(), updatedBy: upn() });
      audit({ definitionId: definition.id, definitionName: definition.name, action: 'update', changes });
      return HttpResponse.json(definition, { headers: { ETag: definition.etag } });
    }),

    http.delete(`${api}/definitions/:id`, async ({ request, params }) => {
      await delay();
      const blocked = guard(request, true);
      if (blocked) return blocked;
      const definition = findDefinition(String(params.id));
      if (!definition) return problem(404, 'Definition not found');
      const ifMatch = request.headers.get('If-Match');
      if (!ifMatch) return problem(428, 'If-Match is required');
      if (ifMatch !== definition.etag)
        return problem(412, 'Changed by someone else', {
          current: { etag: definition.etag, updatedAt: definition.updatedAt, updatedBy: definition.updatedBy },
        });
      const groupId = definition.status?.groupId ?? definition.target.groupId;
      const referencedBy = groupId
        ? data.definitions
            .filter((d) => d.id !== definition.id && d.rule.toLowerCase().includes(groupId.toLowerCase()))
            .map((d) => ({ id: d.id, name: d.name }))
        : [];
      if (referencedBy.length && new URL(request.url).searchParams.get('force') !== 'true') {
        return problem(409, 'Other definitions reference this group', { referencedBy });
      }
      data.definitions = data.definitions.filter((d) => d.id !== definition.id);
      const group = findGroup(groupId);
      if (group) group.managedByDefinitionId = null;
      audit({ definitionId: definition.id, definitionName: definition.name, action: 'delete', changes: [] });
      return new HttpResponse(null, { status: 204 });
    }),

    http.post(`${api}/definitions/:id/sync`, async ({ request, params }) => {
      await delay();
      const blocked = guard(request, true);
      if (blocked) return blocked;
      const definition = findDefinition(String(params.id));
      if (!definition) return problem(404, 'Definition not found');
      const recent = definition.syncRequest && Date.now() - Date.parse(definition.syncRequest.at) < 60_000;
      if (recent && definition.syncRequest) {
        return HttpResponse.json({ requestedAt: definition.syncRequest.at, jobStarted: true, existingRequest: true }, { status: 202 });
      }
      const requestedAt = nowIso();
      definition.syncRequest = { at: requestedAt, by: upn() };
      audit({ definitionId: definition.id, definitionName: definition.name, action: 'syncNow', changes: [] });
      setTimeout(() => {
        const still = findDefinition(definition.id);
        if (still && !data.settings.paused) engineRun(still, 'SyncNow', requestedAt);
        else if (still?.status) still.status.handledSyncRequestAt = requestedAt;
      }, scenario.engineDelayMs);
      return HttpResponse.json({ requestedAt, jobStarted: true, jobId: uuid() }, { status: 202 });
    }),

    http.post(`${api}/definitions/:id/approve`, async ({ request, params }) => {
      await delay();
      const blocked = guard(request, true);
      if (blocked) return blocked;
      const definition = findDefinition(String(params.id));
      if (!definition) return problem(404, 'Definition not found');
      const body = (await request.json()) as { kind: 'changeLimit' | 'adopt'; diffHash: string };
      const pending = definition.status?.pendingApproval;
      if (scenario.readOnly) return problem(409, 'The installation is read-only');
      if (!pending || pending.diffHash !== body.diffHash || pending.kind !== body.kind)
        return problem(409, 'Nothing to approve', { detail: 'Nothing waits for approval, or the set of changes is different now.' });
      definition.approval = {
        kind: body.kind,
        diffHash: body.diffHash,
        adds: pending.adds,
        removes: pending.removes,
        by: upn(),
        at: nowIso(),
      };
      definition.etag = newEtag();
      audit({
        definitionId: definition.id,
        definitionName: definition.name,
        action: 'approve',
        changes: [
          {
            field: 'approval',
            old: null,
            new: { kind: body.kind, adds: pending.adds, removes: pending.removes, percent: pending.percent },
          },
        ],
      });
      setTimeout(() => {
        const still = findDefinition(definition.id);
        if (still && !data.settings.paused) {
          // The next run finds the same diff and writes it (the approval covers exactly that diff).
          engineRun(still, 'Scheduled');
        }
      }, scenario.engineDelayMs);
      return HttpResponse.json(definition, { headers: { ETag: definition.etag } });
    }),

    http.get(`${api}/definitions/:id/runs`, async ({ request, params }) => {
      await delay();
      const blocked = guard(request, false);
      if (blocked) return blocked;
      if (!findDefinition(String(params.id))) return problem(404, 'Definition not found');
      const url = new URL(request.url);
      return HttpResponse.json(
        page(
          data.runs.filter((r) => r.definitionId === params.id),
          url.searchParams.get('continuationToken'),
        ),
      );
    }),

    http.get(`${api}/runs`, async ({ request }) => {
      await delay();
      const blocked = guard(request, false);
      if (blocked) return blocked;
      const url = new URL(request.url);
      const result = url.searchParams.get('result');
      const runbook = url.searchParams.get('runbook');
      const since = url.searchParams.get('since');
      const items = data.runs
        .filter((r) => (!result || r.result === result) && (!runbook || r.runbook === runbook) && (!since || r.startedAt >= since))
        .sort((a, b) => b.startedAt.localeCompare(a.startedAt));
      return HttpResponse.json(page(items, url.searchParams.get('continuationToken')));
    }),

    http.post(`${api}/rules/validate`, async ({ request }) => {
      await delay(120);
      const blocked = guard(request, false);
      if (blocked) return blocked;
      const { rule } = (await request.json()) as { rule: string };
      const check = checkRule(rule);
      const unknown = check.groupIds.filter((id) => !findGroup(id));
      const body: RuleValidationResult = {
        valid: check.valid,
        errors: check.errors,
        referencedGroupIds: check.groupIds,
        unknownGroupIds: unknown,
      };
      return HttpResponse.json(body);
    }),

    http.post(`${api}/preview`, async ({ request }) => {
      await delay(400);
      const blocked = guard(request, false);
      if (blocked) return blocked;
      const body = (await request.json()) as { definitionId?: string; definition?: DefinitionInput };
      const stored = body.definitionId ? findDefinition(body.definitionId) : undefined;
      if (body.definitionId && !stored) return problem(404, 'Definition not found');
      if (stored && !body.definition) return HttpResponse.json(preview(stored, stored.status?.groupId ?? stored.target.groupId));
      if (!body.definition) return problem(400, 'definitionId or definition is required');
      const check = checkRule(body.definition.rule ?? '');
      if (!check.valid)
        return problem(400, 'The rule is not valid', { errors: check.errors.map((e) => ({ field: 'definition.rule', ...e })) });
      // Edited, unsaved version of a saved definition: it keeps the saved one's created group.
      const groupId = body.definition.target.groupId ?? stored?.status?.groupId;
      return HttpResponse.json(preview(body.definition, groupId));
    }),

    http.get(`${api}/settings`, async ({ request }) => {
      await delay();
      const blocked = guard(request, false);
      if (blocked) return blocked;
      return HttpResponse.json(settingsBody(), { headers: { ETag: data.settings.etag } });
    }),

    http.put(`${api}/settings`, async ({ request }) => {
      await delay();
      const blocked = guard(request, true);
      if (blocked) return blocked;
      const ifMatch = request.headers.get('If-Match');
      if (!ifMatch) return problem(428, 'If-Match is required');
      if (ifMatch !== data.settings.etag) {
        return problem(412, 'Changed by someone else', {
          current: {
            etag: data.settings.etag,
            updatedAt: data.settings.updatedAt ?? undefined,
            updatedBy: data.settings.updatedBy ?? undefined,
          },
        });
      }
      const input = (await request.json()) as SettingsInput;
      const changes: AuditEntry['changes'] = [];
      const current = data.settings as unknown as Record<string, unknown>;
      for (const [field, value] of Object.entries(input)) {
        if (JSON.stringify(current[field]) !== JSON.stringify(value)) changes.push({ field, old: current[field], new: value });
      }
      const at = nowIso();
      const pausedChanged = input.paused !== data.settings.paused;
      data.settings = {
        ...input,
        etag: newEtag(),
        pausedAt: input.paused ? (pausedChanged ? at : data.settings.pausedAt) : null,
        pausedBy: input.paused ? (pausedChanged ? upn() : data.settings.pausedBy) : null,
        updatedAt: at,
        updatedBy: upn(),
      };
      if (changes.length) audit({ definitionId: null, definitionName: '', action: 'settings', changes });
      return HttpResponse.json(settingsBody(), { headers: { ETag: data.settings.etag } });
    }),

    http.get(`${api}/audit`, async ({ request }) => {
      await delay();
      const blocked = guard(request, false);
      if (blocked) return blocked;
      const url = new URL(request.url);
      const definitionId = url.searchParams.get('definitionId');
      const by = url.searchParams.get('by')?.toLowerCase();
      const from = url.searchParams.get('from');
      const to = url.searchParams.get('to');
      const items = data.audit
        .filter(
          (e) =>
            (!definitionId || e.definitionId === definitionId) &&
            (!by || e.by.toLowerCase().startsWith(by)) &&
            (!from || e.at >= from) &&
            (!to || e.at <= to),
        )
        .sort((a, b) => b.at.localeCompare(a.at));
      return HttpResponse.json(page(items, url.searchParams.get('continuationToken')));
    }),

    http.get(`${api}/directory/users`, async ({ request }) => {
      await delay(150);
      const blocked = guard(request, false);
      if (blocked) return blocked;
      const search = new URL(request.url).searchParams.get('search') ?? '';
      if (search.length < 2) return problem(400, 'search needs at least 2 characters');
      const text = search.toLowerCase();
      const items = data.users
        .filter(
          (u) =>
            u.displayName.toLowerCase().startsWith(text) ||
            u.userPrincipalName.toLowerCase().startsWith(text) ||
            (u.mail ?? '').toLowerCase().startsWith(text) ||
            u.displayName
              .toLowerCase()
              .split(' ')
              .some((part) => part.startsWith(text)),
        )
        .slice(0, 25)
        .map((u) => ({
          id: u.id,
          upn: u.userPrincipalName,
          displayName: u.displayName,
          mail: u.mail,
          accountEnabled: u.accountEnabled,
          userType: u.userType,
        }));
      return HttpResponse.json({ items });
    }),

    http.get(`${api}/directory/groups`, async ({ request }) => {
      await delay(150);
      const blocked = guard(request, false);
      if (blocked) return blocked;
      const search = new URL(request.url).searchParams.get('search') ?? '';
      if (search.length < 2) return problem(400, 'search needs at least 2 characters');
      const text = search.toLowerCase();
      const items = data.groups
        // Word prefix, like Graph $search on displayName ("board" finds MESG-Board).
        .filter(
          (g) =>
            g.displayName
              .toLowerCase()
              .split(/[^a-z0-9äöü]+/)
              .some((word) => word.startsWith(text)) ||
            g.displayName.toLowerCase().startsWith(text) ||
            (g.mail ?? '').toLowerCase().startsWith(text),
        )
        .slice(0, 25)
        .map(toDirectoryGroup);
      return HttpResponse.json({ items });
    }),
  ];

  const mock: MockApi = {
    get data() {
      return data;
    },
    scenario,
    handlers,
    touch(id, change, by = 'lea.keller@contoso.org') {
      const definition = findDefinition(id);
      if (!definition) return;
      Object.assign(definition, change, { etag: newEtag(), updatedAt: nowIso(), updatedBy: by });
    },
    failNext(path, status, times = 1) {
      failures.set(path, { status, times });
    },
    reset(next = {}) {
      Object.assign(scenario, next);
      data = createData(new Date(), { empty: scenario.empty, paused: scenario.paused });
    },
  };
  return mock;
}
