import { useState } from 'react';
import { Button, type ButtonProps } from '@fluentui/react-components';
import { t } from '../strings/en';

export function CopyButton({
  text,
  label = t.common.copy,
  size,
  appearance,
}: {
  text: string;
  label?: string;
  size?: ButtonProps['size'];
  appearance?: ButtonProps['appearance'];
}) {
  const [copied, setCopied] = useState(false);
  return (
    <Button
      size={size}
      appearance={appearance}
      onClick={() => {
        void navigator.clipboard?.writeText(text).then(() => {
          setCopied(true);
          window.setTimeout(() => setCopied(false), 2000);
        });
      }}
    >
      {copied ? t.common.copied : label}
    </Button>
  );
}
