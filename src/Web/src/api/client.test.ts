import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { ApiError, SignedOutError, buildUrl, request, requestAll } from './client';

const server = setupServer();
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('api client', () => {
  it('builds URLs without empty query values', () => {
    expect(buildUrl('/runs', { result: 'OK', since: undefined, x: '', y: null })).toBe('/api/runs?result=OK');
  });

  it('returns data and ETag, and sends If-Match and JSON', async () => {
    let seen: { ifMatch: string | null; type: string | null; body: unknown } | null = null;
    server.use(
      http.put('*/api/settings', async ({ request: r }) => {
        seen = { ifMatch: r.headers.get('If-Match'), type: r.headers.get('Content-Type'), body: await r.json() };
        return HttpResponse.json({ ok: true }, { headers: { ETag: '"2"' } });
      }),
    );
    const response = await request<{ ok: boolean }>('/settings', { method: 'PUT', body: { paused: true }, ifMatch: '"1"' });
    expect(response).toMatchObject({ data: { ok: true }, etag: '"2"', status: 200 });
    expect(seen).toEqual({ ifMatch: '"1"', type: 'application/json', body: { paused: true } });
  });

  it('throws problems as ApiError with the correlation ID', async () => {
    server.use(
      http.get('*/api/definitions/x', () =>
        HttpResponse.json(
          { type: 'about:blank', title: 'Definition not found', status: 404, correlationId: 'c-1' },
          { status: 404, headers: { 'Content-Type': 'application/problem+json' } },
        ),
      ),
    );
    const error = await request('/definitions/x').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).status).toBe(404);
    expect((error as ApiError).correlationId).toBe('c-1');
    expect((error as ApiError).message).toBe('Definition not found');
  });

  it('builds a problem for answers that are not JSON', async () => {
    server.use(
      http.get(
        '*/api/me',
        () =>
          new HttpResponse('<html>bad gateway</html>', {
            status: 502,
            statusText: 'Bad Gateway',
            headers: { 'Content-Type': 'text/html' },
          }),
      ),
    );
    const error = (await request('/me').catch((e: unknown) => e)) as ApiError;
    expect(error.status).toBe(502);
    expect(error.problem.title).toBe('Bad Gateway');
  });

  it('treats 401 as signed out', async () => {
    server.use(http.get('*/api/me', () => new HttpResponse(null, { status: 401 })));
    await expect(request('/me')).rejects.toBeInstanceOf(SignedOutError);
  });

  it('reads every page of a list', async () => {
    server.use(
      http.get('*/api/runs', ({ request: r }) => {
        const token = new URL(r.url).searchParams.get('continuationToken');
        return HttpResponse.json(token ? { items: [3], continuationToken: null } : { items: [1, 2], continuationToken: 'next' });
      }),
    );
    expect(await requestAll<number>('/runs')).toEqual([1, 2, 3]);
  });
});
