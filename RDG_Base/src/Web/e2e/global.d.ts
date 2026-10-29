import type { MockApi } from '../src/mocks/handlers';

declare global {
  interface Window {
    __rdgMock?: MockApi;
  }
}
