// A small rule parser and evaluator for the mock API only. It covers the common shapes
// (conditions, -and/-or/-not, parentheses, lists, memberOf -any) so the editor and the
// preview behave plausibly without a tenant. The real check is the engine's Test-DgRule.
import { findProperty, properties, tokenize, type Token } from '../rules/language';
import type { RuleError } from '../api/types';

export interface MockUser {
  id: string;
  displayName: string;
  userPrincipalName: string;
  mail: string | null;
  accountEnabled: boolean;
  userType: 'Member' | 'Guest';
  memberOf: string[];
  [field: string]: unknown;
}

type Node =
  | { kind: 'and' | 'or'; left: Node; right: Node }
  | { kind: 'not'; inner: Node }
  | { kind: 'condition'; property: string; operator: string; values: string[]; inner?: Node };

class RuleSyntaxError extends Error {
  constructor(
    readonly position: number,
    readonly length: number,
    message: string,
    readonly suggestion?: string,
  ) {
    super(message);
  }
}

function editDistance(a: string, b: string): number {
  const row = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i += 1) {
    let previous = row[0] ?? 0;
    row[0] = i;
    for (let j = 1; j <= b.length; j += 1) {
      const current = row[j] ?? 0;
      row[j] = Math.min((row[j] ?? 0) + 1, (row[j - 1] ?? 0) + 1, previous + (a[i - 1] === b[j - 1] ? 0 : 1));
      previous = current;
    }
  }
  return row[b.length] ?? 0;
}

function suggest(name: string): string | undefined {
  let best: string | undefined;
  let bestDistance = 3;
  for (const p of properties) {
    const d = editDistance(name.toLowerCase(), p.name.toLowerCase());
    if (d < bestDistance) {
      best = p.name;
      bestDistance = d;
    }
  }
  return best;
}

const op = (token: Token | undefined) => (token ? token.text.replace(/^[-–—−]/, '').toLowerCase() : '');

class Parser {
  private i = 0;
  readonly groupIds: string[] = [];

  constructor(
    private readonly tokens: Token[],
    private readonly length: number,
  ) {}

  parse(): Node {
    if (this.tokens.length === 0) throw new RuleSyntaxError(0, 0, 'the rule is empty');
    const node = this.or();
    const rest = this.tokens[this.i];
    if (rest) throw new RuleSyntaxError(rest.from, rest.to - rest.from, `unexpected ${rest.text}; expected -and or -or`);
    return node;
  }

  private peek() {
    return this.tokens[this.i];
  }

  private or(): Node {
    let left = this.and();
    while (this.peek()?.kind === 'logical' && op(this.peek()) === 'or') {
      this.i += 1;
      left = { kind: 'or', left, right: this.and() };
    }
    return left;
  }

  private and(): Node {
    let left = this.unary();
    while (this.peek()?.kind === 'logical' && op(this.peek()) === 'and') {
      this.i += 1;
      left = { kind: 'and', left, right: this.unary() };
    }
    return left;
  }

  private unary(): Node {
    const token = this.peek();
    if (token?.kind === 'logical' && op(token) === 'not') {
      this.i += 1;
      return { kind: 'not', inner: this.unary() };
    }
    return this.primary();
  }

  private primary(): Node {
    const token = this.peek();
    if (!token) throw new RuleSyntaxError(this.length, 0, 'the rule ends too early; expected a condition');
    if (token.text === '(') {
      this.i += 1;
      const inner = this.or();
      const close = this.peek();
      if (close?.text !== ')') throw new RuleSyntaxError(token.from, 1, '( is never closed with )');
      this.i += 1;
      return inner;
    }
    return this.condition();
  }

  private condition(inner = false): Node {
    const token = this.peek();
    if (!token) throw new RuleSyntaxError(this.length, 0, 'expected a condition');
    if (token.kind !== 'property') {
      throw new RuleSyntaxError(token.from, token.to - token.from, `expected a property such as user.department, found ${token.text}`);
    }
    const name = token.text.replace(/^(user|group|assignedPlan)\./i, '');
    if (!inner && /^user\./i.test(token.text) && !findProperty(name)) {
      const best = suggest(name);
      throw new RuleSyntaxError(
        token.from,
        token.to - token.from,
        `unknown property ${token.text}${best ? `; did you mean ${best}?` : ''}`,
        best,
      );
    }
    this.i += 1;
    const operator = this.peek();
    if (!operator || operator.kind !== 'operator') {
      const at = operator ?? { from: this.length, to: this.length, text: '' };
      throw new RuleSyntaxError(at.from, at.to - at.from, `expected an operator after ${token.text}`);
    }
    this.i += 1;
    const name2 = op(operator);
    if (name2 === 'any' || name2 === 'all') {
      const open = this.peek();
      if (open?.text !== '(') throw new RuleSyntaxError(operator.to, 0, `expected ( after ${operator.text}`);
      this.i += 1;
      const innerNode = this.condition(true);
      if (this.peek()?.text !== ')') throw new RuleSyntaxError(open.from, 1, '( is never closed with )');
      this.i += 1;
      return { kind: 'condition', property: name.toLowerCase(), operator: name2, values: [], inner: innerNode };
    }
    const values = this.values(operator);
    if (/objectid/i.test(name)) this.groupIds.push(...values);
    return { kind: 'condition', property: name.toLowerCase(), operator: name2, values };
  }

  private values(operator: Token): string[] {
    const token = this.peek();
    // Like the engine: the error points at what stands where the value should be.
    const missing = () => {
      const at = this.peek();
      return new RuleSyntaxError(at ? at.from : this.length, at ? at.to - at.from : 0, `expected a value after ${operator.text}`);
    };
    if (!token || token.kind === 'logical' || token.text === ')' || token.kind === 'operator') throw missing();
    if (token.text === '[') {
      this.i += 1;
      const list: string[] = [];
      while (this.peek() && this.peek()?.text !== ']') {
        const item = this.peek();
        if (item?.text === ',') {
          this.i += 1;
          continue;
        }
        if (!item || (item.kind !== 'string' && item.kind !== 'value')) throw missing();
        list.push(unquote(item.text));
        this.i += 1;
      }
      if (this.peek()?.text !== ']') throw new RuleSyntaxError(token.from, 1, '[ is never closed with ]');
      this.i += 1;
      return list;
    }
    if (token.kind !== 'string' && token.kind !== 'value') throw missing();
    this.i += 1;
    return [unquote(token.text)];
  }
}

function unquote(text: string): string {
  if (/^["']/.test(text)) return text.slice(1, -1).replace(/`"/g, '"').replace(/''/g, "'");
  return text;
}

function lineColumn(rule: string, position: number) {
  const before = rule.slice(0, position);
  const lines = before.split('\n');
  return { line: lines.length, column: (lines[lines.length - 1]?.length ?? 0) + 1 };
}

export interface MockCheck {
  valid: boolean;
  errors: RuleError[];
  groupIds: string[];
  node?: Node;
}

export function checkRule(rule: string): MockCheck {
  const parser = new Parser(tokenize(rule), rule.length);
  try {
    const node = parser.parse();
    return { valid: true, errors: [], groupIds: [...new Set(parser.groupIds.map((g) => g.toLowerCase()))], node };
  } catch (error) {
    if (!(error instanceof RuleSyntaxError)) throw error;
    const { line, column } = lineColumn(rule, error.position);
    const ruleError: RuleError = { position: error.position, line, column, length: error.length, message: error.message };
    if (error.suggestion) ruleError.suggestion = error.suggestion;
    return { valid: false, errors: [ruleError], groupIds: [] };
  }
}

function fieldValue(user: MockUser, property: string): unknown {
  const key = Object.keys(user).find((k) => k.toLowerCase() === property);
  return key ? user[key] : undefined;
}

function test(node: Node, user: MockUser): boolean {
  switch (node.kind) {
    case 'and':
      return test(node.left, user) && test(node.right, user);
    case 'or':
      return test(node.left, user) || test(node.right, user);
    case 'not':
      return !test(node.inner, user);
    default:
      break;
  }
  if (node.inner) {
    const items = node.property === 'memberof' ? user.memberOf : ((fieldValue(user, node.property) as unknown[]) ?? []);
    const check = (item: unknown) => {
      const inner = node.inner as Node & { kind: 'condition' };
      return compare(String(item), inner.operator, inner.values);
    };
    return node.operator === 'all' ? items.length > 0 && items.every(check) : items.some(check);
  }
  const raw = fieldValue(user, node.property);
  if (Array.isArray(raw)) return raw.some((item) => compare(String(item), node.operator, node.values));
  return compare(raw === undefined || raw === null ? null : String(raw), node.operator, node.values);
}

function compare(actual: string | null, operator: string, values: string[]): boolean {
  const a = (actual ?? '').toLowerCase();
  const list = values.map((v) => v.toLowerCase());
  const first = list[0] ?? '';
  switch (operator) {
    case 'eq':
      return first === 'null' ? actual === null : a === first;
    case 'ne':
      return first === 'null' ? actual !== null : a !== first;
    case 'startswith':
      return actual !== null && a.startsWith(first);
    case 'notstartswith':
      return !a.startsWith(first);
    case 'endswith':
      return actual !== null && a.endsWith(first);
    case 'notendswith':
      return !a.endsWith(first);
    case 'contains':
      return actual !== null && a.includes(first);
    case 'notcontains':
      return !a.includes(first);
    case 'match':
      return actual !== null && safeRegex(values[0] ?? '').test(actual);
    case 'notmatch':
      return !safeRegex(values[0] ?? '').test(actual ?? '');
    case 'in':
      return list.includes(a);
    case 'notin':
      return !list.includes(a);
    case 'le':
      return actual !== null && a <= first;
    case 'ge':
      return actual !== null && a >= first;
    default:
      return false;
  }
}

function safeRegex(pattern: string): RegExp {
  try {
    return new RegExp(pattern, 'i');
  } catch {
    return /$^/;
  }
}

export function evaluate(rule: string, users: MockUser[]): MockUser[] {
  const check = checkRule(rule);
  if (!check.valid || !check.node) return [];
  const node = check.node;
  return users.filter((user) => test(node, user));
}
