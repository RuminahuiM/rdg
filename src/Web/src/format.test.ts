import { initials, longWhen, nameFromUpn, sentenceWhen, shortName, shortWhen, timeWhen } from './format';

// Tests run with TZ=UTC (vite.config.ts).
const now = new Date('2026-10-12T10:20:00Z');

describe('format', () => {
  it('shows today as a time, yesterday as a word, older days as a date', () => {
    expect(shortWhen('2026-10-12T10:15:00Z', now)).toBe('10:15');
    expect(shortWhen('2026-10-11T16:40:00Z', now)).toBe('Yesterday');
    expect(shortWhen('2026-10-02T09:00:00Z', now)).toBe('2 Oct');
    expect(shortWhen('2025-10-02T09:00:00Z', now)).toBe('2 Oct 2025');
    expect(shortWhen(null, now)).toBe('–');
  });

  it('has a long form for details and a form for sentences', () => {
    expect(longWhen('2026-10-12T10:15:00Z', now)).toBe('Today 10:15');
    expect(longWhen('2026-10-11T16:40:00Z', now)).toBe('Yesterday 16:40');
    expect(longWhen('2026-10-07T11:20:00Z', now)).toBe('7 Oct 11:20');
    expect(sentenceWhen('2026-10-11T16:40:00Z', now)).toBe('yesterday 16:40');
    expect(timeWhen('2026-10-12T10:15:00Z', now)).toBe('10:15');
    expect(timeWhen('2026-10-11T16:40:00Z', now)).toBe('Yesterday 16:40');
  });

  it('turns UPNs into names', () => {
    expect(nameFromUpn('lea.keller@contoso.org')).toBe('Lea Keller');
    expect(shortName('lea.keller@contoso.org')).toBe('Lea K.');
    expect(shortName('admin@contoso.org')).toBe('admin@contoso.org');
    expect(shortName(null)).toBe('');
    expect(initials('alex.example@contoso.org')).toBe('AE');
    expect(initials('admin@contoso.org')).toBe('A');
  });
});
