// Audit: who changed what and when, for definitions and settings (mockup Audit).
import { useMemo, useState, type ReactNode } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Field, Input, Select, Spinner, makeStyles, tokens } from '@fluentui/react-components';
import { useAudit, useDefinitions } from '../api/hooks';
import type { AuditEntry } from '../api/types';
import { useSession } from '../auth/session';
import { AppLink } from '../components/AppLink';
import { PageHeader, Section, useUiStyles } from '../components/ui';
import { useDebounced } from '../components/useDebounced';
import { ErrorView } from './ErrorPages';
import { longWhen, shortName } from '../format';
import { t } from '../strings/en';

const PERIODS = { '7d': 7, '30d': 30, all: 0 } as const;
type Period = keyof typeof PERIODS;

const useStyles = makeStyles({
  filters: { display: 'flex', flexWrap: 'wrap', gap: '12px', alignItems: 'flex-end' },
  tableWrap: { overflowX: 'auto' },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    fontSize: tokens.fontSizeBase300,
    '& th': {
      textAlign: 'left',
      fontWeight: tokens.fontWeightSemibold,
      color: tokens.colorNeutralForeground2,
      padding: '10px 12px',
      borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
      whiteSpace: 'nowrap',
      fontSize: tokens.fontSizeBase200,
    },
    '& td': { padding: '11px 12px', borderBottom: `1px solid ${tokens.colorNeutralStroke3}`, verticalAlign: 'top' },
    '& tr:last-child td': { borderBottom: 0 },
  },
  nowrap: { whiteSpace: 'nowrap' },
  change: { display: 'flex', flexDirection: 'column', gap: '4px', minWidth: '280px' },
});

const fieldLabels: Record<string, string> = {
  ...t.conflict.fields,
  paused: t.settings.pause,
  verboseLogging: t.settings.verbose,
  changeLimitMinChanges: t.settings.minChangesLabel,
  newGroupsDryRun: t.settings.newDryRun,
  nestedMembers: t.settings.nested,
  frequencyOptions: t.settings.frequencyOptions,
  'naming.prefix': t.settings.prefix,
  naming: t.settings.naming,
  marker: t.settings.marker,
  auditRetentionDays: t.settings.retention,
  approval: t.audit.action.approve,
};

/** A stored value as short text: on/off, minutes, names, counts. */
export function formatValue(field: string, value: unknown): string {
  if (value === null || value === undefined || value === '') return t.common.none;
  if (typeof value === 'boolean') return value ? t.common.on : t.common.off;
  if (field === 'frequencyMinutes' && typeof value === 'number') return t.frequency(value);
  if (field === 'frequencyOptions' && Array.isArray(value)) return value.map((m) => t.frequency(Number(m))).join(', ');
  if ((field === 'changeLimitPercent' || field === 'percent') && typeof value === 'number') return `${value} %`;
  if (field === 'groupType' && typeof value === 'string') return t.groupType[value] ?? value;
  if (Array.isArray(value)) return t.audit.users(value.length);
  if (typeof value === 'object') {
    const o = value as Record<string, unknown>;
    if ('mode' in o)
      return `${String(o.displayName ?? o.groupId ?? '')} (${String(o.mode === 'create' ? t.group.modeCreate : o.mode === 'adopt' ? t.group.modeAdopt : t.group.modeExisting).toLowerCase()})`;
    if ('text' in o && 'enabled' in o) return o.enabled && o.text ? String(o.text) : t.common.none;
    return Object.entries(o)
      .map(([k, v]) => `${k} ${formatValue(k, v)}`)
      .join(', ');
  }
  return String(value);
}

export function actionLabel(entry: AuditEntry): string {
  const fields = entry.changes.map((c) => c.field);
  if (entry.action === 'settings' && fields.length === 1 && fields[0] === 'paused') {
    return entry.changes[0]?.new ? t.audit.action.paused : t.audit.action.resumed;
  }
  if (entry.action === 'update' && fields.length === 1 && fields[0] === 'rule') return t.audit.action.updateRule;
  return t.audit.action[entry.action];
}

function Change({ entry }: { entry: AuditEntry }): ReactNode {
  const ui = useUiStyles();
  const s = useStyles();
  if (entry.action === 'syncNow') return <span className={ui.muted}>{t.audit.syncNowDetail}</span>;
  if (entry.action === 'delete') return null;
  if (entry.action === 'approve') {
    const value = (entry.changes[0]?.new ?? {}) as { adds?: number; removes?: number };
    return <span>{t.audit.approvedDetail(value.adds ?? 0, value.removes ?? 0)}</span>;
  }
  if (entry.action === 'create' || entry.action === 'adopt') {
    const shown = entry.changes.filter((c) => ['groupType', 'frequencyMinutes', 'dryRun', 'target'].includes(c.field));
    return <span>{shown.map((c) => `${fieldLabels[c.field] ?? c.field} ${formatValue(c.field, c.new)}`).join(', ')}</span>;
  }
  return (
    <div className={s.change}>
      {entry.changes.map((c) => {
        const mono = c.field === 'rule';
        return (
          <div key={c.field} className={mono ? ui.mono : undefined}>
            {!mono && <>{fieldLabels[c.field] ?? c.field}: </>}
            <span className={ui.old}>{formatValue(c.field, c.old)}</span> → <span className={ui.new}>{formatValue(c.field, c.new)}</span>
          </div>
        );
      })}
    </div>
  );
}

export function AuditPage() {
  const s = useStyles();
  const ui = useUiStyles();
  const { isAdmin } = useSession();
  const [params, setParams] = useSearchParams();
  const definitionId = params.get('definitionId') ?? '';
  const period = (params.get('period') as Period | null) ?? '7d';
  const [by, setBy] = useState(params.get('by') ?? '');
  const byDebounced = useDebounced(by.trim(), 300);
  const filter = useMemo(() => {
    const days = PERIODS[period in PERIODS ? period : '7d'];
    return {
      definitionId: definitionId || undefined,
      by: byDebounced || undefined,
      from: days ? new Date(Date.now() - days * 86_400_000).toISOString() : undefined,
    };
  }, [definitionId, byDebounced, period]);
  const audit = useAudit(filter);
  const definitions = useDefinitions();
  const setParam = (key: string, value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };
  const items = audit.data ?? [];
  const known = new Set((definitions.data ?? []).map((d) => d.id));

  return (
    <div className={ui.page}>
      <PageHeader title={t.audit.title} intro={`${t.audit.intro}${isAdmin ? '' : t.audit.readerIntro}`} />
      <div className={s.filters}>
        <Field label={t.audit.group}>
          <Select value={definitionId} onChange={(_, data) => setParam('definitionId', data.value)}>
            <option value="">{t.audit.allGroups}</option>
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
        <Field label={t.audit.changedBy}>
          <Input type="search" placeholder={t.audit.changedByPlaceholder} value={by} onChange={(_, data) => setBy(data.value)} />
        </Field>
        <Field label={t.audit.period}>
          <Select value={period} onChange={(_, data) => setParam('period', data.value === '7d' ? '' : data.value)}>
            <option value="7d">{t.audit.last7d}</option>
            <option value="30d">{t.audit.last30d}</option>
            <option value="all">{t.audit.all}</option>
          </Select>
        </Field>
      </div>
      {audit.error ? (
        <ErrorView error={audit.error} onRetry={() => void audit.refetch()} />
      ) : (
        <Section flush>
          {audit.isPending ? (
            <div style={{ padding: 20 }}>
              <Spinner label={t.app.loading} />
            </div>
          ) : (
            <div className={s.tableWrap}>
              <table className={s.table}>
                <thead>
                  <tr>
                    <th scope="col">{t.audit.columns.when}</th>
                    <th scope="col">{t.audit.columns.who}</th>
                    <th scope="col">{t.audit.columns.action}</th>
                    <th scope="col">{t.audit.columns.group}</th>
                    <th scope="col">{t.audit.columns.change}</th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((entry) => (
                    <tr key={entry.id}>
                      <td className={s.nowrap}>{longWhen(entry.at)}</td>
                      <td className={s.nowrap} title={entry.by}>
                        {shortName(entry.by)}
                      </td>
                      <td className={s.nowrap}>{actionLabel(entry)}</td>
                      <td className={s.nowrap}>
                        {entry.definitionId ? (
                          known.has(entry.definitionId) ? (
                            <AppLink to={`/groups/${entry.definitionId}`}>{entry.definitionName}</AppLink>
                          ) : (
                            entry.definitionName
                          )
                        ) : (
                          <span className={ui.muted}>{t.audit.settings}</span>
                        )}
                      </td>
                      <td>
                        <Change entry={entry} />
                      </td>
                    </tr>
                  ))}
                  {items.length === 0 && (
                    <tr>
                      <td colSpan={5} className={ui.muted}>
                        {t.audit.noEntries}
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </Section>
      )}
    </div>
  );
}
