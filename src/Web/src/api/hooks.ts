// TanStack Query hooks, one per API operation.
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { request, requestAll } from './client';
import type {
  AuditEntry,
  Definition,
  DefinitionInput,
  DirectoryGroup,
  DirectoryUser,
  Me,
  PreviewInput,
  PreviewResult,
  RuleValidationResult,
  Run,
  RunPage,
  Settings,
  SettingsInput,
  SyncAccepted,
  GroupType,
} from './types';

export const keys = {
  me: ['me'] as const,
  settings: ['settings'] as const,
  definitions: ['definitions'] as const,
  definition: (id: string) => ['definitions', id] as const,
  definitionRuns: (id: string) => ['runs', 'definition', id] as const,
  runs: (filter: RunFilter) => ['runs', 'all', filter] as const,
  audit: (filter: AuditFilter) => ['audit', filter] as const,
  users: (search: string) => ['directory', 'users', search] as const,
  groups: (search: string) => ['directory', 'groups', search] as const,
};

export function useMe() {
  return useQuery({ queryKey: keys.me, queryFn: async () => (await request<Me>('/me')).data, staleTime: 5 * 60_000 });
}

export function useSettings() {
  return useQuery({ queryKey: keys.settings, queryFn: async () => (await request<Settings>('/settings')).data });
}

export function useDefinitions(refetchInterval: number | false = false) {
  return useQuery({
    queryKey: keys.definitions,
    queryFn: () => requestAll<Definition>('/definitions'),
    refetchInterval,
  });
}

export function useDefinition(id: string | undefined, refetchInterval: number | false = false) {
  return useQuery({
    queryKey: keys.definition(id ?? ''),
    queryFn: async () => (await request<Definition>(`/definitions/${id}`)).data,
    enabled: Boolean(id),
    refetchInterval,
  });
}

export function useDefinitionRuns(id: string | undefined) {
  return useQuery({
    queryKey: keys.definitionRuns(id ?? ''),
    queryFn: async () => (await request<RunPage>(`/definitions/${id}/runs`)).data.items,
    enabled: Boolean(id),
  });
}

export interface RunFilter {
  definitionId?: string;
  result?: string;
  since?: string;
}

/** Activity: the latest runs, across all definitions or for one. */
export function useRuns(filter: RunFilter) {
  return useQuery({
    queryKey: keys.runs(filter),
    queryFn: async (): Promise<Run[]> => {
      if (filter.definitionId) {
        const items = await requestAll<Run>(`/definitions/${filter.definitionId}/runs`, {}, 4);
        return items.filter((run) => (!filter.result || run.result === filter.result) && (!filter.since || run.startedAt >= filter.since));
      }
      return requestAll<Run>('/runs', { result: filter.result, since: filter.since }, 4);
    },
    placeholderData: keepPreviousData,
  });
}

export interface AuditFilter {
  definitionId?: string;
  by?: string;
  from?: string;
}

export function useAudit(filter: AuditFilter) {
  return useQuery({
    queryKey: keys.audit(filter),
    queryFn: () => requestAll<AuditEntry>('/audit', { ...filter }, 4),
    placeholderData: keepPreviousData,
  });
}

export function useUserSearch(search: string) {
  return useQuery({
    queryKey: keys.users(search),
    queryFn: async () => (await request<{ items: DirectoryUser[] }>('/directory/users', { query: { search } })).data.items,
    enabled: search.length >= 2,
    staleTime: 60_000,
  });
}

export function useGroupSearch(search: string) {
  return useQuery({
    queryKey: keys.groups(search),
    queryFn: async () => (await request<{ items: DirectoryGroup[] }>('/directory/groups', { query: { search } })).data.items,
    enabled: search.length >= 2,
    staleTime: 60_000,
  });
}

/**
 * Refetches definitions after a write. The write's answer isn't put into the cache: only
 * GET /definitions/{id} carries the names of included and excluded users.
 */
function useInvalidateDefinitions() {
  const client = useQueryClient();
  return () => {
    void client.invalidateQueries({ queryKey: keys.definitions });
    void client.invalidateQueries({ queryKey: ['audit'] });
  };
}

export function useCreateDefinition() {
  const done = useInvalidateDefinitions();
  return useMutation({
    mutationFn: async (input: DefinitionInput) => (await request<Definition>('/definitions', { method: 'POST', body: input })).data,
    onSuccess: done,
  });
}

export function useUpdateDefinition() {
  const done = useInvalidateDefinitions();
  return useMutation({
    mutationFn: async (args: { id: string; etag: string; input: DefinitionInput }) =>
      (await request<Definition>(`/definitions/${args.id}`, { method: 'PUT', body: args.input, ifMatch: args.etag })).data,
    onSuccess: done,
  });
}

export function useDeleteDefinition() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (args: { id: string; etag: string; force?: boolean }) => {
      await request<undefined>(`/definitions/${args.id}`, {
        method: 'DELETE',
        ifMatch: args.etag,
        query: { force: args.force ? true : undefined },
      });
    },
    onSuccess: (_data, args) => {
      client.removeQueries({ queryKey: keys.definition(args.id) });
      void client.invalidateQueries({ queryKey: keys.definitions });
      void client.invalidateQueries({ queryKey: ['audit'] });
    },
  });
}

export function useSyncDefinition() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => (await request<SyncAccepted>(`/definitions/${id}/sync`, { method: 'POST' })).data,
    onSuccess: () => void client.invalidateQueries({ queryKey: ['audit'] }),
  });
}

export function useApproveDefinition() {
  const done = useInvalidateDefinitions();
  return useMutation({
    mutationFn: async (args: { id: string; kind: 'changeLimit' | 'adopt'; diffHash: string }) =>
      (
        await request<Definition>(`/definitions/${args.id}/approve`, {
          method: 'POST',
          body: { kind: args.kind, diffHash: args.diffHash },
        })
      ).data,
    onSuccess: done,
  });
}

export function useUpdateSettings() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (args: { etag: string; input: SettingsInput }) =>
      (await request<Settings>('/settings', { method: 'PUT', body: args.input, ifMatch: args.etag })).data,
    onSuccess: (settings) => {
      client.setQueryData(keys.settings, settings);
      void client.invalidateQueries({ queryKey: ['audit'] });
    },
  });
}

export async function validateRule(rule: string, groupType?: GroupType, signal?: AbortSignal) {
  return (await request<RuleValidationResult>('/rules/validate', { method: 'POST', body: { rule, groupType }, signal })).data;
}

export function usePreview() {
  return useMutation({
    mutationFn: async (input: PreviewInput) => (await request<PreviewResult>('/preview', { method: 'POST', body: input })).data,
  });
}

/** Copies the editable fields of a stored definition into a request body. */
export function toInput(definition: Definition): DefinitionInput {
  const target: DefinitionInput['target'] = { mode: definition.target.mode };
  if (definition.target.groupId) target.groupId = definition.target.groupId;
  if (definition.target.displayName) target.displayName = definition.target.displayName;
  if (definition.target.mailNickname) target.mailNickname = definition.target.mailNickname;
  if (definition.target.mode === 'adopt') target.renameOnAdopt = Boolean(definition.target.renameOnAdopt);
  return {
    name: definition.name,
    groupType: definition.groupType,
    target,
    rule: definition.rule,
    includeUserIds: [...definition.includeUserIds],
    excludeUserIds: [...definition.excludeUserIds],
    includeDisabled: definition.includeDisabled,
    includeGuests: definition.includeGuests,
    frequencyMinutes: definition.frequencyMinutes,
    enabled: definition.enabled,
    dryRun: definition.dryRun,
    changeLimitPercent: definition.changeLimitPercent,
    allowEmpty: definition.allowEmpty,
    compareGroupId: definition.compareGroupId,
  };
}
