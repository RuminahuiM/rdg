// Access denied, error with correlation ID, not found, and the full-page loading state.
import { Button, Spinner, makeStyles, tokens } from '@fluentui/react-components';
import { Link as RouterLink, isRouteErrorResponse, useRouteError } from 'react-router-dom';
import { ApiError } from '../api/client';
import { Header } from '../layout/Header';
import { CopyButton } from '../components/CopyButton';
import { PageHeader, Section, useUiStyles } from '../components/ui';
import { t } from '../strings/en';

const useStyles = makeStyles({
  standalone: { minHeight: '100vh', display: 'flex', flexDirection: 'column', backgroundColor: tokens.colorNeutralBackground2 },
  centre: { flex: 1, display: 'flex', justifyContent: 'center', alignItems: 'flex-start', padding: '48px 16px' },
  box: { maxWidth: '560px', width: '100%' },
  h1: { margin: '0 0 12px', fontSize: tokens.fontSizeBase500, fontWeight: tokens.fontWeightSemibold },
  p: { margin: '0 0 12px', fontSize: tokens.fontSizeBase300 },
  id: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    flexWrap: 'wrap',
    padding: '10px 12px',
    margin: '12px 0',
    backgroundColor: tokens.colorNeutralBackground3,
    borderRadius: tokens.borderRadiusMedium,
    fontSize: tokens.fontSizeBase200,
  },
  code: { fontFamily: '"Cascadia Code", Consolas, ui-monospace, monospace', overflowWrap: 'anywhere' },
  buttons: { display: 'flex', gap: '8px', marginTop: '16px', flexWrap: 'wrap' },
});

export function FullPageMessage({ text, busy }: { text: string; busy?: boolean }) {
  const s = useStyles();
  return (
    <div className={s.standalone}>
      <Header />
      <div className={s.centre} role="status">
        {busy ? <Spinner label={text} /> : text}
      </div>
    </div>
  );
}

export function AccessDenied({ upn }: { upn: string | null }) {
  const s = useStyles();
  const ui = useUiStyles();
  return (
    <div className={s.standalone}>
      <Header />
      <div className={s.centre}>
        <section className={`${ui.card} ${s.box}`}>
          <h1 className={s.h1}>{t.denied.title}</h1>
          <p className={s.p}>
            {upn ? (
              <>
                {t.denied.signedInAs} <strong>{upn}</strong>
                {t.denied.noRole}
              </>
            ) : (
              t.denied.noRoleUnknown
            )}
          </p>
          <p className={`${s.p} ${ui.muted}`}>{t.denied.ask}</p>
          <div className={s.buttons}>
            <Button as="a" href="/.auth/logout?post_logout_redirect_uri=/">
              {t.denied.signOut}
            </Button>
            <Button as="a" href={`/.auth/logout?post_logout_redirect_uri=${encodeURIComponent('/.auth/login/aad')}`}>
              {t.denied.otherAccount}
            </Button>
          </div>
        </section>
      </div>
    </div>
  );
}

function messageOf(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 0) return t.error.offline;
    if (error.status === 429) return t.error.throttled(error.problem.retryAfterSeconds ?? 30);
    return error.problem.detail ?? error.problem.title;
  }
  return t.error.detail;
}

/** "Something went wrong" with the correlation ID to report. Inside the shell or standalone. */
export function ErrorView({ error, onRetry, standalone }: { error: unknown; onRetry?: () => void; standalone?: boolean }) {
  const s = useStyles();
  const ui = useUiStyles();
  const correlationId = error instanceof ApiError ? error.correlationId : '';
  const body = (
    <section className={`${ui.card} ${s.box}`} role="alert">
      <h1 className={s.h1}>{t.error.title}</h1>
      <p className={s.p}>{t.error.detail}</p>
      {error instanceof ApiError && error.status !== 500 && <p className={`${s.p} ${ui.muted}`}>{messageOf(error)}</p>}
      {correlationId && (
        <>
          <div className={s.id}>
            <span className={ui.muted}>{t.error.correlationId}</span>
            <span className={s.code} data-testid="correlation-id">
              {correlationId}
            </span>
            <CopyButton text={correlationId} size="small" />
          </div>
          <p className={`${s.p} ${ui.muted}`}>{t.error.hint}</p>
        </>
      )}
      <div className={s.buttons}>
        {onRetry && (
          <Button appearance="primary" onClick={onRetry}>
            {t.common.retry}
          </Button>
        )}
        <Button as="a" href="/">
          {t.error.backToGroups}
        </Button>
      </div>
    </section>
  );
  if (!standalone) return body;
  return (
    <div className={s.standalone}>
      <Header />
      <div className={s.centre}>{body}</div>
    </div>
  );
}

export function RouteErrorPage() {
  const error = useRouteError();
  if (isRouteErrorResponse(error) && error.status === 404) return <NotFoundPage />;
  return <ErrorView error={error} onRetry={() => window.location.reload()} standalone />;
}

export function NotFoundPage() {
  const ui = useUiStyles();
  return (
    <div className={ui.page}>
      <PageHeader title={t.error.notFoundTitle} />
      <Section>
        <p>{t.error.notFoundDetail}</p>
        <RouterLink to="/">{t.error.backToGroups}</RouterLink>
      </Section>
    </div>
  );
}
