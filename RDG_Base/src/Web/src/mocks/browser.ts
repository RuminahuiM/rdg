// Starts the mock API in the browser (`npm run dev:mock`, `npm run build:mock`).
// The scenario comes from the URL once (?mockRole=reader&mockPaused=1&mockEmpty=1&mockReadOnly=1)
// and is kept for the tab in sessionStorage. window.__rdgMock gives e2e tests access.
import { setupWorker } from 'msw/browser';
import { createMockApi, defaultScenario, type MockApi, type Scenario } from './handlers';

declare global {
  interface Window {
    __rdgMock?: MockApi;
  }
}

function readScenario(): Scenario {
  const key = 'rdg-mock-scenario';
  const params = new URLSearchParams(window.location.search);
  let stored: Partial<Scenario> = {};
  try {
    stored = JSON.parse(window.sessionStorage.getItem(key) ?? '{}') as Partial<Scenario>;
  } catch {
    stored = {};
  }
  const scenario: Scenario = { ...defaultScenario, ...stored };
  const role = params.get('mockRole');
  if (role === 'admin' || role === 'reader' || role === 'none' || role === 'signedOut') scenario.role = role;
  if (params.has('mockPaused')) scenario.paused = params.get('mockPaused') === '1';
  if (params.has('mockEmpty')) scenario.empty = params.get('mockEmpty') === '1';
  if (params.has('mockReadOnly')) scenario.readOnly = params.get('mockReadOnly') === '1';
  if (params.has('mockEngineMs')) scenario.engineDelayMs = Number(params.get('mockEngineMs')) || 0;
  try {
    window.sessionStorage.setItem(key, JSON.stringify(scenario));
  } catch {
    // Private mode: the scenario then lasts until the next full page load.
  }
  return scenario;
}

export async function startMockWorker(): Promise<void> {
  const mock = createMockApi(readScenario());
  window.__rdgMock = mock;
  const worker = setupWorker(...mock.handlers);
  await worker.start({ onUnhandledRequest: 'bypass', quiet: true });
  // Sign-in and sign-out links lead nowhere in the mock; show the app again instead.
  if (window.location.pathname.startsWith('/.auth/')) window.location.replace('/');
}
