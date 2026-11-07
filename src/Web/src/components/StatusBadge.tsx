// Result badge with a dot, coloured like the mockups: green OK, orange warning,
// red blocked/error, blue dry run and waiting, grey disabled and skipped.
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import type { Definition, RunResult } from '../api/types';
import { t } from '../strings/en';

const useStyles = makeStyles({
  badge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '6px',
    padding: '2px 8px',
    borderRadius: '999px',
    fontSize: tokens.fontSizeBase200,
    fontWeight: tokens.fontWeightSemibold,
    whiteSpace: 'nowrap',
    lineHeight: tokens.lineHeightBase200,
  },
  dot: { width: '6px', height: '6px', borderRadius: '50%', backgroundColor: 'currentColor', flexShrink: 0 },
  ok: { backgroundColor: tokens.colorPaletteGreenBackground1, color: tokens.colorPaletteGreenForeground1 },
  warn: { backgroundColor: tokens.colorPaletteDarkOrangeBackground1, color: tokens.colorPaletteDarkOrangeForeground1 },
  err: { backgroundColor: tokens.colorPaletteRedBackground1, color: tokens.colorPaletteRedForeground1 },
  info: { backgroundColor: tokens.colorBrandBackground2, color: tokens.colorBrandForeground2 },
  off: { backgroundColor: tokens.colorNeutralBackground3, color: tokens.colorNeutralForeground3 },
});

export type Tone = 'ok' | 'warn' | 'err' | 'info' | 'off';

export function toneOf(result: RunResult | 'Disabled' | 'NotRunYet' | 'Syncing'): Tone {
  switch (result) {
    case 'OK':
      return 'ok';
    case 'Warning':
      return 'warn';
    case 'Blocked':
    case 'Error':
      return 'err';
    case 'DryRun':
    case 'WaitingForApproval':
    case 'Syncing':
      return 'info';
    default:
      return 'off';
  }
}

export function Badge({ tone, children, dot = true }: { tone: Tone; children: React.ReactNode; dot?: boolean }) {
  const s = useStyles();
  return (
    <span className={mergeClasses(s.badge, s[tone])}>
      {dot && <span className={s.dot} aria-hidden="true" />}
      {children}
    </span>
  );
}

export function ResultBadge({ result, label }: { result: RunResult | 'Disabled' | 'NotRunYet' | 'Syncing'; label?: string }) {
  return <Badge tone={toneOf(result)}>{label ?? t.result[result] ?? result}</Badge>;
}

/** What the groups list and the group page show as "Last result". */
export function definitionResult(
  definition: Definition,
  syncing = false,
): { result: RunResult | 'Disabled' | 'NotRunYet' | 'Syncing'; label: string } {
  if (syncing) return { result: 'Syncing', label: t.result.Syncing ?? 'Syncing' };
  if (!definition.enabled) return { result: 'Disabled', label: t.result.Disabled ?? 'Disabled' };
  const status = definition.status;
  if (!status) return { result: 'NotRunYet', label: t.result.NotRunYet ?? 'Not run yet' };
  if (status.lastResult === 'Blocked' && status.pendingApproval?.kind === 'changeLimit') {
    return { result: 'Blocked', label: t.result.BlockedChangeLimit ?? 'Blocked' };
  }
  return { result: status.lastResult, label: t.result[status.lastResult] ?? status.lastResult };
}

export function DefinitionBadge({ definition, syncing }: { definition: Definition; syncing?: boolean }) {
  const { result, label } = definitionResult(definition, syncing);
  return <ResultBadge result={result} label={label} />;
}

export function TypeBadge({ groupType }: { groupType: string }) {
  return (
    <Badge tone="info" dot={false}>
      {t.groupType[groupType] ?? groupType}
    </Badge>
  );
}
