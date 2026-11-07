// Activity: every run of the last 30 days, with a side panel for one run (mockup Activity).
import { useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Field, Select, Spinner, makeStyles, mergeClasses, tokens } from '@fluentui/react-components';
import { useDefinitions, useRuns } from '../api/hooks';
import type { Run } from '../api/types';
import { ResultBadge } from '../components/StatusBadge';
import { PageHeader, Section, useUiStyles } from '../components/ui';
import { ErrorView } from './ErrorPages';
import { timeWhen } from '../format';
import { t } from '../strings/en';
import { RunPanel } from './RunPanel';

const PERIODS = { '24h': 1, '7d': 7, '30d': 30 } as const;
type Period = keyof typeof PERIODS;

const useStyles = makeStyles({
  filters: { display: 'flex', flexWrap: 'wrap', gap: '12px', alignItems: 'flex-end' },
  layout: { display: 'grid', gridTemplateColumns: 'minmax(0, 1fr)', gap: '16px', alignItems: 'start' },
  withPanel: {
    gridTemplateColumns: 'minmax(0, 1.6fr) minmax(300px, 1fr)',
    '@media (max-width: 1100px)': { gridTemplateColumns: 'minmax(0, 1fr)' },
  },
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
    '& tbody tr': { cursor: 'pointer' },
    '& tbody tr:hover td': { backgroundColor: tokens.colorSubtleBackgroundHover },
    '& tr:last-child td': { borderBottom: 0 },
  },
  selected: { '& td': { backgroundColor: tokens.colorBrandBackground2 } },
  rowButton: {
    background: 'none',
    border: 'none',
    padding: 0,
    fontFamily: 'inherit',
    fontSize: 'inherit',
    color: 'inherit',
    cursor: 'pointer',
    textAlign: 'left',
    ':focus-visible': { outlineWidth: '2px', outlineStyle: 'solid', outlineColor: tokens.colorStrokeFocus2 },
  },
});

function since(period: Period): string {
  return new Date(Date.now() - PERIODS[period] * 86_400_000).toISOString();
}

export function ActivityPage() {
  const s = useStyles();
  const ui = useUiStyles();
  const [params, setParams] = useSearchParams();
  const definitionId = params.get('definitionId') ?? '';
  const result = params.get('result') ?? '';
  const period = (params.get('period') as Period | null) ?? '24h';
  const selectedId = params.get('run');
  const filter = useMemo(
    () => ({ definitionId: definitionId || undefined, result: result || undefined, since: since(period in PERIODS ? period : '24h') }),
    [definitionId, result, period],
  );
  const runs = useRuns(filter);
  const definitions = useDefinitions();
  const setParam = (key: string, value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    if (key !== 'run') next.delete('run');
    setParams(next, { replace: true });
  };
  const items = runs.data ?? [];
  const selected = items.find((r) => r.id === selectedId);

  const cell = (run: Run, what: 'added' | 'removed' | 'skipped'): string => {
    if (run.result === 'SkippedTick' || run.result === 'Paused') return t.common.dash;
    if (what === 'added') {
      if (run.result === 'Blocked') return t.activity.held(run.approval?.adds ?? run.added?.length ?? 0);
      if (run.dryRun) return t.activity.would(run.approval?.adds ?? run.addedCount ?? run.added?.length ?? 0);
      return String(run.addedCount ?? 0);
    }
    if (what === 'removed') {
      if (run.result === 'Blocked') return t.activity.held(run.approval?.removes ?? run.removed?.length ?? 0);
      if (run.dryRun) return t.activity.would(run.approval?.removes ?? run.removedCount ?? run.removed?.length ?? 0);
      return String(run.removedCount ?? 0);
    }
    return String(run.skippedCount ?? 0);
  };

  return (
    <div className={ui.page}>
      <PageHeader title={t.activity.title} intro={t.activity.intro} />
      <div className={s.filters}>
        <Field label={t.activity.group}>
          <Select value={definitionId} onChange={(_, data) => setParam('definitionId', data.value)}>
            <option value="">{t.activity.allGroups}</option>
            {(definitions.data ?? [])
              .slice()
              .sort((a, b) => a.name.localeCompare(b.name))
              .map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name}
                </option>
              ))}
          </Select>
        </Field>
        <Field label={t.activity.result}>
          <Select value={result} onChange={(_, data) => setParam('result', data.value)}>
            <option value="">{t.activity.allResults}</option>
            {['OK', 'Warning', 'Blocked', 'Error', 'DryRun', 'WaitingForApproval', 'SkippedTick', 'Paused'].map((r) => (
              <option key={r} value={r}>
                {t.result[r]}
              </option>
            ))}
          </Select>
        </Field>
        <Field label={t.activity.period}>
          <Select value={period} onChange={(_, data) => setParam('period', data.value === '24h' ? '' : data.value)}>
            <option value="24h">{t.activity.last24h}</option>
            <option value="7d">{t.activity.last7d}</option>
            <option value="30d">{t.activity.last30d}</option>
          </Select>
        </Field>
      </div>
      {runs.error ? (
        <ErrorView error={runs.error} onRetry={() => void runs.refetch()} />
      ) : (
        <div className={mergeClasses(s.layout, selected && s.withPanel)}>
          <Section flush>
            {runs.isPending ? (
              <div style={{ padding: 20 }}>
                <Spinner label={t.app.loading} />
              </div>
            ) : (
              <div className={s.tableWrap}>
                <table className={s.table}>
                  <thead>
                    <tr>
                      <th scope="col">{t.activity.columns.time}</th>
                      <th scope="col">{t.activity.columns.group}</th>
                      <th scope="col">{t.activity.columns.runbook}</th>
                      <th scope="col">{t.activity.columns.result}</th>
                      <th scope="col">{t.activity.columns.added}</th>
                      <th scope="col">{t.activity.columns.removed}</th>
                      <th scope="col">{t.activity.columns.skipped}</th>
                      <th scope="col">{t.activity.columns.duration}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {items.map((run) => (
                      <tr
                        key={run.id}
                        className={run.id === selectedId ? s.selected : undefined}
                        onClick={() => setParam('run', run.id)}
                        aria-selected={run.id === selectedId}
                      >
                        <td>
                          <button
                            type="button"
                            className={s.rowButton}
                            onClick={() => setParam('run', run.id)}
                            aria-label={`${t.activity.details}: ${run.definitionName || t.activity.allSystem} ${timeWhen(run.startedAt)}`}
                          >
                            {timeWhen(run.startedAt)}
                          </button>
                        </td>
                        <td>{run.definitionName || t.activity.allSystem}</td>
                        <td className={ui.muted}>{run.runbook}</td>
                        <td>
                          <ResultBadge result={run.result} />
                        </td>
                        <td>{cell(run, 'added')}</td>
                        <td>{cell(run, 'removed')}</td>
                        <td>{cell(run, 'skipped')}</td>
                        <td className={ui.muted}>{t.activity.duration(run.durationMs)}</td>
                      </tr>
                    ))}
                    {items.length === 0 && (
                      <tr>
                        <td colSpan={8} className={ui.muted}>
                          {t.activity.noRuns}
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </Section>
          {selected && <RunPanel key={selected.id} run={selected} onClose={() => setParam('run', '')} />}
        </div>
      )}
    </div>
  );
}
