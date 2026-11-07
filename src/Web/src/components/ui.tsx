// Small layout pieces shared by the pages: page heading, section cards, label/value rows.
import type { ReactNode } from 'react';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';

export const useUiStyles = makeStyles({
  page: { display: 'flex', flexDirection: 'column', gap: '16px', minWidth: 0 },
  pageHeader: { display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '16px', flexWrap: 'wrap' },
  h1: { margin: 0, fontSize: tokens.fontSizeBase600, lineHeight: tokens.lineHeightBase600, fontWeight: tokens.fontWeightSemibold },
  intro: { margin: '4px 0 0', color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase300 },
  actions: { display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap' },
  card: {
    backgroundColor: tokens.colorNeutralBackground1,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusXLarge,
    padding: '20px',
    minWidth: 0,
  },
  cardFlush: { padding: 0, overflow: 'hidden' },
  cardHeader: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px', marginBottom: '16px' },
  h2: { margin: 0, fontSize: tokens.fontSizeBase400, lineHeight: tokens.lineHeightBase400, fontWeight: tokens.fontWeightSemibold },
  muted: { color: tokens.colorNeutralForeground3 },
  small: { fontSize: tokens.fontSizeBase200 },
  mono: { fontFamily: '"Cascadia Code", Consolas, ui-monospace, monospace', fontSize: tokens.fontSizeBase200 },
  stack: { display: 'flex', flexDirection: 'column', gap: '16px' },
  row: { display: 'flex', gap: '12px', alignItems: 'center', flexWrap: 'wrap' },
  stat: { fontSize: tokens.fontSizeHero700, fontWeight: tokens.fontWeightSemibold, lineHeight: tokens.lineHeightHero700 },
  dl: {
    display: 'grid',
    gridTemplateColumns: 'minmax(120px, max-content) 1fr',
    columnGap: '16px',
    rowGap: '10px',
    margin: 0,
    fontSize: tokens.fontSizeBase300,
    '& dt': { color: tokens.colorNeutralForeground3 },
    '& dd': { margin: 0, minWidth: 0, overflowWrap: 'anywhere' },
  },
  old: {
    backgroundColor: tokens.colorPaletteRedBackground1,
    color: tokens.colorPaletteRedForeground2,
    padding: '1px 4px',
    borderRadius: '3px',
  },
  new: {
    backgroundColor: tokens.colorPaletteGreenBackground1,
    color: tokens.colorPaletteGreenForeground2,
    padding: '1px 4px',
    borderRadius: '3px',
  },
  list: {
    listStyleType: 'none',
    margin: 0,
    padding: 0,
    display: 'flex',
    flexDirection: 'column',
    gap: '6px',
    fontSize: tokens.fontSizeBase300,
  },
  subhead: { fontSize: tokens.fontSizeBase300, fontWeight: tokens.fontWeightSemibold, margin: '16px 0 8px' },
  visuallyHidden: {
    position: 'absolute',
    width: '1px',
    height: '1px',
    overflow: 'hidden',
    clip: 'rect(0 0 0 0)',
    whiteSpace: 'nowrap',
  },
});

export function PageHeader({
  title,
  intro,
  actions,
  badges,
}: {
  title: ReactNode;
  intro?: ReactNode;
  actions?: ReactNode;
  badges?: ReactNode;
}) {
  const s = useUiStyles();
  return (
    <div className={s.pageHeader}>
      <div style={{ minWidth: 0 }}>
        <div className={s.row}>
          <h1 className={s.h1}>{title}</h1>
          {badges}
        </div>
        {intro && <p className={s.intro}>{intro}</p>}
      </div>
      {actions && <div className={s.actions}>{actions}</div>}
    </div>
  );
}

export function Section({
  title,
  actions,
  children,
  flush,
  className,
  labelId,
}: {
  title?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  flush?: boolean;
  className?: string;
  labelId?: string;
}) {
  const s = useUiStyles();
  return (
    <section className={mergeClasses(s.card, flush && s.cardFlush, className)} aria-labelledby={title ? labelId : undefined}>
      {(title || actions) && (
        <div className={s.cardHeader}>
          {title && (
            <h2 className={s.h2} id={labelId}>
              {title}
            </h2>
          )}
          {actions}
        </div>
      )}
      {children}
    </section>
  );
}
