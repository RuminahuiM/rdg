// The mock API for Vitest (Node).
import { setupServer } from 'msw/node';
import { createMockApi, type Scenario } from './handlers';

export function createTestServer(scenario: Partial<Scenario> = {}) {
  const mock = createMockApi({ engineDelayMs: 50, ...scenario });
  const server = setupServer(...mock.handlers);
  return { mock, server };
}
