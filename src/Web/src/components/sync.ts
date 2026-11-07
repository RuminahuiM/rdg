// "Sync now": records the request and polls the definitions until the engine reports it
// handled (status.handledSyncRequestAt reaches requestedAt), as the API contract describes.
import { useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { keys, useDefinitions, useSyncDefinition } from '../api/hooks';
import type { Definition } from '../api/types';
import { ApiError } from '../api/client';
import { useNotify } from './notify';
import { t } from '../strings/en';

type Pending = Record<string, { requestedAt: string; name: string; since: number }>;
const pendingKey = ['syncPending'] as const;
const pollMs = 3000;
const giveUpMs = 10 * 60_000;

function usePending(): Pending {
  return useQuery({ queryKey: pendingKey, queryFn: () => ({}) as Pending, initialData: {} as Pending, staleTime: Infinity }).data;
}

export function useSyncNow() {
  const client = useQueryClient();
  const mutation = useSyncDefinition();
  const notify = useNotify();
  const pending = usePending();

  const start = (definition: Definition) => {
    mutation.mutate(definition.id, {
      onSuccess: (accepted) => {
        client.setQueryData<Pending>(pendingKey, (old) => ({
          ...old,
          [definition.id]: { requestedAt: accepted.requestedAt, name: definition.name, since: Date.now() },
        }));
        notify(
          accepted.jobStarted || accepted.existingRequest ? t.groups.syncRequested(definition.name) : t.groups.syncQueued(definition.name),
          'info',
        );
      },
      onError: (error) => notify(error instanceof ApiError ? error.message : t.error.detail, 'error'),
    });
  };
  return { start, isSyncing: (id: string) => Boolean(pending[id]), isStarting: mutation.isPending };
}

/** Mounted once in the shell; refreshes definitions while a sync request is open. */
export function SyncPoller() {
  const client = useQueryClient();
  const pending = usePending();
  const active = Object.keys(pending).length > 0;
  const definitions = useDefinitions(active ? pollMs : false);
  const notify = useNotify();

  useEffect(() => {
    // Wait for the list; an unloaded list must not end the open requests.
    if (!active || !definitions.data) return;
    const items = definitions.data;
    const finished = new Set<string>();
    for (const [id, entry] of Object.entries(pending)) {
      const definition = items.find((d) => d.id === id);
      const handled = definition?.status?.handledSyncRequestAt;
      if (definition && handled && handled >= entry.requestedAt) {
        finished.add(id);
        void client.invalidateQueries({ queryKey: keys.definition(id) });
        void client.invalidateQueries({ queryKey: ['runs'] });
        notify(t.groups.syncDone(entry.name), 'success');
      } else if (!definition || Date.now() - entry.since > giveUpMs) {
        finished.add(id);
      }
    }
    if (finished.size) client.setQueryData(pendingKey, Object.fromEntries(Object.entries(pending).filter(([id]) => !finished.has(id))));
  }, [active, definitions.data, pending, client, notify]);

  return null;
}
