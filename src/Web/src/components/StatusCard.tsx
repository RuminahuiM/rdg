// Status of one definition as the engine last wrote it, plus the compare counts.
import { Button, makeStyles, tokens } from '@fluentui/react-components';
import { AppLink } from './AppLink';
import type { Definition } from '../api/types';
import { DefinitionBadge } from './StatusBadge';
import { Section, useUiStyles } from './ui';
import { longWhen } from '../format';
import { lastRunText } from './definitionText';
import { t } from '../strings/en';

const useStyles = makeStyles({
  grid: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px 16px' },
  label: { color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase200, marginBottom: '2px' },
  value: { fontSize: tokens.fontSizeBase300, fontWeight: tokens.fontWeightSemibold },
  note: {
    marginTop: '14px',
    padding: '8px 10px',
    borderRadius: tokens.borderRadiusMedium,
    fontSize: tokens.fontSizeBase200,
    backgroundColor: tokens.colorNeutralBackground2,
  },
  error: { backgroundColor: tokens.colorPaletteRedBackground1, color: tokens.colorPaletteRedForeground1 },
  warn: { backgroundColor: tokens.colorPaletteDarkOrangeBackground1, color: tokens.colorPaletteDarkOrangeForeground1 },
  footer: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '8px', flexWrap: 'wrap', marginTop: '16px' },
});

export function StatusCard({
  definition,
  syncing,
  onApprove,
}: {
  definition: Definition;
  syncing?: boolean;
  /** Shown when a change waits for approval and the user may approve. */
  onApprove?: () => void;
}) {
  const s = useStyles();
  const ui = useUiStyles();
  const status = definition.status;
  const pending = status?.pendingApproval;
  return (
    <Section title={t.group.status} labelId="status-title">
      {!status ? (
        <p className={ui.muted} style={{ margin: 0 }}>
          {t.group.notRunYet}
        </p>
      ) : (
        <>
          <div className={s.grid}>
            <div>
              <div className={s.label}>{t.group.lastResult}</div>
              <DefinitionBadge definition={definition} syncing={syncing} />
            </div>
            <div>
              <div className={s.label}>{t.group.members}</div>
              <div className={s.value}>{status.memberCount}</div>
            </div>
            <div>
              <div className={s.label}>{t.group.lastSync}</div>
              <div className={s.value}>{longWhen(status.lastSyncUtc)}</div>
            </div>
            <div>
              <div className={s.label}>{t.group.lastRun}</div>
              <div className={s.value}>{lastRunText(definition)}</div>
            </div>
          </div>
          {status.dryRunReason && <div className={s.note}>{t.dryRunReason[status.dryRunReason]}</div>}
          {status.lastError && (
            <div className={`${s.note} ${s.error}`} role="note">
              <strong>{t.group.lastError}:</strong> {status.lastError}
            </div>
          )}
          {(status.warnings ?? []).length > 0 && (
            <div className={`${s.note} ${s.warn}`}>
              <strong>{t.group.warnings}:</strong> {(status.warnings ?? []).join(' ')}
            </div>
          )}
          {status.manualChangeDetected && <div className={`${s.note} ${s.warn}`}>{t.group.manualChange}</div>}
          {status.compare && (
            <div className={s.note}>
              <strong>{t.group.compare}:</strong> {t.group.compareCounts(status.compare.onlyInRdg, status.compare.onlyInCompare)}
            </div>
          )}
        </>
      )}
      <div className={s.footer}>
        <AppLink to={`/activity?definitionId=${definition.id}`}>{t.group.viewRuns}</AppLink>
        {pending?.kind === 'changeLimit' && onApprove && (
          <Button appearance="primary" onClick={onApprove}>
            {t.group.approveOnce}
          </Button>
        )}
      </div>
    </Section>
  );
}
