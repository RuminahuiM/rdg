// Group picker for the target group (use existing / adopt) and the compare group.
// Shows the chosen group as a chip; otherwise a search box with an inline list in which
// groups RDG can't manage are disabled with the reason (on-prem, role-assignable, linked).
import { useState, useId, type KeyboardEvent } from 'react';
import { Input, Tag, TagGroup, makeStyles, mergeClasses, tokens, Spinner } from '@fluentui/react-components';
import { useGroupSearch } from '../api/hooks';
import type { DirectoryGroup } from '../api/types';
import { useDebounced } from './useDebounced';
import { Badge } from './StatusBadge';
import { t } from '../strings/en';

export type GroupPickerPurpose = 'existing' | 'adopt' | 'compare';

export interface PickedGroup {
  id: string;
  displayName: string;
  mail?: string | null;
}

const useStyles = makeStyles({
  root: { display: 'flex', flexDirection: 'column', gap: '8px' },
  input: { maxWidth: '360px' },
  list: {
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    maxHeight: '260px',
    overflowY: 'auto',
    padding: '4px',
    margin: 0,
  },
  option: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    flexWrap: 'wrap',
    padding: '8px 10px',
    borderRadius: tokens.borderRadiusMedium,
    cursor: 'pointer',
    fontSize: tokens.fontSizeBase300,
    ':hover': { backgroundColor: tokens.colorSubtleBackgroundHover },
  },
  active: {
    backgroundColor: tokens.colorSubtleBackgroundHover,
    outlineWidth: '2px',
    outlineStyle: 'solid',
    outlineColor: tokens.colorStrokeFocus2,
  },
  disabled: { cursor: 'not-allowed', color: tokens.colorNeutralForegroundDisabled, ':hover': { backgroundColor: 'transparent' } },
  name: { fontWeight: tokens.fontWeightSemibold },
  meta: { color: tokens.colorNeutralForeground3 },
  chipRow: { display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap' },
  hint: { color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase200 },
});

/** Why a group can't be picked for this purpose, or null. */
export function disabledReason(group: DirectoryGroup, purpose: GroupPickerPurpose, selfId?: string): string | null {
  if (purpose === 'compare') return null;
  if (group.onPremisesSynced) return t.disabledReason.onPrem;
  if (group.isAssignableToRole) return t.disabledReason.roleAssignable;
  if (group.managedByDefinitionId && group.managedByDefinitionId !== selfId) {
    return group.linkedToName ? t.disabledReason.linked(group.linkedToName) : t.disabledReason.linkedUnknown;
  }
  if (group.groupType === 'Other') return t.disabledReason.otherType;
  if (purpose === 'existing' && group.isDynamic) return t.disabledReason.dynamic;
  return null;
}

function describe(group: DirectoryGroup): string {
  const parts = [t.groupType[group.groupType] ?? group.groupType];
  if (typeof group.memberCount === 'number') parts.push(t.disabledReason.members(group.memberCount));
  return ` · ${parts.join(' · ')}`;
}

export function GroupPicker({
  label,
  value,
  onChange,
  purpose,
  selfId,
  note,
  disabled,
  invalid,
  initialSearch = '',
}: {
  label: string;
  value: PickedGroup | null;
  onChange: (group: DirectoryGroup | null) => void;
  purpose: GroupPickerPurpose;
  selfId?: string;
  note?: string;
  disabled?: boolean;
  invalid?: boolean;
  initialSearch?: string;
}) {
  const s = useStyles();
  const listId = useId();
  const [text, setText] = useState(initialSearch);
  const [active, setActive] = useState(0);
  const search = useDebounced(text.trim(), 250);
  const groups = useGroupSearch(search);
  const items = groups.data ?? [];

  if (value) {
    return (
      <div className={s.chipRow}>
        <TagGroup onDismiss={() => onChange(null)} aria-label={label}>
          <Tag
            shape="rounded"
            size="small"
            dismissible={!disabled}
            dismissIcon={{ 'aria-label': t.common.remove(value.displayName) }}
            value={value.id}
          >
            {value.displayName}
            {value.mail ? ` · ${value.mail}` : ''}
          </Tag>
        </TagGroup>
        {note && <span className={s.hint}>{note}</span>}
      </div>
    );
  }

  const choose = (group: DirectoryGroup | undefined) => {
    if (!group || disabledReason(group, purpose, selfId)) return;
    onChange(group);
  };
  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setActive((a) => Math.min(a + 1, items.length - 1));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setActive((a) => Math.max(a - 1, 0));
    } else if (event.key === 'Enter') {
      event.preventDefault();
      choose(items[active]);
    }
  };

  return (
    <div className={s.root}>
      <Input
        className={s.input}
        aria-label={label}
        placeholder={label}
        value={text}
        disabled={disabled}
        onChange={(_, data) => {
          setText(data.value);
          setActive(0);
        }}
        onKeyDown={onKeyDown}
        aria-controls={listId}
        aria-invalid={invalid || undefined}
        role="combobox"
        aria-expanded={search.length >= 2}
        aria-activedescendant={items[active] ? `${listId}-${items[active]?.id}` : undefined}
      />
      {search.length >= 2 && (
        <div id={listId} role="listbox" aria-label={label} className={s.list}>
          {groups.isPending && <Spinner size="extra-tiny" label={t.common.searching} />}
          {!groups.isPending && items.length === 0 && <div className={s.meta}>{t.common.noMatches}</div>}
          {items.map((group, index) => {
            const reason = disabledReason(group, purpose, selfId);
            return (
              <div
                key={group.id}
                id={`${listId}-${group.id}`}
                role="option"
                aria-selected={index === active}
                aria-disabled={Boolean(reason)}
                className={mergeClasses(s.option, index === active && !reason && s.active, Boolean(reason) && s.disabled)}
                onClick={() => choose(group)}
                onMouseEnter={() => setActive(index)}
              >
                <span className={s.name}>{group.displayName}</span>
                <span className={s.meta}>
                  {describe(group)}
                  {group.isAssignableToRole ? ` · ${t.disabledReason.roleAssignableShort}` : ''}
                </span>
                {reason ? (
                  <Badge tone="off" dot={false}>
                    {reason}
                  </Badge>
                ) : group.isDynamic ? (
                  <Badge tone="info" dot={false}>
                    {t.disabledReason.dynamicBadge}
                  </Badge>
                ) : null}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
