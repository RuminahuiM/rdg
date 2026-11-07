import { FluentProvider } from '@fluentui/react-components';
import { MutationCache, QueryCache, QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createBrowserRouter, RouterProvider, type RouteObject } from 'react-router-dom';
import { lazy, Suspense, useState } from 'react';
import { Spinner } from '@fluentui/react-components';
import { ApiError, SignedOutError, signInUrl } from './api/client';
import { SessionGate } from './auth/session';
import { Shell } from './layout/Shell';
import { GroupsPage } from './pages/GroupsPage';

import { ActivityPage } from './pages/ActivityPage';
import { AuditPage } from './pages/AuditPage';
import { SettingsPage } from './pages/SettingsPage';
import { NotFoundPage, RouteErrorPage } from './pages/ErrorPages';
import { themeFor, useColorScheme } from './theme';

// The group page carries CodeMirror; load it on first use to keep the first load small.
const GroupPage = lazy(() => import('./pages/group/GroupPage').then((m) => ({ default: m.GroupPage })));
const group = (
  <Suspense fallback={<Spinner />}>
    <GroupPage />
  </Suspense>
);

export const routes: RouteObject[] = [
  {
    element: <Shell />,
    errorElement: <RouteErrorPage />,
    children: [
      { index: true, element: <GroupsPage /> },
      { path: 'groups/new', element: group },
      { path: 'groups/:id', element: group },
      { path: 'activity', element: <ActivityPage /> },
      { path: 'audit', element: <AuditPage /> },
      { path: 'settings', element: <SettingsPage /> },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
];

/** An expired session anywhere sends the user to sign-in and back to the same page. */
function onError(error: unknown) {
  if (error instanceof SignedOutError) window.location.assign(signInUrl());
}

export function createQueryClient(): QueryClient {
  return new QueryClient({
    queryCache: new QueryCache({ onError }),
    mutationCache: new MutationCache({ onError }),
    defaultOptions: {
      queries: {
        staleTime: 15_000,
        refetchOnWindowFocus: true,
        // Retry network trouble once; never retry what the API refused on purpose.
        retry: (count, error) =>
          count < 1 && !(error instanceof SignedOutError) && !(error instanceof ApiError && error.status >= 400 && error.status < 500),
      },
      mutations: { retry: false },
    },
  });
}

export function App() {
  const scheme = useColorScheme();
  const [client] = useState(createQueryClient);
  const [router] = useState(() => createBrowserRouter(routes));
  return (
    <FluentProvider theme={themeFor(scheme)} style={{ minHeight: '100vh' }}>
      <QueryClientProvider client={client}>
        <SessionGate>
          <RouterProvider router={router} />
        </SessionGate>
      </QueryClientProvider>
    </FluentProvider>
  );
}
