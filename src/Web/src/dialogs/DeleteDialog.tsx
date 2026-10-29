// Delete a definition. The group stays; rules that reference it keep working because they
// read its members from Entra ID directly. Confirm by typing the definition name.
import { useState } from 'react';
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
  MessageBar,
  MessageBarBody,
  makeStyles,
  tokens,
} from '@fluentui/react-components';
import { useDeleteDefinition } from '../api/hooks';
import type { Definition } from '../api/types';
import { ApiError } from '../api/client';
import { AppLink } from '../components/AppLink';
import { targetText } from '../components/definitionText';
import { t } from '../strings/en';

const useStyles = makeStyles({
  list: { margin: '12px 0', paddingLeft: '20px', display: 'flex', flexDirection: 'column', gap: '6px', fontSize: tokens.fontSizeBase300 },
  danger: {
    backgroundColor: tokens.colorPaletteRedBackground3,
    color: tokens.colorNeutralForegroundOnBrand,
    ':hover': { backgroundColor: tokens.colorPaletteRedForeground1, color: tokens.colorNeutralForegroundOnBrand },
    ':hover:active': { backgroundColor: tokens.colorPaletteRedForeground1, color: tokens.colorNeutralForegroundOnBrand },
  },
});

export function DeleteDialog({
  definition,
  references,
  open,
  onClose,
  onDeleted,
}: {
  definition: Definition;
  /** Definitions whose rule references this one's group (known before deleting). */
  references: { id: string; name: string }[];
  open: boolean;
  onClose: () => void;
  onDeleted: () => void;
}) {
  const s = useStyles();
  const [typed, setTyped] = useState('');
  const remove = useDeleteDefinition();
  const conflict = remove.error instanceof ApiError && remove.error.status === 409 ? (remove.error.problem.referencedBy ?? []) : [];
  const shown = conflict.length ? conflict : references;
  const groupExists = Boolean(definition.status?.groupId ?? (definition.target.mode !== 'create' && definition.target.groupId));
  const matches = typed.trim() === definition.name.trim();

  const submit = () => remove.mutate({ id: definition.id, etag: definition.etag, force: shown.length > 0 }, { onSuccess: onDeleted });

  return (
    <Dialog open={open} onOpenChange={(_, data) => !data.open && onClose()} modalType="alert">
      <DialogSurface>
        <DialogBody>
          <DialogTitle>{t.del.title(definition.name)}</DialogTitle>
          <DialogContent>
            <ul className={s.list}>
              {groupExists ? (
                <li>
                  <strong>{t.del.stays}</strong> {t.del.staysDetail(targetText(definition), definition.status?.memberCount ?? null)}
                </li>
              ) : (
                <li>{t.del.noGroupYet}</li>
              )}
              <li>{t.del.stops}</li>
              <li>{t.del.history}</li>
            </ul>
            {shown.length > 0 && (
              <MessageBar intent="info" layout="multiline">
                <MessageBarBody>
                  {t.del.references(shown.length)}{' '}
                  {shown.map((ref, index) => (
                    <span key={ref.id}>
                      {index > 0 && ', '}
                      <AppLink to={`/groups/${ref.id}`} onClick={onClose}>
                        {ref.name}
                      </AppLink>
                    </span>
                  ))}
                  . {t.del.referencesLive}
                </MessageBarBody>
              </MessageBar>
            )}
            <Field label={t.del.typeToConfirm} style={{ marginTop: 16 }}>
              <Input value={typed} placeholder={definition.name} onChange={(_, data) => setTyped(data.value)} />
            </Field>
            {remove.error && !(remove.error instanceof ApiError && remove.error.status === 409) && (
              <MessageBar intent="error" style={{ marginTop: 12 }}>
                <MessageBarBody>{remove.error instanceof ApiError ? remove.error.message : t.error.detail}</MessageBarBody>
              </MessageBar>
            )}
          </DialogContent>
          <DialogActions>
            <Button onClick={onClose}>{t.common.cancel}</Button>
            <Button className={matches ? s.danger : undefined} disabled={!matches || remove.isPending} onClick={submit}>
              {t.del.confirm}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
