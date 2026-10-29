// Form values of the group page and their conversion to and from the API shapes.
import type { Definition, DefinitionInput, GroupType, Settings, UserRef } from '../../api/types';
import type { PickedGroup } from '../../components/GroupPicker';
import type { ConflictRow } from '../../dialogs/ConflictDialog';
import { t } from '../../strings/en';

export interface FormValues {
  name: string;
  groupType: GroupType;
  mode: 'create' | 'existing' | 'adopt';
  targetGroup: PickedGroup | null;
  renameOnAdopt: boolean;
  rule: string;
  includeUsers: UserRef[];
  excludeUsers: UserRef[];
  includeDisabled: boolean;
  includeGuests: boolean;
  frequencyMinutes: number;
  enabled: boolean;
  dryRun: boolean;
  changeLimitPercent: number | null;
  allowEmpty: boolean;
  compareGroup: PickedGroup | null;
}

/** Names for IDs the API couldn't resolve: show the ID itself. */
const refs = (ids: string[], named: UserRef[] | undefined): UserRef[] =>
  ids.map((id) => named?.find((u) => u.id === id) ?? { id, upn: id, displayName: id });

export function fromDefinition(d: Definition): FormValues {
  return {
    name: d.name,
    groupType: d.groupType,
    mode: d.target.mode,
    targetGroup:
      d.target.groupId && d.target.mode !== 'create'
        ? { id: d.target.groupId, displayName: d.target.displayName ?? d.target.groupId }
        : null,
    renameOnAdopt: Boolean(d.target.renameOnAdopt),
    rule: d.rule,
    includeUsers: refs(d.includeUserIds, d.includeUsers),
    excludeUsers: refs(d.excludeUserIds, d.excludeUsers),
    includeDisabled: d.includeDisabled,
    includeGuests: d.includeGuests,
    frequencyMinutes: d.frequencyMinutes,
    enabled: d.enabled,
    dryRun: d.dryRun,
    changeLimitPercent: d.changeLimitPercent,
    allowEmpty: d.allowEmpty,
    compareGroup: d.compareGroupId ? { id: d.compareGroupId, displayName: d.compareGroup?.displayName ?? d.compareGroupId } : null,
  };
}

export function newFormValues(settings: Settings | undefined): FormValues {
  const options = settings?.frequencyOptions ?? [60];
  return {
    name: '',
    groupType: 'Security',
    mode: 'create',
    targetGroup: null,
    renameOnAdopt: false,
    rule: '',
    includeUsers: [],
    excludeUsers: [],
    includeDisabled: false,
    includeGuests: false,
    frequencyMinutes: options.includes(60) ? 60 : (options[0] ?? 60),
    enabled: true,
    dryRun: settings?.newGroupsDryRun ?? true,
    changeLimitPercent: null,
    allowEmpty: false,
    compareGroup: null,
  };
}

export function toDefinitionInput(v: FormValues): DefinitionInput {
  const target: DefinitionInput['target'] =
    v.mode === 'create'
      ? { mode: 'create', displayName: v.name.trim() }
      : {
          mode: v.mode,
          groupId: v.targetGroup?.id,
          displayName: v.targetGroup?.displayName,
          ...(v.mode === 'adopt' ? { renameOnAdopt: v.renameOnAdopt } : {}),
        };
  return {
    name: v.name.trim(),
    groupType: v.groupType,
    target,
    rule: v.rule,
    includeUserIds: v.includeUsers.map((u) => u.id),
    excludeUserIds: v.excludeUsers.map((u) => u.id),
    includeDisabled: v.includeDisabled,
    includeGuests: v.includeGuests,
    frequencyMinutes: v.frequencyMinutes,
    enabled: v.enabled,
    dryRun: v.dryRun,
    changeLimitPercent: v.changeLimitPercent,
    allowEmpty: v.allowEmpty,
    compareGroupId: v.compareGroup?.id ?? null,
  };
}

/** Rows of the conflict dialog: fields where the saved version and the form differ. */
export function conflictRows(latest: Definition, mine: FormValues, orgLimit: number): ConflictRow[] {
  const theirs = fromDefinition(latest);
  const names = (users: UserRef[]) => users.map((u) => u.displayName || u.upn).join(', ') || t.common.none;
  const yesNo = (b: boolean) => (b ? t.common.yes : t.common.no);
  const limit = (p: number | null) => (p === null ? t.group.orgDefault(orgLimit) : t.group.percent(p));
  const target = (v: FormValues) =>
    v.mode === 'create' ? `${t.group.modeCreate}: ${v.name}` : `${v.targetGroup?.displayName ?? t.common.none}`;
  const fields: [string, string, string, boolean?][] = [
    ['name', theirs.name, mine.name],
    ['groupType', t.groupType[theirs.groupType] ?? '', t.groupType[mine.groupType] ?? ''],
    ['target', target(theirs), target(mine)],
    ['rule', theirs.rule, mine.rule, true],
    ['includeUserIds', names(theirs.includeUsers), names(mine.includeUsers)],
    ['excludeUserIds', names(theirs.excludeUsers), names(mine.excludeUsers)],
    ['includeDisabled', yesNo(theirs.includeDisabled), yesNo(mine.includeDisabled)],
    ['includeGuests', yesNo(theirs.includeGuests), yesNo(mine.includeGuests)],
    ['frequencyMinutes', t.frequency(theirs.frequencyMinutes), t.frequency(mine.frequencyMinutes)],
    ['enabled', yesNo(theirs.enabled), yesNo(mine.enabled)],
    ['dryRun', yesNo(theirs.dryRun), yesNo(mine.dryRun)],
    ['changeLimitPercent', limit(theirs.changeLimitPercent), limit(mine.changeLimitPercent)],
    ['allowEmpty', yesNo(theirs.allowEmpty), yesNo(mine.allowEmpty)],
    ['compareGroupId', theirs.compareGroup?.displayName ?? t.common.none, mine.compareGroup?.displayName ?? t.common.none],
  ];
  return fields
    .filter(([, a, b]) => a !== b)
    .map(([field, a, b, mono]) => ({ field: t.conflict.fields[field] ?? field, theirs: a, mine: b, mono }));
}

export function affixed(name: string, settings: Settings | undefined): string {
  const prefix = settings?.naming.prefix.enabled ? settings.naming.prefix.text : '';
  const suffix = settings?.naming.suffix.enabled ? settings.naming.suffix.text : '';
  return `${prefix}${name}${suffix}`;
}

/** The adoption's forced dry run: who would be added and removed, waiting for approval. */
