import { createData } from '../mocks/data';
import { lastRunText, targetText } from './definitionText';

const now = new Date('2026-10-12T10:20:00Z');
const byName = (name: string) => {
  const found = createData(now).definitions.find((d) => d.name === name);
  if (!found) throw new Error(name);
  return found;
};

describe('definition texts', () => {
  it('describes the last run as the groups list shows it', () => {
    expect(lastRunText(byName('All Staff Zürich'))).toBe('+2 / −1');
    expect(lastRunText(byName('Finance – Distribution'))).toBe('+0 / −0, 3 skipped');
    expect(lastRunText(byName('Intune – Field Laptops'))).toBe('+84 / −0 held');
    expect(lastRunText(byName('Board Members'))).toBe('Dry run: +1 / −3');
    expect(lastRunText(byName('Project Teams South'))).toBe('Would add 62');
    expect(lastRunText(byName('Service Accounts'))).toBe('–');
  });

  it('names the target group', () => {
    expect(targetText(byName('Board Members'))).toBe('MESG-Board (adopted)');
    expect(targetText(byName('All Staff Zürich'))).toBe('SG-Staff-ZH');
    expect(targetText({ ...byName('Project Teams South'), status: null, target: { mode: 'create', displayName: 'X' } })).toBe('New group');
  });
});
