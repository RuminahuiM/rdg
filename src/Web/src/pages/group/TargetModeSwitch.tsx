// Create new / Use existing / Adopt existing.
import { mergeClasses } from '@fluentui/react-components';
import { t } from '../../strings/en';
import { useGroupStyles as useStyles } from './styles';
import type { FormValues } from './formValues';

export function TargetModeSwitch({
  value,
  onChange,
  disabled,
}: {
  value: FormValues['mode'];
  onChange: (mode: FormValues['mode']) => void;
  disabled?: boolean;
}) {
  const s = useStyles();
  const options: [FormValues['mode'], string][] = [
    ['create', t.group.modeCreate],
    ['existing', t.group.modeExisting],
    ['adopt', t.group.modeAdopt],
  ];
  return (
    <div role="group" aria-label={t.group.target} className={s.seg}>
      {options.map(([mode, label]) => (
        <button
          key={mode}
          type="button"
          className={mergeClasses(s.segButton, value === mode && s.segOn)}
          aria-pressed={value === mode}
          disabled={disabled}
          onClick={() => onChange(mode)}
        >
          {label}
        </button>
      ))}
    </div>
  );
}
