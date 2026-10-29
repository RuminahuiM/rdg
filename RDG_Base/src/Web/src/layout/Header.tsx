import { Avatar, Menu, MenuItem, MenuList, MenuPopover, MenuTrigger, makeStyles, tokens, Button } from '@fluentui/react-components';
import { t } from '../strings/en';
import { nameFromUpn } from '../format';

const useStyles = makeStyles({
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    height: '48px',
    padding: '0 20px',
    backgroundColor: tokens.colorBrandBackground,
    color: tokens.colorNeutralForegroundOnBrand,
    flexShrink: 0,
  },
  brand: { display: 'flex', alignItems: 'center', gap: '10px', fontWeight: tokens.fontWeightSemibold, fontSize: '15px' },
  user: { display: 'flex', alignItems: 'center', gap: '12px', fontSize: tokens.fontSizeBase200 },
  avatarButton: { minWidth: 0, padding: 0, borderRadius: '50%', color: 'inherit', ':hover': { backgroundColor: 'transparent' } },
});

export function Logo() {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="9" cy="8" r="3.5" />
      <path d="M2.5 20c0-3.6 2.9-6.5 6.5-6.5s6.5 2.9 6.5 6.5" />
      <path d="M16 4.5a3.5 3.5 0 0 1 0 7" />
      <path d="M18.5 13.8c1.8.9 3 2.9 3 6.2" />
    </svg>
  );
}

export function Header({ upn, roleLabel }: { upn?: string; roleLabel?: string }) {
  const s = useStyles();
  return (
    <header className={s.header}>
      <div className={s.brand}>
        <Logo />
        <span>{t.app.title}</span>
      </div>
      {upn && (
        <div className={s.user}>
          {roleLabel && <span>{roleLabel}</span>}
          <Menu>
            <MenuTrigger disableButtonEnhancement>
              <Button appearance="transparent" className={s.avatarButton} aria-label={t.app.userMenu(upn)}>
                <Avatar name={nameFromUpn(upn)} size={28} color="neutral" />
              </Button>
            </MenuTrigger>
            <MenuPopover>
              <MenuList>
                <MenuItem disabled>{t.app.userMenu(upn)}</MenuItem>
                <MenuItem onClick={() => window.location.assign('/.auth/logout?post_logout_redirect_uri=/')}>{t.app.signOut}</MenuItem>
              </MenuList>
            </MenuPopover>
          </Menu>
        </div>
      )}
    </header>
  );
}
