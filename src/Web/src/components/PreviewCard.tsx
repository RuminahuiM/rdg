// Preview: who would be a member now (POST /preview), the diff against the current group,
// filtered users, the Exchange check and whether the change limit would block.
import { useState } from 'react';
import { Button, Link, makeStyles, tokens } from '@fluentui/react-components';
import { usePreview } from '../api/hooks';
import type { GroupType, PreviewInput, PreviewResult, UserRef } from '../api/types';
import { ApiError } from '../api/client';
import { Section, useUiStyles } from './ui';
import { Badge } from './StatusBadge';
import { timeOnly } from '../format';
import { t } from '../strings/en';

const useStyles = makeStyles({
  stats: { display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '8px', textAlign: 'center', marginBottom: '8px' },
  stat: { backgroundColor: tokens.colorNeutralBackground2, borderRadius: tokens.borderRadiusLarge, padding: '10px 6px' },
  value: { fontSize: tokens.fontSizeBase600, fontWeight: tokens.fontWeightSemibold, lineHeight: tokens.lineHeightBase600 },
  person: { display: 'flex', justifyContent: 'space-between', gap: '8px', alignItems: 'center', minWidth: 0 },
  upn: { color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase200, overflow: 'hidden', textOverflow: 'ellipsis' },
  limit: { display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap', marginTop: '16px' },
  big: { display: 'flex', alignItems: 'baseline', gap: '8px' },
});

const FIRST = 5;

function People({
  title,
  users,
  total,
  badge,
}: {
  title: string;
  users: UserRef[];
  total: number;
  badge?: (u: UserRef) => string | undefined;
}) {
  const s = useStyles();
  const ui = useUiStyles();
  const [all, setAll] = useState(false);
  if (total === 0) return null;
  const shown = all ? users : users.slice(0, FIRST);
  return (
    <>
      <div className={ui.subhead}>{title}</div>
      <ul className={ui.list}>
        {shown.map((user) => (
          <li key={user.id} className={s.person}>
            <span>{user.displayName || user.upn}</span>
            {badge?.(user) ? (
              <Badge tone="warn" dot={false}>
                {badge(user)}
              </Badge>
            ) : (
              <span className={s.upn}>{user.upn}</span>
            )}
          </li>
        ))}
      </ul>
      {!all && users.length > FIRST && (
        <Link as="button" onClick={() => setAll(true)} style={{ marginTop: 6 }}>
          {t.common.showAll(users.length)}
        </Link>
      )}
      {all && total > users.length && <div className={ui.muted}>{t.preview.more(total - users.length)}</div>}
    </>
  );
}

export function PreviewResultView({ result, groupType, at }: { result: PreviewResult; groupType: GroupType; at: string }) {
  const s = useStyles();
  const ui = useUiStyles();
  const exchange = groupType === 'MailEnabledSecurity' || groupType === 'Distribution';
  const filtered = result.excluded.filter((e) => e.reason !== 'noExchangeRecipient');
  const reasons = new Map(result.excluded.map((e) => [e.user.id, t.preview.reason[e.reason] ?? e.reason]));
  const diff = result.diff;
  const changes = diff ? diff.addCount + diff.removeCount : 0;
  const current = diff ? result.memberCount - diff.addCount + diff.removeCount : 0;

  return (
    <div data-testid="preview-result">
      <div className={`${ui.muted} ${ui.small}`} style={{ marginBottom: 8 }}>
        {t.preview.basedOn(timeOnly(at))}
      </div>
      {diff ? (
        <div className={s.stats}>
          <div className={s.stat}>
            <div className={s.value}>{result.memberCount}</div>
            <div className={`${ui.muted} ${ui.small}`}>{t.preview.members}</div>
          </div>
          <div className={s.stat}>
            <div className={s.value}>+{diff.addCount}</div>
            <div className={`${ui.muted} ${ui.small}`}>{t.preview.toAdd}</div>
          </div>
          <div className={s.stat}>
            <div className={s.value}>{diff.removeCount}</div>
            <div className={`${ui.muted} ${ui.small}`}>{t.preview.toRemove}</div>
          </div>
        </div>
      ) : (
        <>
          <div className={s.big}>
            <span className={ui.stat}>{result.memberCount}</span>
            <span className={ui.muted}>{t.preview.usersWouldBe}</span>
          </div>
          {result.excludedCounts.disabled + result.excludedCounts.guest > 0 && (
            <div className={`${ui.muted} ${ui.small}`}>
              {t.preview.excludedSummary(result.excludedCounts.disabled, result.excludedCounts.guest)}
            </div>
          )}
        </>
      )}

      {diff ? (
        <>
          <People title={t.preview.wouldBeAdded} users={diff.adds} total={diff.addCount} />
          <People title={t.preview.wouldBeRemoved} users={diff.removes} total={diff.removeCount} />
        </>
      ) : (
        <People title={t.preview.membersTitle} users={result.members} total={result.memberCount} />
      )}
      {diff && (
        <People
          title={t.preview.excluded(result.excludedCounts.disabled + result.excludedCounts.guest + result.excludedCounts.excludeList)}
          users={filtered.map((e) => e.user)}
          total={result.excludedCounts.disabled + result.excludedCounts.guest + result.excludedCounts.excludeList}
          badge={(u) => reasons.get(u.id)}
        />
      )}

      {exchange && (
        <>
          <div className={ui.subhead}>{t.preview.exchangeCheck}</div>
          <div className={ui.muted}>
            {result.excludedCounts.noExchangeRecipient === 0
              ? t.preview.exchangeAllMail(result.memberCount)
              : t.preview.exchangeMissing(result.excludedCounts.noExchangeRecipient)}
          </div>
        </>
      )}

      {result.compare && (
        <>
          <div className={ui.subhead}>{t.preview.compare}</div>
          <div className={ui.muted}>{t.group.compareCounts(result.compare.onlyInRdgCount, result.compare.onlyInCompareCount)}</div>
          <People title={t.preview.onlyHere} users={result.compare.onlyInRdg} total={result.compare.onlyInRdgCount} />
          <People title={t.preview.onlyThere} users={result.compare.onlyInCompare} total={result.compare.onlyInCompareCount} />
        </>
      )}

      {diff && (
        <div className={s.limit}>
          {result.changeLimit.wouldBlock ? (
            <Badge tone="err">{t.preview.wouldBlock}</Badge>
          ) : (
            <Badge tone="ok">{t.preview.withinLimit}</Badge>
          )}
          <span className={`${ui.muted} ${ui.small}`}>
            {t.preview.limitDetail(changes, result.changeLimit.percent, current)} · {t.preview.limitOf(result.changeLimit.limitPercent)}
          </span>
        </div>
      )}
      {result.emptyResult.wouldBlock && (
        <div className={s.limit} data-testid="preview-empty-block">
          <Badge tone="err">{t.preview.wouldBlockEmpty}</Badge>
          <span className={`${ui.muted} ${ui.small}`}>{t.preview.emptyDetail(result.emptyResult.currentMembers)}</span>
        </div>
      )}
      {result.warnings.length > 0 && (
        <ul className={ui.list} style={{ marginTop: 12 }}>
          {result.warnings.map((w) => (
            <li key={w} className={ui.muted}>
              {w}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function PreviewCard({
  input,
  groupType,
  canRun,
  readerNote,
}: {
  /** Builds the request when the button is pressed (saved definition or the unsaved form). */
  input: () => PreviewInput | null;
  groupType: GroupType;
  canRun: boolean;
  readerNote?: boolean;
}) {
  const ui = useUiStyles();
  const preview = usePreview();
  const [at, setAt] = useState<string | null>(null);
  const run = () => {
    const body = input();
    if (!body) return;
    preview.mutate(body, { onSuccess: () => setAt(new Date().toISOString()) });
  };
  const error = preview.error;
  return (
    <Section
      title={t.preview.title}
      labelId="preview-title"
      actions={
        <Button onClick={run} disabled={!canRun || preview.isPending}>
          {preview.isPending ? t.preview.running : t.preview.run}
        </Button>
      }
    >
      {preview.data && at ? (
        <PreviewResultView result={preview.data} groupType={groupType} at={at} />
      ) : error ? (
        <div role="alert" className={ui.muted}>
          {error instanceof ApiError && error.status === 400
            ? (error.problem.errors ?? []).some((e) => e.field.startsWith('definition.rule'))
              ? t.preview.fixRuleFirst
              : t.preview.cantPreview(error.problem.detail ?? error.problem.title)
            : error instanceof ApiError && error.status === 429
              ? t.error.throttled(error.problem.retryAfterSeconds ?? 30)
              : t.error.detail}
        </div>
      ) : (
        <p className={`${ui.muted} ${ui.small}`} style={{ margin: 0 }}>
          {readerNote ? t.preview.readerNote : t.preview.intro}
        </p>
      )}
    </Section>
  );
}
