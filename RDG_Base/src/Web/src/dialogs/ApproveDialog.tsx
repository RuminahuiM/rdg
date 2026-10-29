// One-time approval of exactly one diff (blocked by the change limit, or an adoption).
import { useState } from 'react';
import {
  Button,
  Checkbox,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Link,
  MessageBar,
  MessageBarBody,
  makeStyles,
  tokens,
} from '@fluentui/react-components';
import { useApproveDefinition, useDefinitionRuns, useSettings } from '../api/hooks';
import type { Definition, UserRef } from '../api/types';
import { useSession } from '../auth/session';
import { ApiError } from '../api/client';
import { useUiStyles } from '../components/ui';
import { atWhen, shortName } from '../format';
import { t } from '../strings/en';

const useStyles = makeStyles({
  stats: { display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '8px', margin: '16px 0' },
  stat: { backgroundColor: tokens.colorNeutralBackground2, borderRadius: tokens.borderRadiusLarge, padding: '12px', textAlign: 'center' },
  value: { fontSize: tokens.fontSizeBase600, fontWeight: tokens.fontWeightSemibold, lineHeight: tokens.lineHeightBase600 },
  person: { display: 'flex', justifyContent: 'space-between', gap: '8px' },
  covers: { margin: '16px 0 12px', fontSize: tokens.fontSizeBase300 },
  scroll: { maxHeight: '240px', overflowY: 'auto' },
});

const FIRST = 5;

function UserList({
  titleFirst,
  titleAll,
  users,
  total,
}: {
  titleFirst: (s: number, n: number) => string;
  titleAll: (n: number) => string;
  users: UserRef[];
  total: number;
}) {
  const s = useStyles();
  const ui = useUiStyles();
  const [all, setAll] = useState(false);
  if (total === 0) return null;
  const shown = all ? users : users.slice(0, FIRST);
  return (
    <>
      <div className={ui.subhead}>{all || users.length <= FIRST ? titleAll(total) : titleFirst(shown.length, total)}</div>
      <ul className={`${ui.list} ${s.scroll}`}>
        {shown.map((user) => (
          <li key={user.id} className={s.person}>
            <span>{user.displayName || user.upn}</span>
            <span className={`${ui.muted} ${ui.small}`}>{user.upn}</span>
          </li>
        ))}
      </ul>
      {!all && users.length > FIRST && (
        <Link as="button" onClick={() => setAll(true)} style={{ marginTop: 6 }}>
          {t.approve.showAllUsers(users.length)}
        </Link>
      )}
    </>
  );
}

export function ApproveDialog({
  definition,
  open,
  onClose,
  onApproved,
}: {
  definition: Definition;
  open: boolean;
  onClose: () => void;
  onApproved?: () => void;
}) {
  const s = useStyles();
  const ui = useUiStyles();
  const { me, readOnly } = useSession();
  const pending = definition.status?.pendingApproval;
  const runs = useDefinitionRuns(open ? definition.id : undefined);
  const approve = useApproveDefinition();
  const settings = useSettings();
  const [checked, setChecked] = useState(false);
  if (!pending) return null;

  // The user lists come from the run that found this diff.
  const run =
    runs.data?.find((r) => r.approval?.diffHash === pending.diffHash) ?? runs.data?.find((r) => r.id === definition.status?.lastRunId);
  const adopt = pending.kind === 'adopt';
  const members = definition.status?.memberCount ?? 0;
  const limit = definition.changeLimitPercent ?? settings.data?.changeLimitPercent;
  const changes = pending.adds + pending.removes;
  const conflict = approve.error instanceof ApiError && approve.error.status === 409;

  const submit = () =>
    approve.mutate(
      { id: definition.id, kind: pending.kind, diffHash: pending.diffHash },
      {
        onSuccess: () => {
          setChecked(false);
          onApproved?.();
          onClose();
        },
      },
    );

  return (
    <Dialog open={open} onOpenChange={(_, data) => !data.open && onClose()} modalType="modal">
      <DialogSurface aria-describedby="approve-subtitle">
        <DialogBody>
          <DialogTitle>{adopt ? t.approve.titleAdopt : t.approve.title}</DialogTitle>
          <DialogContent>
            <p id="approve-subtitle" className={ui.muted} style={{ margin: 0 }}>
              {adopt
                ? t.approve.subtitleAdopt(definition.name)
                : t.approve.subtitle(definition.name, pending.detectedAt ? atWhen(pending.detectedAt) : '')}
            </p>
            <div className={s.stats}>
              <div className={s.stat}>
                <div className={s.value}>+{pending.adds}</div>
                <div className={`${ui.muted} ${ui.small}`}>{t.approve.toAdd}</div>
              </div>
              <div className={s.stat}>
                <div className={s.value}>{pending.removes ? `−${pending.removes}` : 0}</div>
                <div className={`${ui.muted} ${ui.small}`}>{t.approve.toRemove}</div>
              </div>
              <div className={s.stat}>
                <div className={s.value}>{Math.round(pending.percent)} %</div>
                <div className={`${ui.muted} ${ui.small}`}>{t.approve.ofMembers(members)}</div>
              </div>
              <div className={s.stat}>
                <div className={s.value}>{limit ? `${limit} %` : '–'}</div>
                <div className={`${ui.muted} ${ui.small}`}>{t.approve.limit}</div>
              </div>
            </div>
            {run ? (
              <>
                <UserList
                  titleFirst={t.approve.usersToAdd}
                  titleAll={t.approve.usersToAddAll}
                  users={run.added ?? []}
                  total={pending.adds}
                />
                <UserList
                  titleFirst={t.approve.usersToRemove}
                  titleAll={t.approve.usersToRemoveAll}
                  users={run.removed ?? []}
                  total={pending.removes}
                />
              </>
            ) : (
              !runs.isPending && <p className={ui.muted}>{t.approve.listUnavailable}</p>
            )}
            <p className={s.covers}>{t.approve.covers(changes, shortName(me.upn))}</p>
            {readOnly ? (
              <MessageBar intent="warning">
                <MessageBarBody>{t.approve.readOnly}</MessageBarBody>
              </MessageBar>
            ) : (
              <Checkbox checked={checked} onChange={(_, data) => setChecked(Boolean(data.checked))} label={t.approve.confirm} />
            )}
            {approve.error && (
              <MessageBar intent="error" style={{ marginTop: 12 }}>
                <MessageBarBody>
                  {conflict ? t.approve.stale : approve.error instanceof ApiError ? approve.error.message : t.error.detail}
                </MessageBarBody>
              </MessageBar>
            )}
          </DialogContent>
          <DialogActions>
            <Button onClick={onClose}>{t.common.cancel}</Button>
            <Button appearance="primary" disabled={!checked || readOnly || approve.isPending} onClick={submit}>
              {adopt ? t.approve.approveAdopt : t.approve.approve}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
