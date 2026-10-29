import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { FluentProvider, webLightTheme } from '@fluentui/react-components';
import { RuleEditor, type ValidationState } from './RuleEditor';

let calls = 0;
const server = setupServer(
  http.post('*/api/rules/validate', async ({ request }) => {
    calls += 1;
    const { rule } = (await request.json()) as { rule: string };
    if (rule.includes('Atribute')) {
      return HttpResponse.json({
        valid: false,
        referencedGroupIds: [],
        errors: [
          {
            position: 0,
            line: 1,
            column: 1,
            length: 23,
            message: 'unknown property user.extensionAtribute3; did you mean extensionAttribute3?',
            suggestion: 'extensionAttribute3',
          },
        ],
      });
    }
    return HttpResponse.json({ valid: true, errors: [], referencedGroupIds: [] });
  }),
);
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterAll(() => server.close());
beforeEach(() => {
  calls = 0;
});

const wrap = (ui: React.ReactNode) => render(<FluentProvider theme={webLightTheme}>{ui}</FluentProvider>);

describe('RuleEditor', () => {
  it('does not check an empty rule', async () => {
    const states: ValidationState[] = [];
    wrap(<RuleEditor value="" onChange={() => undefined} onValidation={(s) => states.push(s)} />);
    await new Promise((resolve) => setTimeout(resolve, 600));
    expect(calls).toBe(0);
    expect(states.at(-1)).toEqual({ state: 'idle' });
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('checks 400 ms after the last change, shows errors and applies the suggestion', async () => {
    const onChange = vi.fn();
    const states: ValidationState[] = [];
    wrap(<RuleEditor value='user.extensionAtribute3 -eq "KOM"' onChange={onChange} onValidation={(s) => states.push(s)} />);
    expect(screen.getByRole('status')).toHaveTextContent('Checking…');
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(calls).toBe(0);
    const alert = await screen.findByRole('alert');
    expect(calls).toBe(1);
    expect(alert).toHaveTextContent('Line 1, position 1: unknown property user.extensionAtribute3. Did you mean extensionAttribute3?');
    expect(states.at(-1)?.state).toBe('invalid');
    await userEvent.click(screen.getByRole('button', { name: 'extensionAttribute3' }));
    expect(onChange).toHaveBeenCalledWith('user.extensionAttribute3 -eq "KOM"');
  });

  it('reports a valid rule with its condition count', async () => {
    wrap(<RuleEditor value='(user.city -eq "Bern") -and (user.department -eq "IT")' onChange={() => undefined} />);
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Rule is valid · 2 conditions'));
  });

  it('is read-only without validation in the reader view', async () => {
    wrap(<RuleEditor value='user.city -eq "Bern"' readOnly />);
    await new Promise((resolve) => setTimeout(resolve, 600));
    expect(calls).toBe(0);
    expect(document.querySelector('.cm-content')?.getAttribute('contenteditable')).toBe('false');
    expect(document.querySelector('.cm-rule-property')?.textContent).toBe('user.city');
  });
});
