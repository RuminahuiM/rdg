import { completionContext, countConditions, findProperty, operatorsByType, properties, tokenize } from './language';
import propertyFile from './properties.json';

describe('rule language', () => {
  it('uses the property list generated from the engine', () => {
    expect(properties.length).toBe(propertyFile.properties.length);
    expect(findProperty('EXTENSIONATTRIBUTE3')?.type).toBe('String');
    expect(findProperty('memberOf')?.type).toBe('GroupCollection');
    expect(findProperty('extension_b7d8e5f3a1c24e6f9d0a1b2c3d4e5f60_costCentre')?.type).toBe('String');
    expect(findProperty('extensionAtribute3')).toBeUndefined();
    for (const p of properties) expect(operatorsByType[p.type].length).toBeGreaterThan(0);
  });

  it('tokenizes properties, operators, strings and punctuation with positions', () => {
    const tokens = tokenize('(user.department -eq "Sales") -and (user.city –ne \'Bern\')');
    expect(tokens.map((t) => t.kind)).toEqual([
      'punct',
      'property',
      'operator',
      'string',
      'punct',
      'logical',
      'punct',
      'property',
      'operator',
      'string',
      'punct',
    ]);
    expect(tokens[1]).toMatchObject({ text: 'user.department', from: 1, to: 16 });
    // An en dash before ne counts as a hyphen, as in the engine.
    expect(tokens[8]?.text).toBe('–ne');
  });

  it('keeps escaped quotes inside strings and runs unclosed strings to the end', () => {
    expect(tokenize('user.a -eq "x`"y"').map((t) => t.text)).toEqual(['user.a', '-eq', '"x`"y"']);
    expect(tokenize("user.a -eq 'it''s'").at(-1)?.text).toBe("'it''s'");
    expect(tokenize('user.a -eq "open').at(-1)).toMatchObject({ kind: 'string', text: '"open' });
  });

  it('counts conditions; a memberOf -any counts once', () => {
    const rule =
      '(user.extensionAttribute3 -in ["A","B"]) -or (user.extensionAttribute3 -startsWith "SRV") -or (user.memberof -any (group.objectId -in [\'x\']))';
    expect(countConditions(rule)).toBe(3);
    expect(countConditions('')).toBe(0);
  });

  it('knows what to suggest where', () => {
    expect(completionContext('(user.dep', 9)).toEqual({ kind: 'property', from: 6 });
    expect(completionContext('user.accountEnabled ', 20)).toMatchObject({ kind: 'operator', type: 'Boolean' });
    expect(completionContext('user.department -', 17)).toMatchObject({ kind: 'operator', type: 'String', from: 16 });
    expect(completionContext('user.department -eq "x" ', 24).kind).toBe('logical');
    expect(completionContext('', 0).kind).toBe('start');
    expect(completionContext('(user.a -eq "x") -and ', 22).kind).toBe('start');
  });
});
