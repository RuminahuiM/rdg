// Renders the whole app (shell, session, routes) at a path against the mock API.
import { render } from '@testing-library/react';
import { FluentProvider, webLightTheme } from '@fluentui/react-components';
import { QueryClientProvider } from '@tanstack/react-query';
import { RouterProvider, createMemoryRouter } from 'react-router-dom';
import { createQueryClient, routes } from '../App';
import { SessionGate } from '../auth/session';
import { createTestServer } from '../mocks/node';
import type { Scenario } from '../mocks/handlers';

export function startMockServer(scenario: Partial<Scenario> = {}) {
  const { mock, server } = createTestServer(scenario);
  server.listen({ onUnhandledRequest: 'error' });
  return { mock, server, stop: () => server.close() };
}

export function renderApp(path: string) {
  const client = createQueryClient();
  client.setDefaultOptions({ queries: { ...client.getDefaultOptions().queries, retry: false } });
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  const view = render(
    <FluentProvider theme={webLightTheme}>
      <QueryClientProvider client={client}>
        <SessionGate>
          <RouterProvider router={router} />
        </SessionGate>
      </QueryClientProvider>
    </FluentProvider>,
  );
  return { ...view, router, client };
}
