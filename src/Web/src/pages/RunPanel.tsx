// Activity side panel: what one run did, why, and what to do next (mockup Activity).
import { useState } from 'react';
import { Button, Link, makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { useAudit, useDefinition, useSettings } from '../api/hooks';
import type { Run, UserRef } from '../api/types';
import { useSession } from '../auth/session';
import { AppLink } from '../components/AppLink';
import { useUiStyles } from '../components/ui';
import { ApproveDialog } from '../dialogs/ApproveDialog';
import { useNotify } from '../components/notify';
import { longWhen, sentenceWhen, shortName } from '../format';
import { t } from '../strings/en';

const useStyles = makeStyles({
  panelHeader: { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '8px' },
  h2: { margin: 0, fontSize: tokens.fontSizeBase400, fontWeight: tokens.fontWeightSemibold },
  summary: { marginTop: '16px', padding: '10px 12px', borderRadius: tokens.borderRadiusMedium, fontSize: tokens.fontSizeBase300 },
  ok: { backgroundColor: tokens.colorPaletteGreenBackground1, color: tokens.colorPaletteGreenForeground1 },
  err: { backgroundColor: tokens.colorPaletteRedBackground1, color: tokens.colorPaletteRedForeground1 },
  warn: { backgroundColor: tokens.colorPaletteDarkOrangeBackground1, color: tokens.colorPaletteDarkOrangeForeground1 },
  info: { backgroundColor: tokens.colorBrandBackground2, color: tokens.colorBrandForeground2 },
  off: { backgroundColor: tokens.colorNeutralBackground3, color: tokens.colorNeutralForeground2 },
  actions: { display: 'flex', gap: '8px', flexWrap: 'wrap', marginTop: '20px' },
});

function UserList({ title, users, total }: { title: string; users: UserRef[]; total: number }) {
  const ui = useUiStyles();
  const [all, setAll] = useState(false);
  if (total === 0) return null;
  const shown = all ? users : users.slice(0, 3);
  return (
    <>
      <div className={ui.subhead}>{title}</div>
      <ul className={ui.list}>
        {shown.map((u) => (
          <li key={u.id}>{u.displayName || u.upn}</li>
        ))}
      </ul>
      {!all && users.length > 3 && (
        <Link as="button" onClick={() => setAll(true)} style={{ marginTop: 6 }}>
          {t.common.showAll(total)}
        </Link>
      )}
    </>
  );
}

export function RunPanel({ run, onClose }: { run: Run; onClose: () => void }) {
  const s = useStyles();
  const ui = useUiStyles();
  const { isAdmin, readOnly } = useSession();
  const notify = useNotify();
  const definition = useDefinition(run.definitionId ?? undefined);
  const audit = useAudit({ definitionId: run.definitionId ?? undefined });
  const [approveOpen, setApproveOpen] = useState(false);

  const added = run.addedCount ?? run.added?.length ?? 0;
  const removed = run.removedCount ?? run.removed?.length ?? 0;
  const pending = run.approval;
  const held = run.result === 'Blocked' || run.result === 'WaitingForApproval' || run.dryRun;
  const members = definition.data?.status?.memberCount ?? 0;
  const settings = useSettings();
  const limit = definition.data?.changeLimitPercent ?? settings.data?.changeLimitPercent;

  const [tone, headline] = ((): [keyof typeof s, string] => {
    switch (run.result) {
      case 'OK':
        return ['ok', t.activity.okTitle];
      case 'Warning':
        return ['warn', t.activity.warningTitle];
      case 'Blocked':
        return ['err', t.activity.blockedTitle];
      case 'Error':
        return ['err', t.activity.errorTitle];
      case 'DryRun':
        return ['info', t.activity.dryRunTitle];
      case 'WaitingForApproval':
        return ['info', t.activity.waitingTitle];
      case 'SkippedTick':
        return ['off', t.activity.skippedTitle];
      default:
        return ['off', t.activity.pausedTitle];
    }
  })();

  // The latest rule change before this run, as the likely cause of a blocked run.
  const cause = (audit.data ?? []).find((e) => e.at <= run.startedAt && e.changes.some((c) => c.field === 'rule'));
  const canApprove =
    isAdmin &&
    !readOnly &&
    pending &&
    definition.data?.status?.pendingApproval?.diffHash === pending.diffHash &&
    (run.result === 'Blocked' || run.result === 'WaitingForApproval');

  return (
    <aside className={ui.card} aria-label={t.activity.details}>
      <div className={s.panelHeader}>
        <div>
          <h2 className={s.h2}>{run.definitionName || t.activity.allSystem}</h2>
          <div className={`${ui.muted} ${ui.small}`}>
            {t.activity.runAt(longWhen(run.startedAt), t.activity.runbookName(run.runbook))}
            {run.mode === 'SyncNow' ? ` · ${t.activity.syncNowMode}` : ''}
          </div>
        </div>
        <Button appearance="subtle" aria-label={t.activity.closeDetails} onClick={onClose}>
          ×
        </Button>
      </div>
      <div className={mergeClasses(s.summary, s[tone])}>
        <strong>{headline}</strong>{' '}
        {run.result === 'Blocked' && pending
          ? limit || members
            ? t.activity.blockedDetail(pending.adds + pending.removes, pending.percent, members, limit ?? 0)
            : t.activity.blockedDetailNoLimit(pending.adds + pending.removes, pending.percent)
          : (run.reason ?? run.error ?? (run.dryRunReason ? t.dryRunReason[run.dryRunReason] : ''))}
      </div>
      {run.dryRun && run.then && (
        <div className={`${ui.small}`} style={{ marginTop: 8 }} data-testid="run-then">
          <strong>{t.activity.thenTitle}</strong> {t.activity.then(run.then.result, run.then.message)}
        </div>
      )}
      {(run.warnings ?? []).length > 0 && (
        <ul className={ui.list} style={{ marginTop: 12 }}>
          {(run.warnings ?? []).map((w) => (
            <li key={w}>{w}</li>
          ))}
        </ul>
      )}
      <UserList
        title={held ? t.activity.wouldAdd(pending?.adds ?? added) : t.activity.added(added)}
        users={run.added ?? []}
        total={held ? (pending?.adds ?? run.added?.length ?? 0) : added}
      />
      <UserList
        title={held ? t.activity.wouldRemove(pending?.removes ?? removed) : t.activity.removed(removed)}
        users={run.removed ?? []}
        total={held ? (pending?.removes ?? run.removed?.length ?? 0) : removed}
      />
      <UserList title={t.activity.skippedUsers(run.skippedCount ?? 0)} users={run.skipped ?? []} total={run.skippedCount ?? 0} />
      {run.manualChangesReverted && (run.manualChangesReverted.added || run.manualChangesReverted.removed) ? (
        <p className={ui.muted}>{t.activity.reverted(run.manualChangesReverted.removed ?? 0, run.manualChangesReverted.added ?? 0)}</p>
      ) : null}
      {run.excluded && (run.excluded.disabled || run.excluded.guests) ? (
        <p className={`${ui.muted} ${ui.small}`}>{t.activity.excluded(run.excluded.disabled ?? 0, run.excluded.guests ?? 0)}</p>
      ) : null}
      {run.compare && (
        <>
          <div className={ui.subhead}>{t.group.compare}</div>
          <div className={ui.muted}>{t.group.compareCounts(run.compare.onlyInRdgCount, run.compare.onlyInCompareCount)}</div>
        </>
      )}
      {(run.result === 'Blocked' || run.result === 'Error') && cause && (
        <>
          <div className={ui.subhead}>{t.activity.likelyCause}</div>
          <div className={ui.muted}>{t.activity.ruleChanged(sentenceWhen(cause.at), shortName(cause.by))}</div>
        </>
      )}
      <div className={`${ui.muted} ${ui.small}`} style={{ marginTop: 12 }}>
        {t.activity.engineVersion(run.engineVersion)}
      </div>
      <div className={s.actions}>
        {canApprove && (
          <Button appearance="primary" onClick={() => setApproveOpen(true)}>
            {t.group.approveOnce}
          </Button>
        )}
        {run.definitionId && <AppLink to={`/groups/${run.definitionId}`}>{t.activity.openGroup}</AppLink>}
        {run.jobUrl && (
          <Link href={run.jobUrl} target="_blank" rel="noreferrer">
            {t.activity.automationJob}
          </Link>
        )}
      </div>
      {definition.data && definition.data.status?.pendingApproval && (
        <ApproveDialog
          definition={definition.data}
          open={approveOpen}
          onClose={() => setApproveOpen(false)}
          onApproved={() => notify(t.group.approvedToast, 'success')}
        />
      )}
    </aside>
  );
}
