// Date and number formatting in the user's time zone, with en-GB patterns as in the mockups.
import { locale, t } from './strings/en';

const timeFormat = new Intl.DateTimeFormat(locale, { hour: '2-digit', minute: '2-digit', hour12: false });
const dayFormat = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' });
const dayYearFormat = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' });

function startOfDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

function dayDiff(date: Date, now: Date): number {
  return Math.round((startOfDay(now) - startOfDay(date)) / 86_400_000);
}

function day(date: Date, now: Date): string {
  return date.getFullYear() === now.getFullYear() ? dayFormat.format(date) : dayYearFormat.format(date);
}

/** Compact form for tables: "10:15", "Yesterday", "2 Oct". */
export function shortWhen(iso: string | null | undefined, now: Date = new Date()): string {
  if (!iso) return t.time.never;
  const date = new Date(iso);
  const diff = dayDiff(date, now);
  if (diff === 0) return timeFormat.format(date);
  if (diff === 1) return t.time.yesterday;
  return day(date, now);
}

/** Full form: "Today 10:15", "Yesterday 16:40", "7 Oct 11:20". */
export function longWhen(iso: string | null | undefined, now: Date = new Date()): string {
  if (!iso) return t.time.never;
  const date = new Date(iso);
  const diff = dayDiff(date, now);
  const time = timeFormat.format(date);
  if (diff === 0) return t.time.today(time);
  if (diff === 1) return t.time.yesterdayAt(time);
  return `${day(date, now)} ${time}`;
}

/** "10:15" for today, otherwise as longWhen. Used inside sentences ("at 10:15"). */
export function atWhen(iso: string | null | undefined, now: Date = new Date()): string {
  if (!iso) return t.time.never;
  const date = new Date(iso);
  if (dayDiff(date, now) === 0) return timeFormat.format(date);
  const text = longWhen(iso, now);
  return text.charAt(0).toLowerCase() + text.slice(1);
}

/** Time for today, else the full form: Activity rows. */
export function timeWhen(iso: string | null | undefined, now: Date = new Date()): string {
  if (!iso) return t.time.never;
  return dayDiff(new Date(iso), now) === 0 ? timeFormat.format(new Date(iso)) : longWhen(iso, now);
}

/** longWhen for the middle of a sentence: "today 10:15", "yesterday 16:40", "7 Oct 11:20". */
export function sentenceWhen(iso: string | null | undefined, now: Date = new Date()): string {
  const text = longWhen(iso, now);
  return text.charAt(0).toLowerCase() + text.slice(1);
}

export function timeOnly(iso: string): string {
  return timeFormat.format(new Date(iso));
}

/** "Dodoe Mannale" from "dodoe.mannale@contoso.org"; the UPN when it has no dot. */
export function nameFromUpn(upn: string): string {
  const local = upn.split('@')[0] ?? upn;
  const parts = local.split(/[._-]+/).filter(Boolean);
  if (parts.length < 2) return upn;
  return parts.map((p) => p.charAt(0).toUpperCase() + p.slice(1)).join(' ');
}

/** "Lea K." style short name from a UPN, as in the mockups ("Dodoe M."). */
export function shortName(upn: string | null | undefined): string {
  if (!upn) return '';
  const full = nameFromUpn(upn);
  if (full === upn) return upn;
  const [first, ...rest] = full.split(' ');
  const last = rest[rest.length - 1];
  return last ? `${first} ${last.charAt(0)}.` : full;
}

export function initials(upn: string): string {
  const full = nameFromUpn(upn);
  const parts = full === upn ? [upn] : full.split(' ');
  const first = parts[0]?.charAt(0) ?? '';
  const last = parts.length > 1 ? (parts[parts.length - 1]?.charAt(0) ?? '') : '';
  return (first + last).toUpperCase();
}

export function percent(value: number): string {
  return `${Math.round(value)} %`;
}
