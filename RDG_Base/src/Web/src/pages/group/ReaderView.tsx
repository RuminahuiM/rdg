// What readers see of a group (mockup EditGroupReader).
import { useSettings } from '../../api/hooks';
import type { Definition } from '../../api/types';
import { AppLink } from '../../components/AppLink';
import { CopyButton } from '../../components/CopyButton';
import { PreviewCard } from '../../components/PreviewCard';
import { StatusCard } from '../../components/StatusCard';
import { DefinitionBadge, TypeBadge } from '../../components/StatusBadge';
import { PageHeader, Section, useUiStyles } from '../../components/ui';
import { targetText } from '../../components/definitionText';
import { RuleEditor } from '../../rules/RuleEditor';
import { t } from '../../strings/en';
import { useGroupStyles as useStyles } from './styles';
import { fromDefinition } from './formValues';

export function ReaderView({ definition }: { definition: Definition }) {
  const s = useStyles();
  const ui = useUiStyles();
  const settings = useSettings();
  const orgLimit = settings.data?.changeLimitPercent ?? 50;
  const v = fromDefinition(definition);
  const filters =
    v.includeDisabled && v.includeGuests
      ? t.group.includedBoth
      : v.includeDisabled
        ? t.group.includedDisabled
        : v.includeGuests
          ? t.group.includedGuests
          : t.group.excludedBoth;
  return (
    <div className={ui.page}>
      <div className={s.breadcrumb}>
        <AppLink to="/">{t.group.breadcrumb}</AppLink>
        <span className={ui.muted}> / {definition.name}</span>
      </div>
      <PageHeader
        title={definition.name}
        badges={
          <>
            <TypeBadge groupType={definition.groupType} />
            <DefinitionBadge definition={definition} />
          </>
        }
      />
      <div className={s.readerNote} role="note">
        {t.group.readerNote}
      </div>
      <div className={s.layout}>
        <div className={s.column}>
          <Section title={t.group.readerSettings} labelId="reader-settings">
            <dl className={ui.dl}>
              <dt>{t.group.target}</dt>
              <dd>{targetText(definition)}</dd>
              <dt>{t.group.frequency}</dt>
              <dd>{t.frequency(v.frequencyMinutes)}</dd>
              <dt>{t.group.enabled}</dt>
              <dd>{v.enabled ? t.common.yes : t.common.no}</dd>
              <dt>{t.group.dryRun}</dt>
              <dd>{v.dryRun ? t.common.on : t.common.off}</dd>
              <dt>{t.group.alwaysInclude}</dt>
              <dd>{v.includeUsers.map((u) => u.displayName || u.upn).join(', ') || t.common.none}</dd>
              <dt>{t.group.alwaysExclude}</dt>
              <dd>{v.excludeUsers.map((u) => u.displayName || u.upn).join(', ') || t.common.none}</dd>
              <dt>{t.group.readerExcluded}</dt>
              <dd>{filters}</dd>
              <dt>{t.group.changeLimit}</dt>
              <dd>{v.changeLimitPercent === null ? t.group.orgDefault(orgLimit) : t.group.percent(v.changeLimitPercent)}</dd>
              {v.compareGroup && (
                <>
                  <dt>{t.group.compareGroup}</dt>
                  <dd>{v.compareGroup.displayName}</dd>
                </>
              )}
            </dl>
          </Section>
          <Section title={t.group.rule} labelId="reader-rule" actions={<CopyButton text={definition.rule} label={t.group.copyRule} />}>
            <RuleEditor value={definition.rule} readOnly labelledBy="reader-rule" />
          </Section>
        </div>
        <div className={s.column}>
          <StatusCard definition={definition} />
          <PreviewCard input={() => ({ definitionId: definition.id })} groupType={definition.groupType} canRun readerNote />
        </div>
      </div>
    </div>
  );
}
