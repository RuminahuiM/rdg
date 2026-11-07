// The mock API follows the contract's rules, so the app is tested against realistic answers.
import { request } from '../api/client';
import type { Definition, Settings } from '../api/types';
import { createTestServer } from './node';

describe('mock API', () => {
  let close: () => void = () => undefined;
  afterEach(() => close());

  const start = (scenario = {}) => {
    const { mock, server } = createTestServer(scenario);
    server.listen({ onUnhandledRequest: 'error' });
    close = () => server.close();
    return mock;
  };

  it('refuses writes for readers with 403', async () => {
    start({ role: 'reader' });
    const settings = (await request<Settings>('/settings')).data;
    await expect(request('/settings', { method: 'PUT', body: {}, ifMatch: settings.etag })).rejects.toMatchObject({ status: 403 });
    await expect(request('/definitions/x/sync', { method: 'POST' })).rejects.toMatchObject({ status: 403 });
  });

  it('needs If-Match (428) and refuses an outdated one (412) with who changed it', async () => {
    const mock = start();
    const id = mock.data.definitions[0]?.id ?? '';
    const definition = (await request<Definition>(`/definitions/${id}`)).data;
    const input = { name: definition.name, groupType: definition.groupType, target: definition.target, rule: definition.rule };
    await expect(request(`/definitions/${id}`, { method: 'PUT', body: input })).rejects.toMatchObject({ status: 428 });
    mock.touch(id, { dryRun: true }, 'lea.keller@contoso.org');
    await expect(request(`/definitions/${id}`, { method: 'PUT', body: input, ifMatch: definition.etag })).rejects.toMatchObject({
      status: 412,
      problem: { current: { updatedBy: 'lea.keller@contoso.org' } },
    });
  });

  it('refuses to delete a referenced definition unless forced', async () => {
    const mock = start();
    const svc = mock.data.definitions.find((d) => d.name === 'Service Accounts');
    if (!svc) throw new Error('missing');
    await expect(request(`/definitions/${svc.id}`, { method: 'DELETE', ifMatch: svc.etag })).rejects.toMatchObject({
      status: 409,
      problem: { referencedBy: [{ name: 'All Staff Zürich' }] },
    });
    await request(`/definitions/${svc.id}`, { method: 'DELETE', ifMatch: svc.etag, query: { force: true } });
    expect(mock.data.definitions.some((d) => d.id === svc.id)).toBe(false);
  });

  it('approves only the pending diff and the engine writes it', async () => {
    const mock = start();
    const intune = mock.data.definitions.find((d) => d.name === 'Intune – Field Laptops');
    const pending = intune?.status?.pendingApproval;
    if (!intune || !pending) throw new Error('missing');
    await expect(
      request(`/definitions/${intune.id}/approve`, { method: 'POST', body: { kind: 'changeLimit', diffHash: `sha256:${'0'.repeat(64)}` } }),
    ).rejects.toMatchObject({ status: 409 });
    await request(`/definitions/${intune.id}/approve`, { method: 'POST', body: { kind: 'changeLimit', diffHash: pending.diffHash } });
    await new Promise((resolve) => setTimeout(resolve, 150));
    const after = (await request<Definition>(`/definitions/${intune.id}`)).data;
    expect(after.status?.lastResult).toBe('OK');
    expect(after.status?.memberCount).toBe(226);
  });
});
