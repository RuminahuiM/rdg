import { ruleCompletions, toDiagnostics, withoutHint } from './RuleEditor';

describe('rule editor helpers', () => {
  it('offers properties in natural order after "user."', () => {
    const result = ruleCompletions('(user.ext', 9, false);
    expect(result?.from).toBe(6);
    const labels = result?.options.map((o) => o.label) ?? [];
    expect(labels).toContain('extensionAttribute3');
    expect(labels).toContain('extension_');
    const boost = (label: string) => result?.options.find((o) => o.label === label)?.boost ?? 0;
    expect(boost('extensionAttribute2')).toBeGreaterThan(boost('extensionAttribute10'));
  });

  it('offers only the operators that fit the property type', () => {
    const labels = ruleCompletions('user.accountEnabled ', 20, false)?.options.map((o) => o.label);
    expect(labels).toEqual(['-eq', '-ne']);
    const collection = ruleCompletions('user.memberof ', 14, false)?.options.map((o) => o.label);
    expect(collection).toEqual(['-any']);
  });

  it('places API errors in the document', () => {
    expect(toDiagnostics([{ position: 21, line: 1, column: 22, length: 1, message: 'expected a value after -eq' }], 30)).toEqual([
      { from: 21, to: 22, severity: 'error', message: 'expected a value after -eq' },
    ]);
    // Positions past the end are clipped; zero length still marks one character where possible.
    expect(toDiagnostics([{ position: 50, line: 1, column: 51, length: 0, message: 'm' }], 10)[0]).toMatchObject({ from: 10, to: 10 });
    expect(toDiagnostics([{ position: 2, line: 1, column: 3, length: 0, message: 'm' }], 10)[0]).toMatchObject({ from: 2, to: 3 });
  });

  it('removes the engine hint when it shows the suggestion as a link', () => {
    expect(
      withoutHint({
        position: 0,
        line: 1,
        column: 1,
        length: 3,
        message: 'unknown property user.x; did you mean city?',
        suggestion: 'city',
      }),
    ).toBe('unknown property user.x');
    expect(withoutHint({ position: 0, line: 1, column: 1, length: 3, message: 'unknown property user.x' })).toBe('unknown property user.x');
  });
});
