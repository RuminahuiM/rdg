// Fetch wrapper for the RDG API: JSON in and out, ETags, RFC 9457 problems.
import type { Problem } from './types';

export const API_BASE = '/api';

/** Thrown for every non-2xx answer; carries the problem document when the API sent one. */
export class ApiError extends Error {
  readonly status: number;
  readonly problem: Problem;

  constructor(status: number, problem: Problem) {
    super(problem.detail ?? problem.title);
    this.name = 'ApiError';
    this.status = status;
    this.problem = problem;
  }

  get correlationId(): string {
    return this.problem.correlationId;
  }
}

/** The user isn't signed in (or the session expired). The caller sends them to sign-in. */
export class SignedOutError extends Error {
  constructor() {
    super('Not signed in');
    this.name = 'SignedOutError';
  }
}

export interface ApiResponse<T> {
  data: T;
  etag: string | null;
  status: number;
}

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  body?: unknown;
  ifMatch?: string;
  query?: Record<string, string | number | boolean | null | undefined>;
  signal?: AbortSignal;
}

export function buildUrl(path: string, query?: RequestOptions['query']): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== null && value !== '') params.set(key, String(value));
  }
  const text = params.toString();
  return `${API_BASE}${path}${text ? `?${text}` : ''}`;
}

/** Builds a problem for answers that aren't problem documents (gateway errors, HTML pages). */
function fallbackProblem(status: number, statusText: string, response: Response): Problem {
  return {
    type: 'about:blank',
    title: statusText || `HTTP ${status}`,
    status,
    correlationId: response.headers.get('x-correlation-id') ?? '',
  };
}

export async function request<T>(path: string, options: RequestOptions = {}): Promise<ApiResponse<T>> {
  const headers: Record<string, string> = { Accept: 'application/json, application/problem+json' };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  if (options.ifMatch) headers['If-Match'] = options.ifMatch;

  let response: Response;
  try {
    response = await fetch(buildUrl(path, options.query), {
      method: options.method ?? 'GET',
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      credentials: 'same-origin',
      // The Static Web App answers an expired session with a redirect to sign-in.
      redirect: 'manual',
      signal: options.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    throw new ApiError(0, { type: 'about:blank', title: 'The server could not be reached', status: 0, correlationId: '' });
  }

  if (response.type === 'opaqueredirect' || response.status === 401) throw new SignedOutError();

  const etag = response.headers.get('ETag');
  const type = response.headers.get('Content-Type') ?? '';
  const isJson = type.includes('json');

  if (!response.ok) {
    const problem = isJson ? ((await response.json()) as Problem) : fallbackProblem(response.status, response.statusText, response);
    throw new ApiError(response.status, problem);
  }
  const data = (response.status === 204 || !isJson ? undefined : await response.json()) as T;
  return { data, etag, status: response.status };
}

/** Reads every page of a paged list (continuationToken), up to a safety limit. */
export async function requestAll<T>(path: string, query: RequestOptions['query'] = {}, maxPages = 20): Promise<T[]> {
  const items: T[] = [];
  let token: string | null | undefined;
  for (let page = 0; page < maxPages; page += 1) {
    const { data } = await request<{ items: T[]; continuationToken?: string | null }>(path, {
      query: { ...query, continuationToken: token ?? undefined },
    });
    items.push(...data.items);
    token = data.continuationToken;
    if (!token) break;
  }
  return items;
}

export function signInUrl(returnTo: string = window.location.pathname + window.location.search): string {
  return `/.auth/login/aad?post_login_redirect_uri=${encodeURIComponent(returnTo)}`;
}
