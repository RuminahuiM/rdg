// Someone saved the same document while this user edited it (412 on save). Shows the
// fields that differ; the user goes back to the form or reloads the saved version.
import {
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  makeStyles,
  tokens,
} from '@fluentui/react-components';
import { useUiStyles } from '../components/ui';
import { t } from '../strings/en';

export interface ConflictRow {
  field: string;
  theirs: string;
  mine: string;
  mono?: boolean;
}

const useStyles = makeStyles({
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    margin: '16px 0',
    fontSize: tokens.fontSizeBase300,
    tableLayout: 'fixed',
    '& th': {
      textAlign: 'left',
      padding: '8px',
      borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
      fontSize: tokens.fontSizeBase200,
      color: tokens.colorNeutralForeground2,
    },
    '& td': { padding: '8px', borderBottom: `1px solid ${tokens.colorNeutralStroke3}`, verticalAlign: 'top', overflowWrap: 'anywhere' },
    '& th:first-child': { width: '24%' },
  },
});

export function ConflictDialog({
  open,
  title = t.conflict.title,
  intro,
  by,
  rows,
  onBack,
  onReload,
}: {
  open: boolean;
  title?: string;
  intro: string;
  by: string;
  rows: ConflictRow[];
  onBack: () => void;
  onReload: () => void;
}) {
  const s = useStyles();
  const ui = useUiStyles();
  return (
    <Dialog open={open} onOpenChange={(_, data) => !data.open && onBack()} modalType="alert">
      <DialogSurface style={{ maxWidth: 720 }}>
        <DialogBody>
          <DialogTitle>{title}</DialogTitle>
          <DialogContent>
            <p className={ui.muted} style={{ margin: 0 }}>
              {intro}
            </p>
            {rows.length > 0 && (
              <table className={s.table}>
                <thead>
                  <tr>
                    <th scope="col">{t.conflict.field}</th>
                    <th scope="col">{t.conflict.savedBy(by)}</th>
                    <th scope="col">{t.conflict.yourEdit}</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr key={row.field}>
                      <th scope="row" style={{ fontWeight: 600 }}>
                        {row.field}
                      </th>
                      <td className={row.mono ? ui.mono : undefined}>
                        <span className={ui.old}>{row.theirs}</span>
                      </td>
                      <td className={row.mono ? ui.mono : undefined}>
                        <span className={ui.new}>{row.mine}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            <p style={{ margin: 0 }}>{t.conflict.explain(by)}</p>
          </DialogContent>
          <DialogActions>
            <Button onClick={onBack}>{t.conflict.back}</Button>
            <Button appearance="primary" onClick={onReload}>
              {t.conflict.reload}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
