// Short texts about a definition, shared by the groups list and the group page.
import type { Definition } from '../api/types';
import { t } from '../strings/en';

/** "+1 / −0", "Would add 64", "+88 / −0 held"… as in the mockup's "Last run" column. */
export function lastRunText(d: Definition): string {
  const s = d.status;
  if (!s || !d.enabled) return t.common.dash;
  if (s.pendingApproval && s.lastResult === 'Blocked') return t.groups.heldBoth(s.pendingApproval.adds, s.pendingApproval.removes);
  if (s.lastResult === 'WaitingForApproval' && s.pendingApproval)
    return t.groups.dryRunWould(s.pendingApproval.adds, s.pendingApproval.removes);
  if (s.lastResult === 'DryRun') return t.groups.dryRunWould(s.added, s.removed);
  const text = t.groups.lastRun(s.added, s.removed);
  return s.skipped ? `${text}, ${t.groups.skipped(s.skipped)}` : text;
}

export function targetText(d: Definition): string {
  if (d.target.mode === 'create' && !d.status?.groupId) return t.groups.newTarget;
  const name = d.target.displayName ?? d.target.groupId ?? '';
  return d.target.mode === 'adopt' ? `${name}${t.groups.adoptedSuffix}` : name;
}
