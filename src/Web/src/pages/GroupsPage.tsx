// Groups: result counts, filters, the table of definitions, and the empty state.
import { useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import {
  Button,
  Field,
  Input,
  Select,
  Spinner,
  ToggleButton,
  makeStyles,
  mergeClasses,
  shorthands,
  tokens,
} from '@fluentui/react-components';
import { useDefinitions, useSettings, useUpdateDefinition, toInput } from '../api/hooks';
import type { Definition, GroupType, SyncResult } from '../api/types';
import { useSession } from '../auth/session';
import { DefinitionBadge, definitionResult } from '../components/StatusBadge';
import { PageHeader, Section, useUiStyles } from '../components/ui';
import { useSyncNow } from '../components/sync';
import { useNotify } from '../components/notify';
import { ApiError } from '../api/client';
import { ErrorView } from './ErrorPages';
import { shortWhen, timeOnly } from '../format';
import { t } from '../strings/en';
import { lastRunText, targetText } from '../components/definitionText';

const useStyles = makeStyles({
  counts: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: '12px' },
  count: {
    textAlign: 'left',
    padding: '14px 16px',
    cursor: 'pointer',
    fontFamily: 'inherit',
    fontSize: 'inherit',
    color: 'inherit',
    ':hover': { ...shorthands.borderColor(tokens.colorNeutralStroke1Hover) },
    ':focus-visible': { outlineWidth: '2px', outlineStyle: 'solid', outlineColor: tokens.colorStrokeFocus2 },
  },
  countActive: { ...shorthands.borderColor(tokens.colorBrandStroke1), boxShadow: `inset 0 0 0 1px ${tokens.colorBrandStroke1}` },
  countLabel: { fontSize: tokens.fontSizeBase200, color: tokens.colorNeutralForeground3 },
  countValue: { fontSize: '26px', fontWeight: tokens.fontWeightSemibold, marginTop: '2px', lineHeight: '32px' },
  warn: { color: tokens.colorPaletteDarkOrangeForeground1 },
  err: { color: tokens.colorPaletteRedForeground1 },
  info: { color: tokens.colorBrandForeground1 },
  filters: { display: 'flex', flexWrap: 'wrap', gap: '12px', alignItems: 'flex-end' },
  search: { width: '240px' },
  tableWrap: { overflowX: 'auto' },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: tokens.fontSizeBase300,
    '& th': {
      textAlign: 'left',
      fontWeight: tokens.fontWeightSemibold,
      color: tokens.colorNeutralForeground2,
      padding: '10px 10px',
      borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
      whiteSpace: 'nowrap',
      fontSize: tokens.fontSizeBase200,
    },
    '& td': { padding: '11px 10px', borderBottom: `1px solid ${tokens.colorNeutralStroke3}`, whiteSpace: 'nowrap' },
    '& td.wrap': { whiteSpace: 'normal', minWidth: '110px' },
    '& tr:last-child td': { borderBottom: 0 },
    '& tbody tr:hover td': { backgroundColor: tokens.colorSubtleBackgroundHover },
  },
  name: {
    fontWeight: tokens.fontWeightSemibold,
    color: tokens.colorBrandForegroundLink,
    textDecoration: 'none',
    ':hover': { textDecoration: 'underline' },
  },
  num: { textAlign: 'right' },
  footer: { margin: 0, fontSize: tokens.fontSizeBase200, color: tokens.colorNeutralForeground3 },
  emptySteps: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '16px' },
  step: { display: 'flex', gap: '10px', alignItems: 'flex-start' },
  num2: {
    width: '22px',
    height: '22px',
    borderRadius: '50%',
    backgroundColor: tokens.colorBrandBackground2,
    color: tokens.colorBrandForeground2,
    fontSize: tokens.fontSizeBase200,
    fontWeight: tokens.fontWeightSemibold,
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    flex: 'none',
  },
});

const summary: { key: SyncResult; tone?: 'warn' | 'err' | 'info' }[] = [
  { key: 'OK' },
  { key: 'Warning', tone: 'warn' },
  { key: 'Blocked', tone: 'err' },
  { key: 'Error', tone: 'err' },
  { key: 'WaitingForApproval', tone: 'info' },
];

const attention = (d: Definition) =>
  d.enabled && (['Blocked', 'Error', 'WaitingForApproval'].includes(d.status?.lastResult ?? '') || Boolean(d.status?.manualChangeDetected));

function EmptyState({ isAdmin, onNew }: { isAdmin: boolean; onNew: () => void }) {
  const ui = useUiStyles();
  const s = useStyles();
  const steps = [
    [t.empty.step1, t.empty.step1Detail],
    [t.empty.step2, t.empty.step2Detail],
    [t.empty.step3, t.empty.step3Detail],
  ];
  return (
    <>
      <Section title={t.empty.title} labelId="empty-title">
        <p className={ui.muted} style={{ marginTop: 0 }}>
          {isAdmin ? t.empty.intro : t.empty.readerIntro}
        </p>
        <div className={ui.row}>
          {isAdmin && (
            <Button appearance="primary" onClick={onNew}>
              {t.groups.newGroup}
            </Button>
          )}
          <Button as="a" href="https://learn.microsoft.com/entra/identity/users/groups-dynamic-membership" target="_blank" rel="noreferrer">
            {t.empty.ruleReference}
          </Button>
        </div>
      </Section>
      <Section>
        <div className={s.emptySteps}>
          {steps.map(([title, detail], index) => (
            <div className={s.step} key={title}>
              <span className={s.num2}>{index + 1}</span>
              <div>
                <div style={{ fontWeight: 600 }}>{title}</div>
                <div className={ui.muted}>{detail}</div>
              </div>
            </div>
          ))}
        </div>
      </Section>
    </>
  );
}

export function GroupsPage() {
  const s = useStyles();
  const ui = useUiStyles();
  const navigate = useNavigate();
  const { isAdmin } = useSession();
  const definitions = useDefinitions();
  const settings = useSettings();
  const [params, setParams] = useSearchParams();
  const sync = useSyncNow();
  const update = useUpdateDefinition();
  const notify = useNotify();

  const search = params.get('search') ?? '';
  const type = params.get('type') ?? '';
  const result = params.get('result') ?? '';
  const needsAttention = params.get('attention') === '1';
  const setParam = (key: string, value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };

  const all = useMemo(() => definitions.data ?? [], [definitions.data]);
  const counts = useMemo(() => {
    const map: Record<string, number> = {};
    for (const d of all) {
      if (!d.enabled || !d.status) continue;
      map[d.status.lastResult] = (map[d.status.lastResult] ?? 0) + 1;
    }
    return map;
  }, [all]);
  const attentionCount = all.filter(attention).length;
  const rows = all
    .filter((d) => {
      const text = search.toLowerCase();
      return (
        (!text || d.name.toLowerCase().includes(text) || (d.target.displayName ?? '').toLowerCase().includes(text)) &&
        (!type || d.groupType === type) &&
        (!result || (d.enabled && d.status?.lastResult === result)) &&
        (!needsAttention || attention(d))
      );
    })
    .sort((a, b) => a.name.localeCompare(b.name));

  const [enabling, setEnabling] = useState<string | null>(null);
  const enable = (d: Definition) => {
    setEnabling(d.id);
    update.mutate(
      { id: d.id, etag: d.etag, input: { ...toInput(d), enabled: true } },
      {
        onSuccess: () => notify(t.groups.enabled(d.name), 'success'),
        onError: (error) => notify(error instanceof ApiError ? error.message : t.error.detail, 'error'),
        onSettled: () => setEnabling(null),
      },
    );
  };

  if (definitions.isPending) return <Spinner label={t.app.loading} />;
  if (definitions.error) return <ErrorView error={definitions.error} onRetry={() => void definitions.refetch()} />;

  const header = (
    <PageHeader
      title={t.groups.title}
      intro={t.groups.intro}
      actions={
        isAdmin && (
          <Button appearance="primary" onClick={() => navigate('/groups/new')}>
            {t.groups.newGroup}
          </Button>
        )
      }
    />
  );

  if (all.length === 0) {
    return (
      <div className={ui.page}>
        <PageHeader title={t.groups.title} />
        <EmptyState isAdmin={isAdmin} onNew={() => navigate('/groups/new')} />
      </div>
    );
  }

  const nextTick = (() => {
    const now = new Date();
    const next = new Date(now);
    next.setSeconds(0, 0);
    next.setMinutes(now.getMinutes() - (now.getMinutes() % 15) + 15);
    return next.toISOString();
  })();

  return (
    <div className={ui.page}>
      {header}

      <div className={s.counts} role="group" aria-label={t.groups.summaryLabel}>
        {summary.map(({ key, tone }) => (
          <button
            type="button"
            key={key}
            className={mergeClasses(ui.card, s.count, result === key && s.countActive)}
            aria-pressed={result === key}
            onClick={() => setParam('result', result === key ? '' : key)}
          >
            <div className={s.countLabel}>{t.result[key]}</div>
            <div className={mergeClasses(s.countValue, tone && (counts[key] ?? 0) > 0 && s[tone])}>{counts[key] ?? 0}</div>
          </button>
        ))}
      </div>

      <div className={s.filters}>
        <Field label={t.groups.searchLabel}>
          <Input
            className={s.search}
            type="search"
            placeholder={t.groups.searchPlaceholder}
            value={search}
            onChange={(_, data) => setParam('search', data.value)}
          />
        </Field>
        <Field label={t.groups.typeLabel}>
          <Select value={type} onChange={(_, data) => setParam('type', data.value)}>
            <option value="">{t.groups.allTypes}</option>
            {(['Security', 'Microsoft365', 'MailEnabledSecurity', 'Distribution'] as GroupType[]).map((g) => (
              <option key={g} value={g}>
                {t.groupType[g]}
              </option>
            ))}
          </Select>
        </Field>
        <Field label={t.groups.resultLabel}>
          <Select value={result} onChange={(_, data) => setParam('result', data.value)}>
            <option value="">{t.groups.allResults}</option>
            {(['OK', 'Warning', 'Blocked', 'Error', 'DryRun', 'WaitingForApproval'] as SyncResult[]).map((r) => (
              <option key={r} value={r}>
                {t.result[r]}
              </option>
            ))}
          </Select>
        </Field>
        <ToggleButton checked={needsAttention} onClick={() => setParam('attention', needsAttention ? '' : '1')}>
          {t.groups.needsAttention(attentionCount)}
        </ToggleButton>
      </div>

      <Section flush>
        <div className={s.tableWrap}>
          <table className={s.table}>
            <thead>
              <tr>
                <th scope="col">{t.groups.columns.name}</th>
                <th scope="col">{t.groups.columns.type}</th>
                <th scope="col">{t.groups.columns.target}</th>
                <th scope="col">{t.groups.columns.frequency}</th>
                <th scope="col">{t.groups.columns.result}</th>
                <th scope="col" className={s.num}>
                  {t.groups.columns.members}
                </th>
                <th scope="col">{t.groups.columns.lastRun}</th>
                <th scope="col">{t.groups.columns.lastSync}</th>
                {isAdmin && (
                  <th scope="col">
                    <span className={ui.visuallyHidden}>{t.groups.columns.actions}</span>
                  </th>
                )}
              </tr>
            </thead>
            <tbody>
              {rows.map((d) => {
                const syncing = sync.isSyncing(d.id);
                const { result: shown } = definitionResult(d, syncing);
                const review = shown === 'Blocked' || shown === 'WaitingForApproval';
                return (
                  <tr key={d.id}>
                    <td className="wrap">
                      <Link className={s.name} to={`/groups/${d.id}`}>
                        {d.name}
                      </Link>
                    </td>
                    <td className="wrap">{t.groupType[d.groupType]}</td>
                    <td className={mergeClasses('wrap', ui.muted)}>{targetText(d)}</td>
                    <td>{t.frequency(d.frequencyMinutes)}</td>
                    <td>
                      <DefinitionBadge definition={d} syncing={syncing} />
                    </td>
                    <td className={s.num}>{d.status ? d.status.memberCount : t.common.dash}</td>
                    <td>{lastRunText(d)}</td>
                    <td className={ui.muted}>{shortWhen(d.status?.lastSyncUtc)}</td>
                    {isAdmin && (
                      <td>
                        {!d.enabled ? (
                          <Button
                            size="small"
                            onClick={() => enable(d)}
                            disabled={enabling === d.id}
                            aria-label={`${t.groups.enable} ${d.name}`}
                          >
                            {t.groups.enable}
                          </Button>
                        ) : review ? (
                          <Button
                            size="small"
                            onClick={() => navigate(`/groups/${d.id}?review=1`)}
                            aria-label={`${t.groups.review} ${d.name}`}
                          >
                            {t.groups.review}
                          </Button>
                        ) : (
                          <Button
                            size="small"
                            onClick={() => sync.start(d)}
                            disabled={syncing}
                            aria-label={`${t.groups.syncNow} ${d.name}`}
                          >
                            {t.groups.syncNow}
                          </Button>
                        )}
                      </td>
                    )}
                  </tr>
                );
              })}
              {rows.length === 0 && (
                <tr>
                  <td colSpan={isAdmin ? 9 : 8} className={ui.muted}>
                    {t.groups.noMatch}{' '}
                    <Button appearance="transparent" size="small" onClick={() => setParams(new URLSearchParams(), { replace: true })}>
                      {t.groups.clearFilters}
                    </Button>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </Section>
      <p className={s.footer}>
        {t.groups.showing(rows.length, all.length)}
        {settings.data && !settings.data.paused ? ` ${t.groups.nextRun(timeOnly(nextTick))}` : ''}
      </p>
    </div>
  );
}
