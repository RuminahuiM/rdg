// Who is signed in: GET /api/me on start. Unknown session → sign-in; no role → Access denied.
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { ApiError, SignedOutError, signInUrl } from '../api/client';
import { useMe } from '../api/hooks';
import type { Me } from '../api/types';
import { AccessDenied, ErrorView, FullPageMessage } from '../pages/ErrorPages';
import { t } from '../strings/en';

export interface Session {
  me: Me;
  isAdmin: boolean;
  readOnly: boolean;
}

const SessionContext = createContext<Session | null>(null);

export function useSession(): Session {
  const session = useContext(SessionContext);
  if (!session) throw new Error('useSession outside SessionGate');
  return session;
}

/** The Static Web App's own view of the user, for the Access denied page. */
async function readPrincipalName(): Promise<string | null> {
  try {
    const response = await fetch('/.auth/me', { credentials: 'same-origin' });
    if (!response.ok) return null;
    const body = (await response.json()) as { clientPrincipal?: { userDetails?: string } | null };
    return body.clientPrincipal?.userDetails ?? null;
  } catch {
    return null;
  }
}

function Denied() {
  const [upn, setUpn] = useState<string | null>(null);
  useEffect(() => {
    void readPrincipalName().then(setUpn);
  }, []);
  return <AccessDenied upn={upn} />;
}

export function SessionGate({ children }: { children: ReactNode }) {
  const me = useMe();

  useEffect(() => {
    if (me.error instanceof SignedOutError) window.location.assign(signInUrl());
  }, [me.error]);

  if (me.isPending) return <FullPageMessage busy text={t.app.loading} />;
  if (me.error instanceof SignedOutError) return <FullPageMessage busy text={t.error.signedOut} />;
  if (me.error instanceof ApiError && me.error.status === 403) return <Denied />;
  if (me.error) return <ErrorView error={me.error} onRetry={() => void me.refetch()} standalone />;
  if (me.data.roles.length === 0) return <Denied />;

  const session: Session = {
    me: me.data,
    isAdmin: me.data.roles.includes('admin'),
    readOnly: me.data.accessMode === 'read-only',
  };
  return <SessionContext.Provider value={session}>{children}</SessionContext.Provider>;
}
