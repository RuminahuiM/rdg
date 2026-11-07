// What the simulated engine computes: desired members after the filters, and a hash of a diff
// (the approval covers exactly one diff, as in the real engine).
import type { Definition, UserRef } from '../api/types';
import { evaluate, type MockUser } from './evaluate';

export type ExcludeReason = 'disabled' | 'guest' | 'excludeList' | 'noExchangeRecipient';

export type DesiredInput = Pick<
  Definition,
  'rule' | 'includeUserIds' | 'excludeUserIds' | 'includeDisabled' | 'includeGuests' | 'groupType'
>;

export const userRef = (user: MockUser): UserRef => ({ id: user.id, upn: user.userPrincipalName, displayName: user.displayName });

export function desiredMembers(users: MockUser[], definition: DesiredInput) {
  const matched = evaluate(definition.rule, users);
  const byId = new Map(users.map((u) => [u.id, u]));
  const excluded: { user: UserRef; reason: ExcludeReason }[] = [];
  const members: MockUser[] = [];
  const exchange = definition.groupType === 'MailEnabledSecurity' || definition.groupType === 'Distribution';
  const forcedExtra = definition.includeUserIds
    .map((id) => byId.get(id))
    .filter((u): u is MockUser => Boolean(u) && !matched.includes(u as MockUser));
  for (const user of [...matched, ...forcedExtra]) {
    const forced = definition.includeUserIds.includes(user.id);
    if (definition.excludeUserIds.includes(user.id)) excluded.push({ user: userRef(user), reason: 'excludeList' });
    else if (!forced && !user.accountEnabled && !definition.includeDisabled) excluded.push({ user: userRef(user), reason: 'disabled' });
    else if (!forced && user.userType === 'Guest' && !definition.includeGuests) excluded.push({ user: userRef(user), reason: 'guest' });
    else if (exchange && !user.mail) excluded.push({ user: userRef(user), reason: 'noExchangeRecipient' });
    else members.push(user);
  }
  return { members, excluded };
}

/** The diff from the current members to the desired ones. */
export function diffOf(current: string[], desired: string[]) {
  const now = new Set(current);
  const want = new Set(desired);
  return { adds: desired.filter((id) => !now.has(id)), removes: current.filter((id) => !want.has(id)) };
}

/** sha256-shaped, deterministic hash of a diff (FNV-1a based; good enough for a mock). */
export function diffHash(adds: string[], removes: string[]): string {
  const text = `${[...adds].sort().join(',')}|${[...removes].sort().join(',')}`;
  let out = '';
  for (let round = 0; round < 8; round += 1) {
    let h = 0x811c9dc5 ^ round;
    for (let i = 0; i < text.length; i += 1) {
      h ^= text.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    out += h.toString(16).padStart(8, '0');
  }
  return `sha256:${out}`;
}
