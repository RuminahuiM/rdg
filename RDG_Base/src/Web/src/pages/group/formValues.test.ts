import type { Definition } from '../../api/types';
import { conflictRows, fromDefinition, newFormValues, toDefinitionInput } from './formValues';

const definition: Definition = {
  id: 'def-01JA7K3M9QXR4T6V8W0Y2Z4B6D',
  etag: '"1"',
  name: 'Board',
  groupType: 'MailEnabledSecurity',
  target: {
    mode: 'adopt',
    groupId: '0b7d2c1e-0000-4e3b-9c8d-000000000006',
    displayName: 'MESG-Board',
    renameOnAdopt: true,
    adopted: false,
  },
  rule: 'user.department -eq "Board"',
  includeUserIds: ['u1'],
  excludeUserIds: ['u2'],
  includeDisabled: false,
  includeGuests: true,
  frequencyMinutes: 60,
  enabled: true,
  dryRun: false,
  changeLimitPercent: null,
  allowEmpty: false,
  compareGroupId: null,
  includeUsers: [{ id: 'u1', upn: 'lea.keller@contoso.org', displayName: 'Lea Keller' }],
  createdAt: '2026-10-01T00:00:00Z',
  createdBy: 'a@contoso.org',
  updatedAt: '2026-10-02T00:00:00Z',
  updatedBy: 'lea.keller@contoso.org',
  syncRequest: null,
  approval: null,
  status: null,
};

describe('group form', () => {
  it('round-trips a definition through the form', () => {
    const values = fromDefinition(definition);
    expect(values.includeUsers[0]?.displayName).toBe('Lea Keller');
    // An ID the API couldn't name is shown as the ID.
    expect(values.excludeUsers[0]).toEqual({ id: 'u2', upn: 'u2', displayName: 'u2' });
    const input = toDefinitionInput(values);
    expect(input.target).toEqual({ mode: 'adopt', groupId: definition.target.groupId, displayName: 'MESG-Board', renameOnAdopt: true });
    expect(input.includeUserIds).toEqual(['u1']);
    expect(input).not.toHaveProperty('etag');
    expect(input).not.toHaveProperty('includeUsers');
  });

  it('sends no group ID for a group the engine creates', () => {
    const values = { ...newFormValues(undefined), name: ' New ', rule: 'user.city -eq "Bern"' };
    expect(toDefinitionInput(values).target).toEqual({ mode: 'create', displayName: 'New' });
    expect(values.dryRun).toBe(true);
  });

  it('lists only the fields that differ in the conflict dialog', () => {
    const mine = { ...fromDefinition(definition), frequencyMinutes: 15, changeLimitPercent: 30 };
    const rows = conflictRows(definition, mine, 50);
    expect(rows).toEqual([
      { field: 'Frequency', theirs: '1 h', mine: '15 min', mono: undefined },
      { field: 'Change limit', theirs: 'Organisation default (50 %)', mine: '30 %', mono: undefined },
    ]);
  });
});
