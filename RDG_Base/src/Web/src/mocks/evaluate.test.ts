import { checkRule, evaluate, type MockUser } from './evaluate';

const user = (id: string, fields: Partial<MockUser>): MockUser => ({
  id,
  displayName: id,
  userPrincipalName: `${id}@contoso.org`,
  mail: `${id}@contoso.org`,
  accountEnabled: true,
  userType: 'Member',
  memberOf: [],
  ...fields,
});

describe('mock rule check', () => {
  it('reports a missing value at the token after the operator, like the engine', () => {
    const check = checkRule('(user.department -eq ) -and (user.city -eq "Bern")');
    expect(check.valid).toBe(false);
    expect(check.errors[0]).toMatchObject({ position: 21, line: 1, column: 22, message: 'expected a value after -eq' });
  });

  it('suggests the closest property name', () => {
    const check = checkRule('user.extensionAtribute3 -eq "KOM"');
    expect(check.errors[0]?.suggestion).toBe('extensionAttribute3');
    expect(check.errors[0]?.message).toContain('did you mean extensionAttribute3?');
  });

  it('collects memberOf group IDs', () => {
    const check = checkRule("user.memberof -any (group.objectId -in ['AA','bb'])");
    expect(check.valid).toBe(true);
    expect(check.groupIds).toEqual(['aa', 'bb']);
  });

  it('evaluates conditions, lists, -not and memberOf', () => {
    const users = [
      user('a', { department: 'Sales', memberOf: ['g1'] }),
      user('b', { department: 'IT' }),
      user('c', { department: 'sales' }),
    ];
    expect(evaluate('user.department -eq "Sales"', users).map((u) => u.id)).toEqual(['a', 'c']);
    expect(evaluate('user.department -in ["IT","HR"]', users).map((u) => u.id)).toEqual(['b']);
    expect(evaluate('-not (user.department -eq "IT")', users).map((u) => u.id)).toEqual(['a', 'c']);
    expect(evaluate("user.memberof -any (group.objectId -in ['g1'])", users).map((u) => u.id)).toEqual(['a']);
    expect(evaluate('user.department -eq', users)).toEqual([]);
  });
});
