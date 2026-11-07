import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderApp, startMockServer } from './test/render';

const EOP = 'def-01JA7K3M9QXR4T6V8W0Y2Z0001';

describe('app against the mock API', () => {
  let stop: () => void = () => undefined;
  afterEach(() => stop());

  it('lists the groups with result counts and filters them', async () => {
    ({ stop } = startMockServer());
    renderApp('/');
    const table = await screen.findByRole('table');
    expect(within(table).getAllByRole('row')).toHaveLength(11); // header + 10 definitions
    expect(within(table).getByText('Blocked: change limit')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Needs attention \(2\)/ })).toBeInTheDocument();
    await userEvent.type(screen.getByPlaceholderText('Group name'), 'board');
    await waitFor(() => expect(within(table).getAllByRole('row')).toHaveLength(4));
  });

  it('shows the empty state when there are no definitions', async () => {
    ({ stop } = startMockServer({ empty: true }));
    renderApp('/');
    expect(await screen.findByText('No groups yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'New group' })).toBeInTheDocument();
  });

  it('shows the reader view without edit controls', async () => {
    ({ stop } = startMockServer({ role: 'reader' }));
    renderApp(`/groups/${EOP}`);
    expect(await screen.findByText(/You have read access/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Save' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Copy rule' })).toBeInTheDocument();
    expect(screen.getByText('Lea Keller')).toBeInTheDocument();
  });

  it('shows Access denied for a user without a role', async () => {
    ({ stop } = startMockServer({ role: 'none' }));
    renderApp('/');
    expect(await screen.findByText("You don't have access to Dynamic Groups")).toBeInTheDocument();
    expect(await screen.findByText('marco.rossi@contoso.org')).toBeInTheDocument();
  });

  it('shows the error page with the correlation ID when the API fails', async () => {
    const server = startMockServer();
    stop = server.stop;
    server.mock.failNext('/api/definitions', 500);
    renderApp('/');
    expect(await screen.findByText('Something went wrong')).toBeInTheDocument();
    expect(screen.getByTestId('correlation-id').textContent).toMatch(/^4f2a9c1e-/);
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(await screen.findByRole('table')).toBeInTheDocument();
  });

  it('opens the conflict dialog when someone else saved first, and reloads their version', async () => {
    const server = startMockServer();
    stop = server.stop;
    renderApp(`/groups/${EOP}`);
    const name = await screen.findByRole('textbox', { name: /Name/ });
    server.mock.touch(EOP, { frequencyMinutes: 30 });
    await userEvent.type(name, ' (new)');
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));
    const dialog = await screen.findByRole('alertdialog');
    expect(within(dialog).getByText('Someone else changed this group')).toBeInTheDocument();
    expect(within(dialog).getByText('Frequency')).toBeInTheDocument();
    expect(within(dialog).getByText('30 min')).toBeInTheDocument();
    // Under load, tabster in jsdom may still mark the opening surface aria-hidden; the e2e test covers the real browser.
    await userEvent.click(await screen.findByRole('button', { name: 'Reload latest version', hidden: true }));
    await waitFor(() => expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument());
    expect(screen.getByRole('textbox', { name: /Name/ })).toHaveValue('EOP Strict – Management');
    expect(screen.getByRole('combobox', { name: 'Frequency' })).toHaveValue('30');
  });

  it('saves a group and keeps the names of included and excluded users', async () => {
    ({ stop } = startMockServer());
    renderApp(`/groups/${EOP}`);
    await userEvent.click(await screen.findByRole('switch', { name: 'Dry run' }));
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled());
    expect(screen.getByRole('switch', { name: 'Dry run' })).toBeChecked();
    expect(screen.getByText('Lea Keller')).toBeInTheDocument();
    expect(screen.getByText('svc-backup')).toBeInTheDocument();
  });

  it('pauses syncing in Settings and resumes from the banner', async () => {
    ({ stop } = startMockServer());
    renderApp('/settings');
    await userEvent.click(await screen.findByRole('switch', { name: 'Pause all syncing' }));
    await userEvent.click(screen.getByRole('button', { name: 'Save settings' }));
    const banner = await screen.findByText('Syncing is paused');
    expect(banner).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Resume syncing' }));
    await waitFor(() => expect(screen.queryByText('Syncing is paused')).not.toBeInTheDocument());
    expect(screen.getByRole('switch', { name: 'Pause all syncing' })).not.toBeChecked();
  });
});
