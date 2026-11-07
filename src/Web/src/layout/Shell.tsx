// Frame of every page: header, paused / read-only banners, navigation, content, toasts.
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  Button,
  makeStyles,
  mergeClasses,
  tokens,
  Toaster,
  useId,
  useToastController,
  Toast,
  ToastTitle,
} from '@fluentui/react-components';
import { useCallback } from 'react';
import { NotifyContext, useNotify, type Notify } from '../components/notify';
import { Header } from './Header';
import { useSession } from '../auth/session';
import { useSettings, useUpdateSettings } from '../api/hooks';
import { t } from '../strings/en';
import { atWhen, shortName } from '../format';
import { ApiError } from '../api/client';
import type { Settings } from '../api/types';
import { SyncPoller } from '../components/sync';

const useStyles = makeStyles({
  root: { minHeight: '100vh', display: 'flex', flexDirection: 'column', backgroundColor: tokens.colorNeutralBackground2 },
  banner: {
    display: 'flex',
    flexWrap: 'wrap',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: '12px',
    padding: '10px 20px',
    fontSize: tokens.fontSizeBase300,
  },
  paused: {
    backgroundColor: tokens.colorPaletteYellowBackground1,
    color: tokens.colorPaletteYellowForeground2,
    borderBottom: `1px solid ${tokens.colorPaletteYellowBorder1}`,
  },
  readOnly: {
    backgroundColor: tokens.colorPaletteBlueBackground2,
    color: tokens.colorPaletteBlueForeground2,
    borderBottom: `1px solid ${tokens.colorPaletteBlueBorderActive}`,
  },
  body: { display: 'flex', flexWrap: 'wrap', flex: 1 },
  nav: {
    flex: '1 1 220px',
    maxWidth: '260px',
    padding: '16px 12px',
    backgroundColor: tokens.colorNeutralBackground3,
    borderRight: `1px solid ${tokens.colorNeutralStroke2}`,
    display: 'flex',
    flexDirection: 'column',
    gap: '2px',
    boxSizing: 'border-box',
    '@media (max-width: 700px)': {
      maxWidth: 'none',
      flexDirection: 'row',
      borderRight: 'none',
      borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    },
  },
  link: {
    display: 'flex',
    alignItems: 'center',
    padding: '9px 12px',
    borderRadius: tokens.borderRadiusLarge,
    color: tokens.colorNeutralForeground1,
    textDecoration: 'none',
    fontSize: tokens.fontSizeBase300,
    ':hover': { backgroundColor: tokens.colorSubtleBackgroundHover },
    ':focus-visible': { outlineWidth: '2px', outlineStyle: 'solid', outlineColor: tokens.colorStrokeFocus2, outlineOffset: '-2px' },
  },
  active: {
    backgroundColor: tokens.colorBrandBackground2,
    color: tokens.colorBrandForeground2,
    fontWeight: tokens.fontWeightSemibold,
    ':hover': { backgroundColor: tokens.colorBrandBackground2Hover },
  },
  main: {
    flex: '999 1 560px',
    minWidth: 0,
    padding: '24px 32px 40px',
    boxSizing: 'border-box',
    '@media (max-width: 700px)': { padding: '16px' },
  },
  skip: {
    position: 'absolute',
    left: '-9999px',
    ':focus': { left: '8px', top: '8px', zIndex: 10, padding: '8px', backgroundColor: tokens.colorNeutralBackground1 },
  },
});

export function PausedBanner({ settings }: { settings: Settings }) {
  const s = useStyles();
  const { isAdmin } = useSession();
  const update = useUpdateSettings();
  const notify = useNotify();
  const resume = () => {
    const { etag, pausedAt: _a, pausedBy: _b, updatedAt: _c, updatedBy: _d, ...input } = settings;
    update.mutate(
      { etag, input: { ...input, paused: false } },
      {
        onSuccess: () => notify(t.banner.resumed, 'success'),
        onError: (error) => notify(error instanceof ApiError ? error.message : t.error.detail, 'error'),
      },
    );
  };
  return (
    <div role="status" className={mergeClasses(s.banner, s.paused)}>
      <span>
        <strong>{t.banner.pausedTitle}</strong>{' '}
        {settings.pausedAt ? t.banner.pausedDetail(atWhen(settings.pausedAt), shortName(settings.pausedBy)) : t.banner.pausedDetailNoTime}
      </span>
      {isAdmin && (
        <Button onClick={resume} disabled={update.isPending}>
          {t.banner.resume}
        </Button>
      )}
    </div>
  );
}

export function Shell() {
  const s = useStyles();
  const { me, isAdmin, readOnly } = useSession();
  const settings = useSettings();
  const toasterId = useId('toaster');
  const { dispatchToast } = useToastController(toasterId);
  const notify = useCallback<Notify>(
    (text, intent = 'success') =>
      dispatchToast(
        <Toast>
          <ToastTitle>{text}</ToastTitle>
        </Toast>,
        { intent, timeout: intent === 'error' ? 8000 : 4000 },
      ),
    [dispatchToast],
  );

  const location = useLocation();
  const onGroups = location.pathname === '/' || location.pathname.startsWith('/groups');
  const links = [
    { to: '/', label: t.nav.groups, end: true },
    { to: '/activity', label: t.nav.activity },
    { to: '/audit', label: t.nav.audit },
    { to: '/settings', label: t.nav.settings },
  ];

  return (
    <NotifyContext.Provider value={notify}>
      <div className={s.root}>
        <a href="#main" className={s.skip}>
          {t.app.skipToContent}
        </a>
        <Header upn={me.upn} roleLabel={isAdmin ? t.app.roleAdmin : t.app.roleReader} />
        {settings.data?.paused && <PausedBanner settings={settings.data} />}
        {readOnly && (
          <div role="status" className={mergeClasses(s.banner, s.readOnly)}>
            <span>
              <strong>{t.banner.readOnlyTitle}</strong> {t.banner.readOnlyDetail}
            </span>
          </div>
        )}
        <div className={s.body}>
          <nav className={s.nav} aria-label={t.nav.label}>
            {links.map((link) =>
              link.end ? (
                <Link
                  key={link.to}
                  to={link.to}
                  className={mergeClasses(s.link, onGroups && s.active)}
                  aria-current={onGroups ? 'page' : undefined}
                >
                  {link.label}
                </Link>
              ) : (
                <NavLink key={link.to} to={link.to} className={({ isActive }) => mergeClasses(s.link, isActive && s.active)}>
                  {link.label}
                </NavLink>
              ),
            )}
          </nav>
          <main id="main" className={s.main} tabIndex={-1}>
            <Outlet />
          </main>
        </div>
        <Toaster toasterId={toasterId} position="bottom-end" />
        <SyncPoller />
      </div>
    </NotifyContext.Provider>
  );
}
