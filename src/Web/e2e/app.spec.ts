// End-to-end flows against the mock build (the 14 mockup screens and their main actions).
import { expect, test, type Page } from '@playwright/test';

const EOP = 'def-01JA7K3M9QXR4T6V8W0Y2Z0001';
const INTUNE = 'def-01JA7K3M9QXR4T6V8W0Y2Z0004';
const BOARD = 'def-01JA7K3M9QXR4T6V8W0Y2Z0006';
const SVC = 'def-01JA7K3M9QXR4T6V8W0Y2Z0008';

/** A toast; Fluent also repeats it in an aria-live region, so match the visible title only. */
const toast = (page: Page, text: string) => page.locator('.fui-ToastTitle', { hasText: text });

async function open(page: Page, path: string) {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto(path);
  return errors;
}

test('groups list: counts, filters and sync now', async ({ page }) => {
  const errors = await open(page, '/?mockEngineMs=300');
  const table = page.getByRole('table');
  await expect(table.getByRole('row')).toHaveCount(11);
  await page.getByRole('button', { name: /Needs attention/ }).click();
  await expect(table.getByRole('row')).toHaveCount(3);
  await page.getByRole('button', { name: /Needs attention/ }).click();
  await page.getByRole('button', { name: 'Sync now Management Board' }).click();
  await expect(toast(page, 'Sync requested for Management Board.')).toBeVisible();
  await expect(toast(page, 'Management Board synced.')).toBeVisible({ timeout: 10_000 });
  expect(errors).toEqual([]);
});

test('rule editor: highlighting, live validation, suggestion, autocomplete', async ({ page }) => {
  await open(page, '/groups/new');
  await page.getByRole('textbox', { name: /Name/ }).fill('Project Teams East');
  const editor = page.locator('.cm-content');
  await editor.click();
  await page.keyboard.type('user.extensionAtribute3 -eq "KOM"');
  const alert = page.getByRole('alert');
  await expect(alert).toContainText('Line 1, position 1:');
  await expect(alert).toContainText('unknown property user.extensionAtribute3');
  await expect(page.locator('.cm-lintRange-error')).toHaveCount(1);
  await expect(page.getByRole('button', { name: 'Create', exact: true })).toBeDisabled();
  await alert.getByRole('button', { name: 'extensionAttribute3' }).click();
  await expect(page.getByText('Rule is valid · 1 condition')).toBeVisible();
  await expect(page.locator('.cm-rule-property').first()).toHaveText('user.extensionAttribute3');
  await expect(page.locator('.cm-rule-string')).toHaveText('"KOM"');

  await editor.click();
  await page.keyboard.press('Control+End');
  await page.keyboard.type(' -and (user.dep');
  await expect(page.getByRole('listbox')).toContainText('department');
  await page.keyboard.press('Enter');
  await page.keyboard.type(' ');
  await page.keyboard.press('Control+Space');
  await expect(page.getByRole('listbox')).toContainText('-startsWith');
});

test('new group: preview, create, then the group page', async ({ page }) => {
  await open(page, '/groups/new');
  await page.getByRole('textbox', { name: /Name/ }).fill('Projects East');
  await page.locator('.cm-content').click();
  await page.keyboard.type('user.department -eq "Projects East"');
  await expect(page.getByText('Rule is valid · 1 condition')).toBeVisible();
  await expect(page.getByText('DG-Projects East')).toBeVisible();
  await page.getByRole('button', { name: 'Run preview' }).click();
  await expect(page.getByTestId('preview-result')).toContainText('users would be members');
  await page.getByRole('button', { name: 'Create', exact: true }).click();
  await expect(toast(page, 'Projects East created.')).toBeVisible();
  await expect(page).toHaveURL(/\/groups\/def-/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Projects East');
  await expect(page.getByText('The engine has not run this definition yet.')).toBeVisible();
});

test('adopt: picker shows why groups are disabled; a dynamic group fills the rule', async ({ page }) => {
  await open(page, '/groups/new');
  await page.getByRole('button', { name: 'Adopt existing' }).click();
  await page.getByRole('combobox', { name: 'Find the group to adopt' }).fill('board');
  const list = page.getByRole('listbox', { name: 'Find the group to adopt' });
  await expect(list.getByRole('option', { name: /SG-Board-OnPrem/ })).toHaveAttribute('aria-disabled', 'true');
  await expect(list.getByRole('option', { name: /SG-Board-OnPrem/ })).toContainText('Synced from on-prem AD');
  await expect(list.getByRole('option', { name: /SG-Board-Admins/ })).toContainText('Role-assignable');
  await page.getByRole('combobox', { name: 'Find the group to adopt' }).fill('dyn');
  await list.getByRole('option', { name: /DYN-Sales-Europe/ }).click();
  await expect(page.locator('.cm-content')).toContainText('user.department -eq "Fundraising"');
  await expect(page.getByRole('textbox', { name: /Name/ })).toHaveValue('DYN-Sales-Europe');
  await page.getByRole('switch', { name: 'Rename on adopt' }).click();
  await expect(page.getByText('DG-DYN-Sales-Europe')).toBeVisible();
});

test('adoption waiting for approval: dry run result and approve takeover', async ({ page }) => {
  await open(page, `/groups/${BOARD}?mockEngineMs=300`);
  await expect(page.getByRole('heading', { name: 'Dry run result' })).toBeVisible();
  await expect(page.getByText('Would be removed')).toBeVisible();
  await page.getByRole('button', { name: 'Approve takeover' }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByRole('heading', { name: 'Approve the takeover' })).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Approve takeover' })).toBeDisabled();
  await dialog.getByRole('checkbox').check();
  await dialog.getByRole('button', { name: 'Approve takeover' }).click();
  await expect(toast(page, 'Approved once. The next run writes these changes.')).toBeVisible();
});

test('blocked group: review from the list opens the one-time approval', async ({ page }) => {
  await open(page, '/');
  await page.getByRole('button', { name: 'Review Intune – Field Laptops' }).click();
  await expect(page).toHaveURL(new RegExp(`/groups/${INTUNE}`));
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByRole('heading', { name: 'Approve this change once' })).toBeVisible();
  await expect(dialog).toContainText('Users to add (first 5 of 84)');
  await dialog.getByRole('button', { name: 'Show all 84 users' }).click();
  await expect(dialog.getByRole('listitem')).toHaveCount(84);
  await dialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(dialog).toBeHidden();
});

test('conflict: someone else saved first', async ({ page }) => {
  await open(page, `/groups/${EOP}`);
  await expect(page.getByText('Rule is valid · 3 conditions · references 1 group')).toBeVisible();
  await expect(page.getByText('managed by')).toBeVisible();
  await page.evaluate((id) => window.__rdgMock?.touch(id, { frequencyMinutes: 30 }), EOP);
  await page.getByRole('switch', { name: 'Include guests' }).click();
  await page.getByRole('button', { name: 'Save' }).click();
  const dialog = page.getByRole('alertdialog');
  await expect(dialog).toContainText('Someone else changed this group');
  await expect(dialog).toContainText('Lea K. saved EOP Strict – Management');
  await dialog.getByRole('button', { name: 'Back to my edits' }).click();
  await expect(page.getByRole('switch', { name: 'Include guests' })).toBeChecked();
  await page.getByRole('button', { name: 'Save' }).click();
  await page.getByRole('alertdialog').getByRole('button', { name: 'Reload latest version' }).click();
  await expect(page.getByRole('switch', { name: 'Include guests' })).not.toBeChecked();
  await expect(page.getByRole('combobox', { name: 'Frequency' })).toHaveValue('30');
});

test('unsaved changes ask before leaving', async ({ page }) => {
  await open(page, `/groups/${EOP}`);
  await page.getByRole('switch', { name: 'Dry run' }).click();
  await page.getByRole('navigation').getByRole('link', { name: 'Audit' }).click();
  await expect(page.getByText('You have unsaved changes. Leave this page anyway?')).toBeVisible();
  await page.getByRole('button', { name: 'Leave page' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Audit');
});

test('delete: references read the group live; confirm by name', async ({ page }) => {
  await open(page, `/groups/${SVC}`);
  await page.getByRole('button', { name: 'Delete' }).click();
  const dialog = page.getByRole('alertdialog');
  await expect(dialog).toContainText('The group stays.');
  await expect(dialog).toContainText('All Staff Zürich');
  await expect(dialog).toContainText('they read the members of this group from Entra ID directly');
  const confirm = dialog.getByRole('button', { name: 'Delete definition' });
  await expect(confirm).toBeDisabled();
  await dialog.getByRole('textbox').fill('Service Accounts');
  await confirm.click();
  await expect(page).toHaveURL(/\/$/);
  await expect(toast(page, 'Service Accounts deleted. The group stays as it is.')).toBeVisible();
  await expect(page.getByRole('table').getByRole('row')).toHaveCount(10);
});

test('activity: run details, likely cause and approval', async ({ page }) => {
  await open(page, '/activity');
  await page
    .getByRole('row', { name: /Intune – Field Laptops/ })
    .first()
    .click();
  const panel = page.getByRole('complementary', { name: 'Run details' });
  await expect(panel).toContainText('Blocked by change limit.');
  await expect(panel).toContainText('the limit is 50 %');
  await expect(panel).toContainText('Rule changed yesterday');
  await expect(panel.getByRole('button', { name: 'Approve once' })).toBeVisible();
  await panel.getByRole('button', { name: 'Close details' }).click();
  await expect(panel).toBeHidden();
  await page.getByRole('combobox', { name: 'Result' }).selectOption('SkippedTick');
  await expect(page.getByRole('table').getByRole('row')).toHaveCount(2);
});

test('audit: filters by group and shows rule changes old → new', async ({ page }) => {
  await open(page, '/audit');
  await expect(page.getByRole('row', { name: /Changed rule/ })).toContainText('user.extensionAttribute5 -startsWith "FIELD"');
  await page.getByRole('combobox', { name: 'Period' }).selectOption('all');
  await expect(page.getByRole('row', { name: /Created group/ })).toBeVisible();
  await page.getByRole('combobox', { name: 'Group' }).selectOption({ label: 'Board Members' });
  await expect(page.getByRole('table').getByRole('row')).toHaveCount(2);
});

test('settings: pause, banner, resume', async ({ page }) => {
  await open(page, '/settings');
  await page.getByRole('switch', { name: 'Pause all syncing' }).click();
  await page.getByRole('button', { name: 'Save settings' }).click();
  await expect(page.getByRole('status').filter({ hasText: 'Syncing is paused' })).toBeVisible();
  await page.getByRole('button', { name: 'Resume syncing' }).click();
  await expect(page.getByText('Syncing is paused')).toBeHidden();
  await page.getByRole('spinbutton', { name: 'Minutes (3 to 1440)' }).fill('2');
  await page.getByRole('button', { name: 'Add option' }).click();
  await expect(page.getByText('Enter whole minutes from 3 to 1440')).toBeVisible();
});

test('reader: read-only group, settings disabled, no new group', async ({ page }) => {
  await open(page, `/groups/${EOP}?mockRole=reader`);
  await expect(page.getByText('You have read access. Ask an admin to change this group.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Save' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Run preview' }).click();
  await expect(page.getByTestId('preview-result')).toBeVisible();
  await page.getByRole('navigation').getByRole('link', { name: 'Settings' }).click();
  await expect(page.getByRole('switch', { name: 'Pause all syncing' })).toBeDisabled();
  await page.getByRole('navigation').getByRole('link', { name: 'Groups' }).click();
  await expect(page.getByRole('button', { name: 'New group' })).toHaveCount(0);
});

test('read-only installation shows the banner and blocks approvals', async ({ page }) => {
  await open(page, `/groups/${INTUNE}?mockReadOnly=1`);
  await expect(page.getByText('Read-only installation')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Approve once' })).toHaveCount(0);
});

test('empty state, access denied and paused banner', async ({ browser }) => {
  const empty = await browser.newPage();
  await empty.goto('/?mockEmpty=1');
  await expect(empty.getByRole('heading', { name: 'No groups yet' })).toBeVisible();
  await empty.getByRole('button', { name: 'New group' }).click();
  await expect(empty).toHaveURL(/\/groups\/new$/);

  const denied = await browser.newPage();
  await denied.goto('/?mockRole=none');
  await expect(denied.getByRole('heading', { name: "You don't have access to Dynamic Groups" })).toBeVisible();
  await expect(denied.getByText('marco.rossi@contoso.org')).toBeVisible();

  const paused = await browser.newPage();
  await paused.goto('/?mockPaused=1');
  await expect(paused.getByText('Syncing is paused')).toBeVisible();
});

test('error page shows the correlation ID and recovers', async ({ page }) => {
  await open(page, '/activity');
  await expect(page.getByRole('table')).toBeVisible();
  await page.evaluate(() => window.__rdgMock?.failNext('/api/audit', 500, 2));
  await page.getByRole('navigation').getByRole('link', { name: 'Audit' }).click();
  await expect(page.getByRole('heading', { name: 'Something went wrong' })).toBeVisible();
  await expect(page.getByTestId('correlation-id')).toHaveText(/^4f2a9c1e-/);
  await page.getByRole('button', { name: 'Try again' }).click();
  await expect(page.getByRole('table')).toBeVisible();
});
