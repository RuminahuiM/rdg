// Organisation settings (mockup Settings). Readers see the same page with controls disabled.
import { useEffect, useState } from 'react';
import { Controller, useForm, useWatch } from 'react-hook-form';
import {
  Button,
  Input,
  MessageBar,
  MessageBarBody,
  Select,
  Spinner,
  Switch,
  Tag,
  TagGroup,
  makeStyles,
  tokens,
} from '@fluentui/react-components';
import { useSettings, useUpdateSettings } from '../api/hooks';
import type { Settings, SettingsInput } from '../api/types';
import { ApiError } from '../api/client';
import { useSession } from '../auth/session';
import { useNotify } from '../components/notify';
import { PageHeader, Section, useUiStyles } from '../components/ui';
import { ConflictDialog, type ConflictRow } from '../dialogs/ConflictDialog';
import { ErrorView } from './ErrorPages';
import { atWhen, shortName } from '../format';
import { t } from '../strings/en';

const LIMITS = [10, 20, 25, 30, 40, 50, 60, 75, 90, 100];

const useStyles = makeStyles({
  row: {
    display: 'flex',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: '16px',
    padding: '14px 0',
    borderTop: `1px solid ${tokens.colorNeutralStroke3}`,
    ':first-of-type': { borderTop: 'none', paddingTop: 0 },
  },
  text: { flex: '1 1 320px', minWidth: 0 },
  title: { fontSize: tokens.fontSizeBase300, fontWeight: tokens.fontWeightSemibold },
  sub: { fontSize: tokens.fontSizeBase200, color: tokens.colorNeutralForeground3, marginTop: '2px' },
  control: { display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' },
  chips: { display: 'flex', flexWrap: 'wrap', gap: '6px', alignItems: 'center', maxWidth: '520px' },
  small: { width: '96px' },
  error: { color: tokens.colorPaletteRedForeground1, fontSize: tokens.fontSizeBase200, width: '100%', textAlign: 'right' },
  footnote: { margin: 0, fontSize: tokens.fontSizeBase200, color: tokens.colorNeutralForeground3 },
});

export function toSettingsInput(settings: Settings): SettingsInput {
  const { etag: _etag, pausedAt: _pa, pausedBy: _pb, updatedAt: _ua, updatedBy: _ub, ...input } = settings;
  return structuredClone(input);
}

function Row({ title, sub, children }: { title: string; sub?: string; children: React.ReactNode }) {
  const s = useStyles();
  return (
    <div className={s.row}>
      <div className={s.text}>
        <div className={s.title}>{title}</div>
        {sub && <div className={s.sub}>{sub}</div>}
      </div>
      <div className={s.control}>{children}</div>
    </div>
  );
}

function settingsRows(theirs: SettingsInput, mine: SettingsInput): ConflictRow[] {
  const rows: ConflictRow[] = [];
  const label: Record<string, string> = {
    paused: t.settings.pause,
    verboseLogging: t.settings.verbose,
    changeLimitPercent: t.settings.changeLimit,
    changeLimitMinChanges: t.settings.minChangesLabel,
    newGroupsDryRun: t.settings.newDryRun,
    nestedMembers: t.settings.nested,
    frequencyOptions: t.settings.frequencyOptions,
    naming: t.settings.naming,
    marker: t.settings.marker,
    auditRetentionDays: t.settings.retention,
  };
  const text = (v: unknown) =>
    typeof v === 'boolean'
      ? v
        ? t.common.on
        : t.common.off
      : Array.isArray(v)
        ? v.join(', ')
        : typeof v === 'object'
          ? JSON.stringify(v)
          : String(v);
  for (const key of Object.keys(label) as (keyof SettingsInput)[]) {
    if (JSON.stringify(theirs[key]) !== JSON.stringify(mine[key]))
      rows.push({ field: label[key] ?? key, theirs: text(theirs[key]), mine: text(mine[key]) });
  }
  return rows;
}

export function SettingsPage() {
  const settings = useSettings();
  if (settings.isPending) return <Spinner label={t.app.loading} />;
  if (settings.error) return <ErrorView error={settings.error} onRetry={() => void settings.refetch()} />;
  return <SettingsForm settings={settings.data} reload={() => settings.refetch().then((r) => r.data)} />;
}

function SettingsForm({ settings, reload }: { settings: Settings; reload: () => Promise<Settings | undefined> }) {
  const s = useStyles();
  const ui = useUiStyles();
  const { isAdmin } = useSession();
  const notify = useNotify();
  const update = useUpdateSettings();
  const form = useForm<SettingsInput>({ defaultValues: toSettingsInput(settings) });
  const { control, handleSubmit, reset, formState, getValues, setValue } = form;
  const values = useWatch({ control }) as SettingsInput;
  const [baseEtag, setBaseEtag] = useState(settings.etag);
  const [newOption, setNewOption] = useState('');
  const [optionError, setOptionError] = useState(false);
  const [conflict, setConflict] = useState<Settings | null>(null);
  const [error, setError] = useState<string | null>(null);
  const disabled = !isAdmin;

  // The banner's "Resume syncing" saves elsewhere; take the new version if nothing is edited.
  useEffect(() => {
    if (settings.etag !== baseEtag && !formState.isDirty) {
      reset(toSettingsInput(settings));
      setBaseEtag(settings.etag);
    }
  }, [settings, baseEtag, formState.isDirty, reset]);

  const addOption = () => {
    const minutes = Number(newOption);
    const list = getValues('frequencyOptions');
    if (!Number.isInteger(minutes) || minutes < 3 || minutes > 1440 || list.includes(minutes)) {
      setOptionError(true);
      return;
    }
    setValue(
      'frequencyOptions',
      [...list, minutes].sort((a, b) => a - b),
      { shouldDirty: true },
    );
    setNewOption('');
    setOptionError(false);
  };

  const submit = handleSubmit((input) => {
    setError(null);
    update.mutate(
      { etag: baseEtag, input },
      {
        onSuccess: (saved) => {
          reset(toSettingsInput(saved));
          setBaseEtag(saved.etag);
          notify(t.settings.savedToast, 'success');
        },
        onError: (e) => {
          if (e instanceof ApiError && e.status === 412) void reload().then((latest) => setConflict(latest ?? null));
          else
            setError(
              e instanceof ApiError
                ? [e.problem.title, ...(e.problem.errors ?? []).map((x) => `${x.field}: ${x.message}`)].join(' ')
                : t.error.detail,
            );
        },
      },
    );
  });

  const sw = (name: 'paused' | 'verboseLogging' | 'newGroupsDryRun' | 'nestedMembers', label: string) => (
    <Controller
      name={name}
      control={control}
      render={({ field }) => (
        <Switch checked={field.value} onChange={(_, data) => field.onChange(data.checked)} aria-label={label} disabled={disabled} />
      )}
    />
  );

  return (
    <form className={ui.page} onSubmit={(e) => void submit(e)} noValidate aria-label={t.settings.title}>
      <PageHeader
        title={t.settings.title}
        intro={isAdmin ? t.settings.intro : t.settings.readerIntro}
        actions={
          isAdmin && (
            <Button appearance="primary" type="submit" disabled={!formState.isDirty || update.isPending}>
              {update.isPending ? t.common.saving : t.settings.save}
            </Button>
          )
        }
      />
      {error && (
        <MessageBar intent="error">
          <MessageBarBody>{error}</MessageBarBody>
        </MessageBar>
      )}

      <Section title={t.settings.sync} labelId="settings-sync">
        <Row title={t.settings.pause} sub={t.settings.pauseHint}>
          {sw('paused', t.settings.pause)}
        </Row>
        <Row title={t.settings.frequencyOptions} sub={t.settings.frequencyHint}>
          <div className={s.chips}>
            <TagGroup
              aria-label={t.settings.frequencyOptions}
              onDismiss={(_, data) => {
                const list = getValues('frequencyOptions');
                if (list.length > 1)
                  setValue(
                    'frequencyOptions',
                    list.filter((m) => String(m) !== data.value),
                    { shouldDirty: true },
                  );
              }}
              style={{ flexWrap: 'wrap', gap: 6 }}
            >
              {values.frequencyOptions.map((m) => (
                <Tag
                  key={m}
                  value={String(m)}
                  shape="rounded"
                  size="small"
                  dismissible={!disabled && values.frequencyOptions.length > 1}
                  dismissIcon={{ 'aria-label': t.common.remove(t.frequency(m)) }}
                >
                  {t.frequency(m)}
                </Tag>
              ))}
            </TagGroup>
            {!disabled && (
              <>
                <Input
                  className={s.small}
                  type="number"
                  min={3}
                  max={1440}
                  value={newOption}
                  aria-label={t.settings.optionMinutes}
                  placeholder={t.settings.optionPlaceholder}
                  onChange={(_, data) => {
                    setNewOption(data.value);
                    setOptionError(false);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      addOption();
                    }
                  }}
                />
                <Button onClick={addOption}>{t.settings.addOption}</Button>
              </>
            )}
            {optionError && (
              <div className={s.error} role="alert">
                {t.settings.optionInvalid}
              </div>
            )}
          </div>
        </Row>
        <Row title={t.settings.verbose} sub={t.settings.verboseHint}>
          {sw('verboseLogging', t.settings.verbose)}
        </Row>
      </Section>

      <Section title={t.settings.safety} labelId="settings-safety">
        <Row title={t.settings.changeLimit} sub={t.settings.changeLimitHint}>
          <Controller
            name="changeLimitPercent"
            control={control}
            render={({ field }) => (
              <Select
                aria-label={t.settings.changeLimit}
                value={String(field.value)}
                onChange={(_, data) => field.onChange(Number(data.value))}
                disabled={disabled}
              >
                {[...new Set([...LIMITS, field.value])]
                  .sort((a, b) => b - a)
                  .map((p) => (
                    <option key={p} value={p}>
                      {p} %
                    </option>
                  ))}
              </Select>
            )}
          />
        </Row>
        <Row title={t.settings.minChanges} sub={t.settings.minChangesHint}>
          <Controller
            name="changeLimitMinChanges"
            control={control}
            rules={{ min: 0, max: 10000 }}
            render={({ field, fieldState }) => (
              <Input
                className={s.small}
                type="number"
                min={0}
                max={10000}
                aria-label={t.settings.minChangesLabel}
                aria-invalid={fieldState.invalid || undefined}
                value={String(field.value)}
                onChange={(_, data) => field.onChange(data.value === '' ? 0 : Math.max(0, Math.min(10000, Math.trunc(Number(data.value)))))}
                disabled={disabled}
              />
            )}
          />
        </Row>
        <Row title={t.settings.newDryRun} sub={t.settings.newDryRunHint}>
          {sw('newGroupsDryRun', t.settings.newDryRun)}
        </Row>
      </Section>

      <Section title={t.settings.rules} labelId="settings-rules">
        <Row title={t.settings.nested} sub={t.settings.nestedHint}>
          {sw('nestedMembers', t.settings.nested)}
        </Row>
      </Section>

      <Section title={t.settings.naming} labelId="settings-naming">
        {(['prefix', 'suffix'] as const).map((which) => (
          <Row
            key={which}
            title={which === 'prefix' ? t.settings.prefix : t.settings.suffix}
            sub={which === 'prefix' ? t.settings.prefixHint : t.settings.suffixHint}
          >
            <Controller
              name={`naming.${which}.enabled`}
              control={control}
              render={({ field }) => (
                <Switch
                  checked={field.value}
                  onChange={(_, data) => field.onChange(data.checked)}
                  aria-label={which === 'prefix' ? t.settings.usePrefix : t.settings.useSuffix}
                  disabled={disabled}
                />
              )}
            />
            <Controller
              name={`naming.${which}.text`}
              control={control}
              render={({ field }) => (
                <Input
                  className={s.small}
                  value={field.value}
                  maxLength={20}
                  placeholder={t.common.none}
                  aria-label={which === 'prefix' ? t.settings.prefixText : t.settings.suffixText}
                  onChange={(_, data) => field.onChange(data.value)}
                  disabled={disabled || !values.naming[which].enabled}
                />
              )}
            />
          </Row>
        ))}
        <Row title={t.settings.marker} sub={t.settings.markerHint}>
          <Controller
            name="marker.enabled"
            control={control}
            render={({ field }) => (
              <Switch
                checked={field.value}
                onChange={(_, data) => field.onChange(data.checked)}
                aria-label={t.settings.useMarker}
                disabled={disabled}
              />
            )}
          />
          <Controller
            name="marker.exchangeCustomAttribute"
            control={control}
            render={({ field }) => (
              <Select
                aria-label={t.settings.customAttribute}
                value={String(field.value)}
                onChange={(_, data) => field.onChange(Number(data.value))}
                disabled={disabled || !values.marker.enabled}
              >
                {Array.from({ length: 15 }, (_, i) => 15 - i).map((n) => (
                  <option key={n} value={n}>
                    {t.settings.customAttributeN(n)}
                  </option>
                ))}
              </Select>
            )}
          />
        </Row>
      </Section>

      <Section title={t.settings.history} labelId="settings-history">
        <Row title={t.settings.retention} sub={t.settings.retentionHint}>
          <Controller
            name="auditRetentionDays"
            control={control}
            render={({ field }) => (
              <Input
                className={s.small}
                type="number"
                min={1}
                max={3650}
                aria-label={t.settings.retentionLabel}
                value={String(field.value)}
                onChange={(_, data) => field.onChange(Math.max(1, Math.min(3650, Math.trunc(Number(data.value) || 1))))}
                disabled={disabled}
              />
            )}
          />
        </Row>
      </Section>
      <p className={s.footnote}>{t.settings.infra}</p>

      {conflict && (
        <ConflictDialog
          open
          title={t.conflict.settingsTitle}
          intro={t.conflict.settingsIntro(shortName(conflict.updatedBy) || t.conflict.someone, atWhen(conflict.updatedAt))}
          by={shortName(conflict.updatedBy) || t.conflict.someone}
          rows={settingsRows(toSettingsInput(conflict), getValues())}
          onBack={() => setConflict(null)}
          onReload={() => {
            reset(toSettingsInput(conflict));
            setBaseEtag(conflict.etag);
            setConflict(null);
          }}
        />
      )}
    </form>
  );
}
