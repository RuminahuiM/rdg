import { useDefinitionRuns } from '../../api/hooks';
import type { Definition } from '../../api/types';
import { Section, useUiStyles } from '../../components/ui';
import { longWhen } from '../../format';
import { t } from '../../strings/en';
import { useGroupStyles as useStyles } from './styles';

export function AdoptResultCard({ definition }: { definition: Definition }) {
  const s = useStyles();
  const ui = useUiStyles();
  const runs = useDefinitionRuns(definition.id);
  const pending = definition.status?.pendingApproval;
  if (!pending || pending.kind !== 'adopt') return null;
  const run = runs.data?.find((r) => r.approval?.diffHash === pending.diffHash);
  return (
    <Section title={t.group.dryRunResult} labelId="adopt-result">
      <div className={`${ui.muted} ${ui.small}`} style={{ marginBottom: 8 }}>
        {t.group.forcedDryRun(longWhen(pending.detectedAt ?? definition.status?.lastSyncUtc))}
      </div>
      <div className={s.stats}>
        <div className={s.stat}>
          <div className={ui.stat}>+{pending.adds}</div>
          <div className={`${ui.muted} ${ui.small}`}>{t.group.toAdd}</div>
        </div>
        <div className={s.stat}>
          <div className={ui.stat}>−{pending.removes}</div>
          <div className={`${ui.muted} ${ui.small}`}>{t.group.toRemove}</div>
        </div>
      </div>
      {run && (run.removed ?? []).length > 0 && (
        <>
          <div className={ui.subhead}>{t.group.wouldBeRemoved}</div>
          <ul className={ui.list}>
            {(run.removed ?? []).slice(0, 8).map((u) => (
              <li key={u.id} className={s.person}>
                <span>{u.displayName || u.upn}</span>
                <span className={`${ui.muted} ${ui.small}`}>{u.upn}</span>
              </li>
            ))}
          </ul>
        </>
      )}
      {run && (run.added ?? []).length > 0 && (
        <>
          <div className={ui.subhead}>{t.group.wouldBeAdded}</div>
          <ul className={ui.list}>
            {(run.added ?? []).slice(0, 8).map((u) => (
              <li key={u.id} className={s.person}>
                <span>{u.displayName || u.upn}</span>
                <span className={`${ui.muted} ${ui.small}`}>{u.upn}</span>
              </li>
            ))}
          </ul>
        </>
      )}
      <p className={`${ui.muted} ${ui.small}`}>{t.group.nonUserMembers}</p>
      <p style={{ marginBottom: 0 }}>{t.group.afterAdopt}</p>
    </Section>
  );
}
