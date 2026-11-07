import { createContext, useContext } from 'react';

export type Notify = (text: string, intent?: 'success' | 'info' | 'warning' | 'error') => void;
export const NotifyContext = createContext<Notify>(() => undefined);

/** Shows a short toast at the bottom; pages call it after saves and syncs. */
export function useNotify(): Notify {
  return useContext(NotifyContext);
}
