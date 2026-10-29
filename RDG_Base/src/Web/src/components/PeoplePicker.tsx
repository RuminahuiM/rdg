// "Always include" / "Always exclude": chips for the chosen users and a search box
// (GET /directory/users, prefix match, at least 2 characters).
import { useState } from 'react';
import { Combobox, Option, Tag, TagGroup, makeStyles, tokens, Spinner } from '@fluentui/react-components';
import { useUserSearch } from '../api/hooks';
import type { UserRef } from '../api/types';
import { useDebounced } from './useDebounced';
import { t } from '../strings/en';

const useStyles = makeStyles({
  root: { display: 'flex', flexDirection: 'column', gap: '8px' },
  tags: { display: 'flex', flexWrap: 'wrap', gap: '6px' },
  input: { maxWidth: '320px' },
  secondary: { color: tokens.colorNeutralForeground3, marginLeft: '6px', fontSize: tokens.fontSizeBase200 },
});

export function PeoplePicker({
  label,
  labelId,
  value,
  onChange,
  disabled,
}: {
  label: string;
  labelId: string;
  value: UserRef[];
  onChange: (users: UserRef[]) => void;
  disabled?: boolean;
}) {
  const s = useStyles();
  const [text, setText] = useState('');
  const search = useDebounced(text.trim(), 250);
  const users = useUserSearch(search);
  const chosen = new Set(value.map((u) => u.id));
  const options = (users.data ?? []).filter((u) => !chosen.has(u.id));

  return (
    <div className={s.root}>
      {value.length > 0 && (
        <TagGroup className={s.tags} aria-labelledby={labelId} onDismiss={(_, data) => onChange(value.filter((u) => u.id !== data.value))}>
          {value.map((user) => (
            <Tag
              key={user.id}
              value={user.id}
              shape="rounded"
              size="small"
              dismissible={!disabled}
              dismissIcon={{ 'aria-label': t.common.remove(user.displayName ?? user.upn) }}
              title={user.upn}
            >
              {user.displayName || user.upn}
            </Tag>
          ))}
        </TagGroup>
      )}
      {!disabled && (
        <Combobox
          className={s.input}
          aria-label={`${label}: ${t.group.addPerson}`}
          placeholder={t.group.addPerson}
          freeform
          value={text}
          onChange={(event) => setText(event.target.value)}
          onOptionSelect={(_, data) => {
            const user = options.find((u) => u.id === data.optionValue);
            if (user) onChange([...value, { id: user.id, upn: user.upn, displayName: user.displayName }]);
            setText('');
          }}
          selectedOptions={[]}
        >
          {search.length < 2 ? (
            <Option disabled value="" text="">
              {t.common.minChars}
            </Option>
          ) : users.isFetching && options.length === 0 ? (
            <Option disabled value="" text="">
              <Spinner size="extra-tiny" label={t.common.searching} />
            </Option>
          ) : options.length === 0 ? (
            <Option disabled value="" text="">
              {t.common.noMatches}
            </Option>
          ) : (
            options.map((user) => (
              <Option key={user.id} value={user.id} text={user.displayName}>
                {user.displayName}
                <span className={s.secondary}>{user.upn}</span>
              </Option>
            ))
          )}
        </Combobox>
      )}
    </div>
  );
}
