// Invented contoso.org tenant for the mock API: users, groups, definitions, runs, audit.
// Deterministic (seeded) so tests and screenshots are stable. No real data.
import type { AuditEntry, Definition, DirectoryGroup, GroupType, Run, Settings, UserRef } from '../api/types';
import type { MockUser } from './evaluate';
import { desiredMembers, diffHash, diffOf } from './engine';

export interface MockGroup extends Omit<DirectoryGroup, 'memberCount' | 'linkedToName'> {
  members: string[];
}

export interface MockData {
  users: MockUser[];
  groups: MockGroup[];
  definitions: Definition[];
  runs: Run[];
  audit: AuditEntry[];
  settings: Settings;
}

function rng(seed: number) {
  let state = seed;
  return () => {
    state = (state * 1664525 + 1013904223) % 4294967296;
    return state / 4294967296;
  };
}

const firstNames = [
  'Lea',
  'Marco',
  'Anna',
  'Peter',
  'Nina',
  'Tom',
  'Sara',
  'Jonas',
  'Elif',
  'Luca',
  'Mia',
  'Noah',
  'Laura',
  'David',
  'Sofia',
  'Jan',
  'Lena',
  'Felix',
  'Clara',
  'Leon',
  'Emma',
  'Ben',
  'Julia',
  'Elias',
  'Nora',
  'Samuel',
  'Alina',
  'Tim',
];
const lastNames = [
  'Keller',
  'Rossi',
  'Weber',
  'Graf',
  'Frei',
  'Bachmann',
  'Meier',
  'Huber',
  'Kaya',
  'Brunner',
  'Fischer',
  'Baumann',
  'Steiner',
  'Moser',
  'Wyss',
  'Gerber',
  'Roth',
  'Suter',
  'Widmer',
  'Zimmermann',
  'Schmid',
  'Lehmann',
  'Marti',
  'Frey',
];
const departments = [
  'Finance',
  'IT',
  'Programmes',
  'Projects South',
  'Projects East',
  'Communication',
  'HR',
  'Fundraising',
  'Field Operations',
];
const cities = ['Zürich', 'Bern', 'Lausanne', 'Geneva', 'Basel'];

export const ids = {
  user: (n: number) => `7e21a3b4-0000-4e7f-8a9b-${n.toString().padStart(12, '0')}`,
  group: (n: number) => `0b7d2c1e-0000-4e3b-9c8d-${n.toString().padStart(12, '0')}`,
  job: (n: number) => `5f0c9a2e-0000-4d1b-8e3f-${n.toString().padStart(12, '0')}`,
  definition: (n: number) =>
    `def-01JA7K3M9QXR4T6V8W0Y2Z${n
      .toString()
      .padStart(4, '0')
      .replace(/[ILOU]/g, 'X')}`,
};

/** Definition IDs must match ^def-[0-9A-HJKMNP-TV-Z]{26}$. */
function definitionId(n: number): string {
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  let text = '';
  let value = n;
  for (let i = 0; i < 4; i += 1) {
    text = alphabet.charAt(value % 32) + text;
    value = Math.floor(value / 32);
  }
  return `def-01JA7K3M9QXR4T6V8W0Y2Z${text}`;
}

export const ADMIN_UPN = 'alex.example@contoso.org';
export const OTHER_ADMIN_UPN = 'lea.keller@contoso.org';
export const READER_UPN = 'sam.sample@contoso.org';

function iso(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export function createData(now: Date = new Date(), options: { empty?: boolean; paused?: boolean } = {}): MockData {
  const random = rng(42);
  const pick = <T>(list: T[]): T => list[Math.floor(random() * list.length)] as T;

  // The last quarter-hour tick, like the engine's schedule.
  const tick = new Date(now);
  tick.setSeconds(0, 0);
  tick.setMinutes(tick.getMinutes() - (tick.getMinutes() % 15));
  const minutesAgo = (m: number) => iso(new Date(tick.getTime() - m * 60_000));

  // Users
  const users: MockUser[] = [];
  for (let n = 1; n <= 360; n += 1) {
    const first = firstNames[(n - 1) % firstNames.length] ?? 'Alex';
    const last = lastNames[Math.floor((n - 1) / firstNames.length) % lastNames.length] ?? 'Example';
    const suffix = n > firstNames.length * lastNames.length ? String(n) : '';
    const upn = `${first.toLowerCase()}.${last.toLowerCase()}${suffix}@contoso.org`;
    const guest = n % 41 === 0;
    const department = n <= 64 ? 'Projects South' : pick(departments);
    users.push({
      id: ids.user(n),
      displayName: guest ? `${first} ${last} (Partner)` : `${first} ${last}`,
      userPrincipalName: guest ? `${first.toLowerCase()}_partner.org#EXT#@contoso.org` : upn,
      mail: n % 53 === 0 ? null : guest ? `${first.toLowerCase()}@partner.org` : upn,
      accountEnabled: n % 37 !== 0,
      userType: guest ? 'Guest' : 'Member',
      department,
      city: n <= 318 ? 'Zürich' : pick(cities),
      usageLocation: n <= 64 ? (n % 2 ? 'CH' : 'IT') : 'CH',
      country: 'Switzerland',
      jobTitle: department === 'IT' ? 'Engineer' : 'Officer',
      companyName: 'Contoso Aid',
      extensionAttribute3: n <= 42 ? (['STIFTRAT', 'DIR1', 'DIR2', 'KOM', 'GPK'][n % 5] ?? 'KOM') : n <= 50 ? 'SRV' : '',
      extensionAttribute5: n > 200 && n <= 350 ? (n % 2 ? 'FIELD-OPS' : 'FIELD-LOG') : n <= 88 ? 'FIELD' : '',
      memberOf: [],
    });
  }
  // A few named people used in the mockups.
  const named = (n: number, displayName: string, upn: string) => {
    const user = users[n - 1];
    if (user) Object.assign(user, { displayName, userPrincipalName: upn, mail: upn });
  };
  named(1, 'Lea Keller', OTHER_ADMIN_UPN);
  named(2, 'Marco Rossi', 'marco.rossi@contoso.org');
  named(3, 'Alex Example', ADMIN_UPN);
  named(4, 'Sam Sample', READER_UPN);
  users.push({
    id: ids.user(900),
    displayName: 'svc-backup',
    userPrincipalName: 'svc-backup@contoso.org',
    mail: null,
    accountEnabled: true,
    userType: 'Member',
    department: 'IT',
    city: 'Zürich',
    usageLocation: 'CH',
    extensionAttribute3: 'SRV',
    memberOf: [],
  });

  const ref = (user: MockUser): UserRef => ({ id: user.id, upn: user.userPrincipalName, displayName: user.displayName });
  const userAt = (n: number) => users[n - 1] as MockUser;

  // Groups. Members are lists of user IDs; definitions' statuses agree with them.
  const group = (n: number, displayName: string, groupType: GroupType | 'Other', extra: Partial<MockGroup> = {}): MockGroup => ({
    id: ids.group(n),
    displayName,
    mail: groupType === 'Security' ? null : `${displayName.toLowerCase().replace(/[^a-z0-9]+/g, '-')}@contoso.org`,
    groupType,
    isDynamic: false,
    membershipRule: null,
    onPremisesSynced: false,
    isAssignableToRole: false,
    managedByDefinitionId: null,
    members: [],
    ...extra,
  });
  const range = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => ids.user(from + i));

  const intuneRule = 'user.extensionAttribute5 -startsWith "FIELD"';
  const boardRule = 'user.extensionAttribute3 -in ["STIFTRAT","DIR1"]';
  // The hand-kept board group: one member missing, three that no longer match.
  const boardWanted = desiredMembers(users, {
    rule: boardRule,
    groupType: 'MailEnabledSecurity',
    includeUserIds: [],
    excludeUserIds: [],
    includeDisabled: false,
    includeGuests: false,
  }).members.map((u) => u.id);
  const boardMembers = [...boardWanted.slice(1), ids.user(17), ids.user(41), ids.user(330)];

  const groups: MockGroup[] = [
    group(1, 'MESG-EOP-Strict', 'MailEnabledSecurity', { members: range(1, 42) }),
    group(2, 'SG-Staff-ZH', 'Security', { members: range(1, 318) }),
    group(3, 'DL-Finance', 'Distribution', { members: range(100, 126) }),
    group(4, 'SG-Intune-Field', 'Security', {
      members: users
        .filter((u) => /^FIELD-/.test(String(u.extensionAttribute5)) && u.accountEnabled && u.userType === 'Member')
        .map((u) => u.id),
    }),
    group(5, 'M365-Country-Offices', 'Microsoft365', { members: range(120, 273) }),
    group(6, 'MESG-Board', 'MailEnabledSecurity', { members: boardMembers }),
    group(7, 'DG-Project Teams South', 'Security', { members: [] }),
    group(8, 'SG-SVC', 'Security', { members: [...range(43, 50), ids.user(900)] }),
    group(9, 'MESG-Board-Assistants', 'MailEnabledSecurity', { members: range(16, 19) }),
    group(10, 'SG-Management-Board', 'Security', { members: range(1, 8) }),
    group(20, 'SG-Board-OnPrem', 'Security', { onPremisesSynced: true, members: range(5, 17) }),
    group(21, 'SG-Board-Admins', 'Security', { isAssignableToRole: true, members: range(3, 4) }),
    group(22, 'DYN-Sales-Europe', 'Security', {
      isDynamic: true,
      membershipRule: '(user.department -eq "Fundraising") -and (user.usageLocation -in ["CH","IT"])',
      members: range(60, 90),
    }),
    group(23, 'SG-Helpdesk', 'Security', { members: range(30, 39) }),
    group(24, 'DL-All-Communication', 'Distribution', { members: range(70, 95) }),
  ];
  for (const g of groups) {
    for (const member of g.members) users.find((u) => u.id === member)?.memberOf.push(g.id);
  }
  // Pending approvals agree with what the simulated engine computes for these rules.
  const pendingFor = (rule: string, groupType: GroupType, groupNumber: number) => {
    const current = groups.find((g) => g.id === ids.group(groupNumber))?.members ?? [];
    const desired = desiredMembers(users, {
      rule,
      groupType,
      includeUserIds: [],
      excludeUserIds: [],
      includeDisabled: false,
      includeGuests: false,
    });
    const diff = diffOf(
      current,
      desired.members.map((u) => u.id),
    );
    const percent = current.length ? Math.round(((diff.adds.length + diff.removes.length) / current.length) * 1000) / 10 : 0;
    return { ...diff, current: current.length, percent, hash: diffHash(diff.adds, diff.removes), excluded: desired.excluded };
  };
  const intunePlan = pendingFor(intuneRule, 'Security', 4);
  const boardPlan = pendingFor(boardRule, 'MailEnabledSecurity', 6);
  const groupOf = (n: number) => groups.find((g) => g.id === ids.group(n)) as MockGroup;

  const base = (n: number, fields: Partial<Definition> & Pick<Definition, 'name' | 'groupType' | 'target' | 'rule'>): Definition => ({
    id: definitionId(n),
    etag: `"0000${n.toString(16)}a1-0000-0d00-0000-${(670000000000 + n).toString()}"`,
    includeUserIds: [],
    excludeUserIds: [],
    includeDisabled: false,
    includeGuests: false,
    frequencyMinutes: 60,
    enabled: true,
    dryRun: false,
    changeLimitPercent: null,
    allowEmpty: false,
    compareGroupId: null,
    createdAt: minutesAgo(60 * 24 * 6 + 88),
    createdBy: ADMIN_UPN,
    updatedAt: minutesAgo(60 * 24 * 6 + 88),
    updatedBy: ADMIN_UPN,
    syncRequest: null,
    approval: null,
    status: null,
    ...fields,
  });
  const status = (fields: Partial<NonNullable<Definition['status']>> & { lastSyncUtc: string }) => ({
    groupId: null,
    lastResult: 'OK' as const,
    dryRunReason: null,
    memberCount: 0,
    added: 0,
    removed: 0,
    skipped: 0,
    excluded: { disabled: 0, guests: 0 },
    warnings: [],
    lastError: null,
    lastRunId: null,
    handledSyncRequestAt: null,
    pendingApproval: null,
    manualChangeDetected: false,
    compare: null,
    ...fields,
  });
  const hash = (c: string) => `sha256:${c.repeat(64)}`;

  const definitions: Definition[] = [
    base(1, {
      name: 'EOP Strict – Management',
      groupType: 'MailEnabledSecurity',
      target: { mode: 'existing', groupId: ids.group(1), displayName: 'MESG-EOP-Strict' },
      rule: `(user.extensionAttribute3 -in ["STIFTRAT","DIR1","DIR2","KOM","GPK"]) -or\n(user.extensionAttribute3 -startsWith "SRV") -or\n(user.memberof -any (group.objectId -in ['${ids.group(10)}']))`,
      frequencyMinutes: 15,
      includeUserIds: [ids.user(1)],
      excludeUserIds: [ids.user(900)],
      createdAt: minutesAgo(60 * 24 * 6 + 88),
      updatedAt: minutesAgo(60 * 24 * 3),
      updatedBy: OTHER_ADMIN_UPN,
      status: status({
        groupId: ids.group(1),
        lastSyncUtc: minutesAgo(0),
        memberCount: 42,
        added: 1,
        excluded: { disabled: 2, guests: 1 },
        lastRunId: 'run-1-0',
      }),
    }),
    base(2, {
      name: 'All Staff Zürich',
      groupType: 'Security',
      target: { mode: 'existing', groupId: ids.group(2), displayName: 'SG-Staff-ZH' },
      rule: `(user.city -eq "Zürich") -and (user.userType -eq "Member") -and -not (user.memberof -any (group.objectId -in ['${ids.group(8)}']))`,
      approval: { kind: 'changeLimit', diffHash: hash('b'), adds: 41, removes: 0, by: ADMIN_UPN, at: minutesAgo(60 * 24 * 5 + 30) },
      status: status({ groupId: ids.group(2), lastSyncUtc: minutesAgo(15), memberCount: 318, added: 2, removed: 1, lastRunId: 'run-2-0' }),
    }),
    base(3, {
      name: 'Finance – Distribution',
      groupType: 'Distribution',
      target: { mode: 'existing', groupId: ids.group(3), displayName: 'DL-Finance' },
      rule: 'user.department -eq "Finance"',
      status: status({
        groupId: ids.group(3),
        lastSyncUtc: minutesAgo(15),
        lastResult: 'Warning',
        memberCount: 27,
        skipped: 3,
        warnings: ['3 users have no Exchange recipient and were skipped.'],
        lastRunId: 'run-3-0',
      }),
    }),
    base(4, {
      name: 'Intune – Field Laptops',
      groupType: 'Security',
      target: { mode: 'existing', groupId: ids.group(4), displayName: 'SG-Intune-Field' },
      rule: intuneRule,
      frequencyMinutes: 15,
      updatedAt: minutesAgo(60 * 17 + 35),
      updatedBy: OTHER_ADMIN_UPN,
      status: status({
        groupId: ids.group(4),
        lastSyncUtc: minutesAgo(0),
        lastResult: 'Blocked',
        memberCount: intunePlan.current,
        lastError: `Blocked by the change limit: ${intunePlan.adds.length} changes are ${intunePlan.percent} % of ${intunePlan.current} members (limit 50 %).`,
        pendingApproval: {
          kind: 'changeLimit',
          diffHash: intunePlan.hash,
          adds: intunePlan.adds.length,
          removes: intunePlan.removes.length,
          percent: intunePlan.percent,
          detectedAt: minutesAgo(0),
        },
        lastRunId: 'run-4-0',
      }),
    }),
    base(5, {
      name: 'Country Offices',
      groupType: 'Microsoft365',
      target: { mode: 'existing', groupId: ids.group(5), displayName: 'M365-Country-Offices' },
      rule: 'user.department -in ["Programmes","Field Operations","Projects East"]',
      frequencyMinutes: 360,
      compareGroupId: ids.group(24),
      status: status({
        groupId: ids.group(5),
        lastSyncUtc: minutesAgo(60 * 4 + 15),
        memberCount: 154,
        removed: 2,
        lastRunId: 'run-5-0',
        compare: { groupId: ids.group(24), onlyInRdg: 141, onlyInCompare: 13 },
      }),
    }),
    base(6, {
      name: 'Board Members',
      groupType: 'MailEnabledSecurity',
      target: { mode: 'adopt', groupId: ids.group(6), displayName: 'MESG-Board', renameOnAdopt: true },
      rule: boardRule,
      frequencyMinutes: 1440,
      createdAt: minutesAgo(60 * 20 + 10),
      updatedAt: minutesAgo(60 * 20 + 10),
      status: status({
        groupId: ids.group(6),
        lastSyncUtc: minutesAgo(60 * 20),
        lastResult: 'WaitingForApproval',
        dryRunReason: 'adoption',
        memberCount: boardPlan.current,
        pendingApproval: {
          kind: 'adopt',
          diffHash: boardPlan.hash,
          adds: boardPlan.adds.length,
          removes: boardPlan.removes.length,
          percent: boardPlan.percent,
          detectedAt: minutesAgo(60 * 20),
        },
        lastRunId: 'run-6-0',
      }),
    }),
    base(7, {
      name: 'Project Teams South',
      groupType: 'Security',
      target: { mode: 'create', displayName: 'Project Teams South', groupId: ids.group(7) },
      rule: '(user.department -startsWith "Projects South") -and\n(user.usageLocation -in ["CH","IT"])',
      dryRun: true,
      createdAt: minutesAgo(45),
      updatedAt: minutesAgo(45),
      status: status({
        groupId: ids.group(7),
        lastSyncUtc: minutesAgo(15),
        lastResult: 'DryRun',
        dryRunReason: 'definition',
        memberCount: 0,
        added: 62,
        excluded: { disabled: 1, guests: 1 },
        lastRunId: 'run-7-0',
      }),
    }),
    base(8, {
      name: 'Service Accounts',
      groupType: 'Security',
      target: { mode: 'existing', groupId: ids.group(8), displayName: 'SG-SVC' },
      rule: 'user.extensionAttribute3 -eq "SRV"',
      enabled: false,
      status: status({ groupId: ids.group(8), lastSyncUtc: minutesAgo(60 * 24 * 10), memberCount: 9, lastRunId: null }),
    }),
    base(9, {
      name: 'Board Assistants',
      groupType: 'MailEnabledSecurity',
      target: { mode: 'existing', groupId: ids.group(9), displayName: 'MESG-Board-Assistants' },
      rule: 'user.jobTitle -eq "Board Assistant"',
      frequencyMinutes: 1440,
      allowEmpty: true,
      status: status({ groupId: ids.group(9), lastSyncUtc: minutesAgo(60 * 6), memberCount: 4, lastRunId: 'run-9-0' }),
    }),
    base(10, {
      name: 'Management Board',
      groupType: 'Security',
      target: { mode: 'existing', groupId: ids.group(10), displayName: 'SG-Management-Board' },
      rule: 'user.extensionAttribute3 -in ["STIFTRAT","DIR1","DIR2"]',
      status: status({ groupId: ids.group(10), lastSyncUtc: minutesAgo(15), memberCount: 8, lastRunId: 'run-10-0' }),
    }),
  ];
  for (const definition of definitions) {
    const target = groups.find((g) => g.id === definition.target.groupId);
    if (target && definition.target.mode !== 'adopt') target.managedByDefinitionId = definition.id;
  }
  groupOf(6).managedByDefinitionId = definitionId(6);

  // Runs
  const runs: Run[] = [];
  let job = 1;
  const run = (definition: Definition | null, minutes: number, fields: Partial<Run>) => {
    const index = runs.filter((r) => r.definitionId === (definition?.id ?? null)).length;
    runs.push({
      id: definition ? `run-${definitions.indexOf(definition) + 1}-${index}` : `run-system-${index}`,
      definitionId: definition?.id ?? null,
      definitionName: definition?.name ?? '',
      groupId: definition?.status?.groupId ?? null,
      jobId: ids.job(job),
      jobUrl: `https://portal.azure.com/#resource/subscriptions/00000000-0000-4000-8000-0000000000aa/resourceGroups/rg-rdg/providers/Microsoft.Automation/automationAccounts/aa-rdg/jobs/${ids.job(job)}`,
      runbook: definition && ['MailEnabledSecurity', 'Distribution'].includes(definition.groupType) ? 'Exchange' : 'Entra',
      mode: 'Scheduled',
      startedAt: minutesAgo(minutes),
      durationMs:
        definition && ['MailEnabledSecurity', 'Distribution'].includes(definition.groupType)
          ? 31_000 + (job % 9) * 1000
          : 3000 + (job % 4) * 1000,
      engineVersion: '0.1.0',
      result: 'OK',
      dryRun: false,
      dryRunReason: null,
      addedCount: 0,
      removedCount: 0,
      skippedCount: 0,
      added: [],
      removed: [],
      skipped: [],
      excluded: { disabled: 0, guests: 0 },
      warnings: [],
      error: null,
      approval: null,
      compare: null,
      ...fields,
    });
    job += 1;
  };
  const [eop, staff, finance, intune, offices, board, south, , assistants, management] = definitions as Definition[];
  if (eop && staff && finance && intune && offices && board && south && assistants && management) {
    run(intune, 0, {
      result: 'Blocked',
      addedCount: 0,
      approval: intune.status?.pendingApproval ?? null,
      added: intunePlan.adds.map((id) => ref(users.find((u) => u.id === id) as MockUser)),
      error: 'Blocked by the change limit.',
      reason: `${intunePlan.adds.length} changes are ${intunePlan.percent} % of ${intunePlan.current} members; the limit is 50 %.`,
    });
    run(eop, 0, { result: 'OK', addedCount: 1, added: [ref(userAt(2))], excluded: { disabled: 2, guests: 1 } });
    run(finance, 15, {
      result: 'Warning',
      skippedCount: 3,
      skipped: [userAt(106), userAt(159), userAt(212)].map(ref),
      warnings: ['3 users have no Exchange recipient and were skipped.'],
    });
    run(staff, 15, {
      result: 'OK',
      addedCount: 2,
      removedCount: 1,
      added: [userAt(317), userAt(318)].map(ref),
      removed: [ref(userAt(319))],
    });
    run(south, 15, {
      result: 'DryRun',
      dryRun: true,
      dryRunReason: 'definition',
      addedCount: 62,
      added: users
        .slice(0, 64)
        .filter((u) => u.accountEnabled && u.userType === 'Member')
        .slice(0, 62)
        .map(ref),
    });
    run(management, 15, { result: 'OK' });
    run(eop, 15, { result: 'OK' });
    run(null, 30, { result: 'SkippedTick', runbook: 'Exchange', durationMs: 1000, reason: 'The previous job was still running.' });
    run(eop, 30, { result: 'OK' });
    run(assistants, 60 * 6, { result: 'OK' });
    run(offices, 60 * 4 + 15, {
      result: 'OK',
      removedCount: 2,
      removed: [userAt(274), userAt(275)].map(ref),
      compare: {
        groupId: ids.group(24),
        onlyInRdgCount: 141,
        onlyInCompareCount: 13,
        onlyInRdg: [userAt(120), userAt(121)].map(ref),
        onlyInCompare: [userAt(70), userAt(71)].map(ref),
      },
    });
    run(board, 60 * 20, {
      result: 'WaitingForApproval',
      dryRun: true,
      dryRunReason: 'adoption',
      approval: board.status?.pendingApproval ?? null,
      added: boardPlan.adds.map((id) => ref(users.find((u) => u.id === id) as MockUser)),
      removed: boardPlan.removes.map((id) => ref(users.find((u) => u.id === id) as MockUser)),
      addedCount: boardPlan.adds.length,
      removedCount: boardPlan.removes.length,
    });
    run(staff, 60 * 24 + 15, { result: 'OK', addedCount: 1, added: [ref(userAt(316))] });
    run(intune, 60 * 24, { result: 'OK' });
    run(staff, 60 * 24 * 5 + 20, { result: 'OK', addedCount: 41, added: users.slice(270, 311).map(ref), mode: 'SyncNow' });
  }

  // Audit
  const audit: AuditEntry[] = [
    {
      id: 'aud-1',
      definitionId: intune?.id ?? null,
      definitionName: intune?.name ?? '',
      at: minutesAgo(60 * 17 + 35),
      by: OTHER_ADMIN_UPN,
      action: 'update',
      changes: [{ field: 'rule', old: 'user.extensionAttribute5 -eq "FIELD"', new: 'user.extensionAttribute5 -startsWith "FIELD"' }],
    },
    {
      id: 'aud-2',
      definitionId: board?.id ?? null,
      definitionName: board?.name ?? '',
      at: minutesAgo(60 * 20 + 10),
      by: ADMIN_UPN,
      action: 'adopt',
      changes: [{ field: 'target', old: null, new: { mode: 'adopt', groupId: ids.group(6), displayName: 'MESG-Board' } }],
    },
    {
      id: 'aud-3',
      definitionId: staff?.id ?? null,
      definitionName: staff?.name ?? '',
      at: minutesAgo(60 * 24 * 5 + 30),
      by: ADMIN_UPN,
      action: 'approve',
      changes: [{ field: 'approval', old: null, new: { kind: 'changeLimit', adds: 41, removes: 0, percent: 13 } }],
    },
    {
      id: 'aud-4',
      definitionId: null,
      definitionName: '',
      at: minutesAgo(60 * 24 * 6 + 70),
      by: ADMIN_UPN,
      action: 'settings',
      changes: [{ field: 'naming.prefix', old: { enabled: false, text: '' }, new: { enabled: true, text: 'DG-' } }],
    },
    {
      id: 'aud-5',
      definitionId: eop?.id ?? null,
      definitionName: eop?.name ?? '',
      at: minutesAgo(60 * 24 * 6 + 88),
      by: ADMIN_UPN,
      action: 'create',
      changes: [
        { field: 'groupType', old: null, new: 'MailEnabledSecurity' },
        { field: 'frequencyMinutes', old: null, new: 15 },
        { field: 'dryRun', old: null, new: true },
      ],
    },
  ];

  const settings: Settings = {
    paused: Boolean(options.paused),
    verboseLogging: false,
    changeLimitPercent: 50,
    changeLimitMinChanges: 10,
    newGroupsDryRun: true,
    nestedMembers: true,
    frequencyOptions: [3, 5, 15, 30, 60, 360, 1440],
    naming: { prefix: { enabled: true, text: 'DG-' }, suffix: { enabled: false, text: '' } },
    marker: { enabled: false, exchangeCustomAttribute: 15 },
    auditRetentionDays: 60,
    etag: '"settings-1"',
    pausedAt: options.paused ? minutesAgo(0) : null,
    pausedBy: options.paused ? ADMIN_UPN : null,
    updatedAt: minutesAgo(60 * 24 * 6 + 70),
    updatedBy: ADMIN_UPN,
  };
  if (options.paused) {
    audit.unshift({
      id: 'aud-0',
      definitionId: null,
      definitionName: '',
      at: minutesAgo(0),
      by: ADMIN_UPN,
      action: 'settings',
      changes: [{ field: 'paused', old: false, new: true }],
    });
  }

  if (options.empty) {
    for (const g of groups) g.managedByDefinitionId = null;
    return { users, groups, definitions: [], runs: [], audit: [], settings };
  }
  return { users, groups, definitions, runs, audit, settings };
}
