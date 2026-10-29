// New, edit and adopt (mockups EditGroup, NewGroup, AdoptGroup). Saves with If-Match; a 412
// opens the conflict dialog.
import { useEffect, useMemo, useRef, useState } from 'react';
import { useBlocker, useNavigate, useSearchParams } from 'react-router-dom';
import { Controller, useForm, useWatch } from 'react-hook-form';
import {
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Field,
  Input,
  Link,
  MessageBar,
  MessageBarBody,
  Select,
  Switch,
  tokens,
} from '@fluentui/react-components';
import { useCreateDefinition, useDefinition, useDefinitions, useUpdateDefinition } from '../../api/hooks';
import type { Definition, DirectoryGroup, GroupType, PreviewInput, Settings } from '../../api/types';
import { ApiError } from '../../api/client';
import { useSession } from '../../auth/session';
import { AppLink } from '../../components/AppLink';
import { GroupPicker } from '../../components/GroupPicker';
import { PeoplePicker } from '../../components/PeoplePicker';
import { PreviewCard } from '../../components/PreviewCard';
import { StatusCard } from '../../components/StatusCard';
import { DefinitionBadge, TypeBadge } from '../../components/StatusBadge';
import { useNotify } from '../../components/notify';
import { useSyncNow } from '../../components/sync';
import { PageHeader, Section, useUiStyles } from '../../components/ui';
import { ApproveDialog } from '../../dialogs/ApproveDialog';
import { ConflictDialog } from '../../dialogs/ConflictDialog';
import { DeleteDialog } from '../../dialogs/DeleteDialog';
import { RuleEditor, type ValidationState } from '../../rules/RuleEditor';
import { atWhen, shortName } from '../../format';
import { t } from '../../strings/en';
import { useGroupStyles as useStyles } from './styles';
import { affixed, conflictRows, fromDefinition, newFormValues, toDefinitionInput, type FormValues } from './formValues';
import { TargetModeSwitch as Segmented } from './TargetModeSwitch';
import { AdoptResultCard } from './AdoptResultCard';

const RULE_REFERENCE = 'https://learn.microsoft.com/entra/identity/users/groups-dynamic-membership';
const GROUP_TYPES: GroupType[] = ['Security', 'Microsoft365', 'MailEnabledSecurity', 'Distribution'];
const LIMITS = [10, 20, 25, 30, 40, 50, 60, 75, 90, 100];
export function GroupForm({ definition, settings }: { definition: Definition | undefined; settings: Settings | undefined }) {
  const s = useStyles();
  const ui = useUiStyles();
  const navigate = useNavigate();
  const notify = useNotify();
  const { readOnly } = useSession();
  const [params, setParams] = useSearchParams();
  const isNew = !definition;
  const all = useDefinitions();
  const create = useCreateDefinition();
  const update = useUpdateDefinition();
  const sync = useSyncNow();
  const latest = useDefinition(definition?.id);

  const form = useForm<FormValues>({ defaultValues: definition ? fromDefinition(definition) : newFormValues(settings) });
  const { control, handleSubmit, reset, setValue, getValues, formState } = form;
  const values = useWatch({ control }) as FormValues;
  // The stored version the form is based on (ETag for If-Match, updatedAt to ignore older cache entries).
  const [base, setBase] = useState(definition ? { etag: definition.etag, updatedAt: definition.updatedAt } : null);
  const baseEtag = base?.etag ?? null;
  const setBaseFrom = (d: Definition) => setBase({ etag: d.etag, updatedAt: d.updatedAt });
  const [ruleState, setRuleState] = useState<ValidationState>({ state: 'idle' });
  const [errors, setErrors] = useState<{ field: string; message: string }[]>([]);
  const [conflict, setConflict] = useState<Definition | null>(null);
  const [approveOpen, setApproveOpen] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const saved = useRef(false);
  const current = latest.data ?? definition;

  // A newer stored version (e.g. after an approval) replaces an untouched form.
  useEffect(() => {
    if (current && base && current.etag !== base.etag && current.updatedAt >= base.updatedAt && !formState.isDirty) {
      reset(fromDefinition(current));
      setBase({ etag: current.etag, updatedAt: current.updatedAt });
    }
  }, [current, base, formState.isDirty, reset]);

  // ?review=1 from the groups list opens the approval at once.
  useEffect(() => {
    if (params.get('review') === '1' && current?.status?.pendingApproval) {
      setApproveOpen(true);
      const next = new URLSearchParams(params);
      next.delete('review');
      setParams(next, { replace: true });
    }
  }, [params, setParams, current]);

  const blocker = useBlocker(
    ({ currentLocation, nextLocation }) => formState.isDirty && !saved.current && currentLocation.pathname !== nextLocation.pathname,
  );
  useEffect(() => {
    if (!formState.isDirty) return undefined;
    const handler = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [formState.isDirty]);

  const frequencyOptions = useMemo(() => {
    const list = new Set(settings?.frequencyOptions ?? [15, 60]);
    list.add(values.frequencyMinutes);
    return [...list].sort((a, b) => a - b);
  }, [settings, values.frequencyMinutes]);
  const orgLimit = settings?.changeLimitPercent ?? 50;

  const references = useMemo(() => {
    const groupId = current?.status?.groupId ?? current?.target.groupId;
    if (!groupId || !all.data) return [];
    return all.data
      .filter((d) => d.id !== current?.id && d.rule.toLowerCase().includes(groupId.toLowerCase()))
      .map((d) => ({ id: d.id, name: d.name }));
  }, [all.data, current]);

  // A group the engine created, or an adoption that was approved, stays the target.
  const targetLocked = Boolean(current?.status?.groupId) && (current?.target.mode === 'create' || Boolean(current?.target.adopted));
  const followsGroup = values.mode !== 'create' || targetLocked;
  const pending = current?.status?.pendingApproval;
  const adoptWaiting = !isNew && current?.target.mode === 'adopt' && pending?.kind === 'adopt';
  const busy = create.isPending || update.isPending;
  const canSave = !busy && ruleState.state !== 'invalid' && (isNew || formState.isDirty);

  const onPickTarget = (group: DirectoryGroup | null) => {
    setValue('targetGroup', group ? { id: group.id, displayName: group.displayName, mail: group.mail } : null, { shouldDirty: true });
    if (group && group.groupType !== 'Other') setValue('groupType', group.groupType, { shouldDirty: true });
    if (group?.isDynamic && group.membershipRule && !getValues('rule').trim())
      setValue('rule', group.membershipRule, { shouldDirty: true });
    if (group && !getValues('name').trim()) setValue('name', group.displayName, { shouldDirty: true });
  };

  const submit = handleSubmit((v) => {
    const missing: { field: string; message: string }[] = [];
    if (!v.name.trim()) missing.push({ field: 'name', message: t.group.nameRequired });
    if (!v.rule.trim()) missing.push({ field: 'rule', message: t.group.ruleRequired });
    if (v.mode !== 'create' && !v.targetGroup) missing.push({ field: 'target', message: t.group.groupRequired });
    setErrors(missing);
    if (missing.length) return;
    const input = toDefinitionInput(v);
    const onError = (error: unknown) => {
      if (error instanceof ApiError && error.status === 412) {
        void latest.refetch().then((result) => setConflict(result.data ?? null));
      } else if (error instanceof ApiError && error.problem.errors?.length) {
        setErrors(error.problem.errors);
      } else {
        setErrors([{ field: '', message: error instanceof ApiError ? (error.problem.detail ?? error.problem.title) : t.error.detail }]);
      }
    };
    if (isNew) {
      create.mutate(input, {
        onSuccess: (created) => {
          saved.current = true;
          notify(t.group.createdToast(created.name), 'success');
          navigate(`/groups/${created.id}`, { replace: true });
        },
        onError,
      });
    } else if (definition && baseEtag) {
      update.mutate(
        { id: definition.id, etag: baseEtag, input },
        {
          onSuccess: (updated) => {
            // The PUT answer has no user names; keep the ones in the form.
            reset({ ...fromDefinition(updated), includeUsers: v.includeUsers, excludeUsers: v.excludeUsers, compareGroup: v.compareGroup });
            setBaseFrom(updated);
            setErrors([]);
            notify(t.group.savedToast(updated.name), 'success');
          },
          onError,
        },
      );
    }
  });

  const previewInput = (): PreviewInput | null => {
    const v = getValues();
    if (!isNew && !formState.isDirty && current) return { definitionId: current.id };
    if (!v.rule.trim() || (v.mode !== 'create' && !v.targetGroup)) return null;
    const definition = toDefinitionInput({ ...v, name: v.name.trim() || t.preview.unnamed });
    // Unsaved changes to a saved definition: send its ID too, so the edited version replaces
    // the saved one in the preview instead of competing with it for the same group.
    return !isNew && current ? { definitionId: current.id, definition } : { definition };
  };

  const fieldError = (field: string) =>
    errors
      .filter((e) => e.field === field || e.field.startsWith(`${field}.`))
      .map((e) => e.message)
      .join(' ') || undefined;
  const otherErrors = errors.filter(
    (e) => !['name', 'rule', 'target', 'target.groupId', 'target.displayName', 'target.mode', 'groupType'].includes(e.field),
  );
  const ruleServerErrors = errors.filter((e) => e.field === 'rule');

  const title = isNew ? t.group.newTitle : (current?.name ?? '');
  const noun = t.groupTypeNoun[values.groupType] ?? '';
  const createHint = t.group.createHint(noun, affixed(values.name.trim() || '…', settings));
  const renameHint = t.group.renameHint(affixed(values.targetGroup?.displayName ?? '…', settings));

  return (
    <form className={ui.page} onSubmit={(e) => void submit(e)} noValidate aria-label={title}>
      <div className={s.breadcrumb}>
        <AppLink to="/">{t.group.breadcrumb}</AppLink>
        <span className={ui.muted}> / {title}</span>
      </div>
      <PageHeader
        title={title}
        badges={
          current && (
            <>
              <TypeBadge groupType={current.groupType} />
              <DefinitionBadge definition={current} syncing={sync.isSyncing(current.id)} />
            </>
          )
        }
        actions={
          isNew ? (
            <>
              <Button onClick={() => navigate('/')}>{t.common.cancel}</Button>
              <Button appearance="primary" type="submit" disabled={!canSave}>
                {create.isPending ? t.common.saving : t.group.create}
              </Button>
            </>
          ) : (
            current && (
              <>
                <Button className={s.danger} onClick={() => setDeleteOpen(true)}>
                  {t.group.delete}
                </Button>
                {!adoptWaiting && (
                  <Button
                    onClick={() => sync.start(current)}
                    disabled={sync.isSyncing(current.id) || formState.isDirty || !current.enabled}
                  >
                    {t.group.syncNow}
                  </Button>
                )}
                <Button appearance={adoptWaiting ? 'secondary' : 'primary'} type="submit" disabled={!canSave}>
                  {update.isPending ? t.common.saving : t.group.save}
                </Button>
                {adoptWaiting && (
                  <Button appearance="primary" onClick={() => setApproveOpen(true)} disabled={readOnly || formState.isDirty}>
                    {t.group.approveTakeover}
                  </Button>
                )}
              </>
            )
          )
        }
      />

      {(otherErrors.length > 0 || ruleServerErrors.length > 0 || fieldError('groupType')) && (
        <MessageBar intent="error" layout="multiline">
          <MessageBarBody>
            {t.group.fixErrors}
            <ul style={{ margin: '4px 0 0', paddingLeft: 18 }}>
              {[...otherErrors, ...ruleServerErrors, ...errors.filter((e) => e.field === 'groupType')].map((e) => (
                <li key={`${e.field}-${e.message}`}>{e.message}</li>
              ))}
            </ul>
          </MessageBarBody>
        </MessageBar>
      )}

      <div className={s.layout}>
        <div className={s.column}>
          <Section title={t.group.basics} labelId="basics-title">
            <div className={s.fields}>
              <Controller
                name="name"
                control={control}
                render={({ field }) => (
                  <Field label={t.group.name} required validationMessage={fieldError('name')}>
                    <Input {...field} onChange={(_, data) => field.onChange(data.value)} maxLength={120} />
                  </Field>
                )}
              />
              <Controller
                name="groupType"
                control={control}
                render={({ field }) => (
                  <Field
                    label={t.group.groupType}
                    hint={followsGroup && values.mode !== 'create' ? undefined : targetLocked ? t.group.groupTypeLocked : undefined}
                  >
                    <Select value={field.value} onChange={(_, data) => field.onChange(data.value)} disabled={followsGroup}>
                      {GROUP_TYPES.map((g) => (
                        <option key={g} value={g}>
                          {t.groupType[g]}
                        </option>
                      ))}
                    </Select>
                  </Field>
                )}
              />
              <div className={s.full}>
                <span className={s.label} id="target-label">
                  {t.group.target}
                </span>
                <Controller
                  name="mode"
                  control={control}
                  render={({ field }) => (
                    <Segmented
                      value={field.value}
                      disabled={targetLocked}
                      onChange={(mode) => {
                        field.onChange(mode);
                        if (mode === 'create') setValue('targetGroup', null, { shouldDirty: true });
                      }}
                    />
                  )}
                />
                <div style={{ marginTop: 10 }}>
                  {values.mode === 'create' ? (
                    <div className={s.hint} style={{ fontSize: tokens.fontSizeBase300 }}>
                      {targetLocked ? (
                        <>
                          {t.group.createdHint} <strong>{current?.target.displayName}</strong>
                        </>
                      ) : (
                        <>
                          {createHint.before} <strong>{createHint.name}</strong> {createHint.after}
                        </>
                      )}
                    </div>
                  ) : (
                    <Controller
                      name="targetGroup"
                      control={control}
                      render={({ field }) => (
                        <Field validationMessage={fieldError('target')}>
                          <GroupPicker
                            label={values.mode === 'adopt' ? t.group.findAdopt : t.group.findGroup}
                            value={field.value}
                            onChange={onPickTarget}
                            purpose={values.mode === 'adopt' ? 'adopt' : 'existing'}
                            selfId={current?.id}
                            disabled={targetLocked}
                            invalid={Boolean(fieldError('target'))}
                            note={values.mode === 'existing' ? t.group.linkedOnly : undefined}
                          />
                        </Field>
                      )}
                    />
                  )}
                  {values.mode === 'existing' && !values.targetGroup && <div className={s.hint}>{t.group.existingHint}</div>}
                  {values.mode === 'adopt' && (
                    <div style={{ marginTop: 12 }}>
                      <Controller
                        name="renameOnAdopt"
                        control={control}
                        render={({ field }) => (
                          <Switch
                            checked={field.value}
                            onChange={(_, data) => field.onChange(data.checked)}
                            label={t.group.renameOnAdopt}
                            disabled={Boolean(current?.target.adopted)}
                          />
                        )}
                      />
                      {values.renameOnAdopt && (
                        <div className={s.hint}>
                          {renameHint.before} <strong>{renameHint.name}</strong>
                          {renameHint.after}
                        </div>
                      )}
                      {current?.target.convertFromDynamic && <div className={s.hint}>{t.group.dynamicHint}</div>}
                    </div>
                  )}
                </div>
              </div>
              <Controller
                name="frequencyMinutes"
                control={control}
                render={({ field }) => (
                  <Field label={t.group.frequency}>
                    <Select value={String(field.value)} onChange={(_, data) => field.onChange(Number(data.value))}>
                      {frequencyOptions.map((m) => (
                        <option key={m} value={m}>
                          {t.frequency(m)}
                        </option>
                      ))}
                    </Select>
                  </Field>
                )}
              />
              <div className={s.switches} style={{ alignSelf: 'end', minHeight: 32 }}>
                <Controller
                  name="enabled"
                  control={control}
                  render={({ field }) => (
                    <Switch checked={field.value} onChange={(_, data) => field.onChange(data.checked)} label={t.group.enabled} />
                  )}
                />
                <Controller
                  name="dryRun"
                  control={control}
                  render={({ field }) => (
                    <Switch checked={field.value} onChange={(_, data) => field.onChange(data.checked)} label={t.group.dryRun} />
                  )}
                />
              </div>
            </div>
          </Section>

          <Section
            title={t.group.rule}
            labelId="rule-title"
            actions={
              <Link href={RULE_REFERENCE} target="_blank" rel="noreferrer">
                {t.group.ruleReference}
              </Link>
            }
          >
            <span className={s.label} id="rule-label">
              {t.group.ruleText}
            </span>
            <Controller
              name="rule"
              control={control}
              render={({ field }) => (
                <RuleEditor
                  value={field.value}
                  onChange={field.onChange}
                  groupType={values.groupType}
                  onValidation={setRuleState}
                  labelledBy="rule-label"
                />
              )}
            />
            {fieldError('rule') && ruleState.state !== 'invalid' && (
              <div role="alert" className={s.hint} style={{ color: tokens.colorPaletteRedForeground1 }}>
                {fieldError('rule')}
              </div>
            )}
            {ruleState.state === 'valid' && ruleState.result.referencedGroupIds.length > 0 && (
              <ul className={s.refs} aria-label={t.group.referencedGroups}>
                {ruleState.result.referencedGroupIds.map((groupId) => {
                  const owner = (all.data ?? []).find(
                    (d) => (d.status?.groupId ?? d.target.groupId)?.toLowerCase() === groupId.toLowerCase(),
                  );
                  return (
                    <li key={groupId}>
                      {owner ? (
                        <>
                          {t.group.referencesManaged(owner.target.displayName ?? groupId)}{' '}
                          <AppLink to={`/groups/${owner.id}`}>{owner.name}</AppLink>
                        </>
                      ) : (
                        t.group.referencesUnmanaged(groupId)
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
            {isNew && <div className={s.hint}>{t.group.pasteTip}</div>}
            <div className={s.fields} style={{ marginTop: 16 }}>
              <div>
                <span className={s.label} id="include-label">
                  {t.group.alwaysInclude}
                </span>
                <Controller
                  name="includeUsers"
                  control={control}
                  render={({ field }) => (
                    <PeoplePicker label={t.group.alwaysInclude} labelId="include-label" value={field.value} onChange={field.onChange} />
                  )}
                />
              </div>
              <div>
                <span className={s.label} id="exclude-label">
                  {t.group.alwaysExclude}
                </span>
                <Controller
                  name="excludeUsers"
                  control={control}
                  render={({ field }) => (
                    <PeoplePicker label={t.group.alwaysExclude} labelId="exclude-label" value={field.value} onChange={field.onChange} />
                  )}
                />
              </div>
            </div>
            <div className={s.switches} style={{ marginTop: 16 }}>
              <Controller
                name="includeDisabled"
                control={control}
                render={({ field }) => (
                  <Switch checked={field.value} onChange={(_, data) => field.onChange(data.checked)} label={t.group.includeDisabled} />
                )}
              />
              <Controller
                name="includeGuests"
                control={control}
                render={({ field }) => (
                  <Switch checked={field.value} onChange={(_, data) => field.onChange(data.checked)} label={t.group.includeGuests} />
                )}
              />
            </div>
          </Section>

          <Section title={t.group.safety} labelId="safety-title">
            <div className={s.fields}>
              <Controller
                name="changeLimitPercent"
                control={control}
                render={({ field }) => (
                  <Field label={t.group.changeLimit}>
                    <Select
                      value={field.value === null ? '' : String(field.value)}
                      onChange={(_, data) => field.onChange(data.value === '' ? null : Number(data.value))}
                    >
                      <option value="">{t.group.orgDefault(orgLimit)}</option>
                      {[...new Set([...LIMITS, ...(field.value === null ? [] : [field.value])])]
                        .sort((a, b) => a - b)
                        .map((p) => (
                          <option key={p} value={p}>
                            {t.group.percent(p)}
                          </option>
                        ))}
                    </Select>
                  </Field>
                )}
              />
              <div style={{ alignSelf: 'end' }}>
                <Controller
                  name="allowEmpty"
                  control={control}
                  render={({ field }) => (
                    <Switch checked={field.value} onChange={(_, data) => field.onChange(data.checked)} label={t.group.allowEmpty} />
                  )}
                />
                <div className={s.hint} style={{ marginTop: 0 }}>
                  {t.group.allowEmptyHint}
                </div>
              </div>
              <div className={s.full}>
                <span className={s.label}>{t.group.compareGroup}</span>
                <Controller
                  name="compareGroup"
                  control={control}
                  render={({ field }) => (
                    <GroupPicker
                      label={t.group.compareGroup}
                      value={field.value}
                      onChange={(g) => field.onChange(g ? { id: g.id, displayName: g.displayName, mail: g.mail } : null)}
                      purpose="compare"
                    />
                  )}
                />
                <div className={s.hint}>{t.group.compareHint}</div>
              </div>
            </div>
          </Section>
        </div>

        <div className={s.column}>
          {current && (
            <StatusCard
              definition={current}
              syncing={sync.isSyncing(current.id)}
              onApprove={readOnly ? undefined : () => setApproveOpen(true)}
            />
          )}
          {current && adoptWaiting && <AdoptResultCard definition={current} />}
          {isNew && values.mode === 'adopt' && (
            <Section>
              <p className={ui.muted} style={{ margin: 0 }}>
                {t.group.adoptWaiting}
              </p>
            </Section>
          )}
          <PreviewCard
            input={previewInput}
            groupType={values.groupType}
            canRun={ruleState.state !== 'invalid' && Boolean(values.rule.trim())}
          />
          {isNew && values.mode === 'create' && (
            <Section title={t.group.afterCreate} labelId="after-create">
              <div className={s.steps}>
                {(values.dryRun
                  ? [t.group.afterCreate1, t.group.afterCreate2(t.frequency(Math.max(values.frequencyMinutes, 15))), t.group.afterCreate3]
                  : [t.group.afterCreate1Live, t.group.afterCreate2Live(t.frequency(Math.max(values.frequencyMinutes, 15)))]
                ).map((text, index) => (
                  <div className={s.step} key={text}>
                    <span className={s.num}>{index + 1}</span>
                    <span>{text}</span>
                  </div>
                ))}
              </div>
            </Section>
          )}
        </div>
      </div>

      {current && pending && (
        <ApproveDialog
          definition={current}
          open={approveOpen}
          onClose={() => setApproveOpen(false)}
          onApproved={() => notify(t.group.approvedToast, 'success')}
        />
      )}
      {current && (
        <DeleteDialog
          definition={current}
          references={references}
          open={deleteOpen}
          onClose={() => setDeleteOpen(false)}
          onDeleted={() => {
            saved.current = true;
            notify(t.group.deletedToast(current.name), 'success');
            navigate('/', { replace: true });
          }}
        />
      )}
      {conflict && (
        <ConflictDialog
          open
          intro={t.conflict.intro(nameOrSomeone(conflict.updatedBy), conflict.name, atWhen(conflict.updatedAt))}
          by={nameOrSomeone(conflict.updatedBy)}
          rows={conflictRows(conflict, getValues(), orgLimit)}
          onBack={() => setConflict(null)}
          onReload={() => {
            reset(fromDefinition(conflict));
            setBaseFrom(conflict);
            setErrors([]);
            setConflict(null);
          }}
        />
      )}
      <Dialog open={blocker.state === 'blocked'} modalType="alert">
        <DialogSurface>
          <DialogBody>
            <DialogTitle>{t.common.unsavedChanges}</DialogTitle>
            <DialogContent />
            <DialogActions>
              <Button onClick={() => blocker.reset?.()}>{t.common.cancel}</Button>
              <Button appearance="primary" onClick={() => blocker.proceed?.()}>
                {t.common.leave}
              </Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </form>
  );
}

function nameOrSomeone(upn: string | null | undefined): string {
  return upn ? shortName(upn) : t.conflict.someone;
}
