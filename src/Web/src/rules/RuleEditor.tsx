// The rule editor: CodeMirror 6 with RDG highlighting, autocomplete and live validation
// (POST /rules/validate 400 ms after typing stops; errors are underlined at their position).
import { useEffect, useMemo, useRef, useState } from 'react';
import CodeMirror, { type ReactCodeMirrorRef } from '@uiw/react-codemirror';
import { EditorView, Decoration, ViewPlugin, type DecorationSet, type ViewUpdate, keymap } from '@codemirror/view';
import { EditorState, RangeSetBuilder, type Extension } from '@codemirror/state';
import {
  autocompletion,
  type Completion,
  type CompletionContext as CmContext,
  type CompletionResult,
  completionKeymap,
} from '@codemirror/autocomplete';
import { linter, setDiagnostics, type Diagnostic, lintGutter } from '@codemirror/lint';
import { makeStyles, tokens as fluent, Link, Spinner, Text } from '@fluentui/react-components';
import type { GroupType, RuleError, RuleValidationResult } from '../api/types';
import { validateRule } from '../api/hooks';
import { t } from '../strings/en';
import { completionContext, countConditions, operatorsByType, properties, tokenize, type TokenKind } from './language';
import { useColorScheme } from '../theme';

export type ValidationState =
  | { state: 'idle' }
  | { state: 'checking' }
  | { state: 'valid'; result: RuleValidationResult }
  | { state: 'invalid'; result: RuleValidationResult }
  | { state: 'failed' };

const tokenClass: Partial<Record<TokenKind, string>> = {
  property: 'cm-rule-property',
  operator: 'cm-rule-operator',
  logical: 'cm-rule-operator',
  string: 'cm-rule-string',
};

function buildDecorations(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const token of tokenize(view.state.doc.toString())) {
    const cls = tokenClass[token.kind];
    if (cls) builder.add(token.from, token.to, Decoration.mark({ class: cls }));
  }
  return builder.finish();
}

/** Colours the rule with the same tokenizer that counts conditions. */
export const ruleHighlighting = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = buildDecorations(view);
    }
    update(update: ViewUpdate) {
      if (update.docChanged) this.decorations = buildDecorations(update.view);
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

/** Completion options for a position; exported for tests. */
export function ruleCompletions(rule: string, pos: number, explicit: boolean): { from: number; options: Completion[] } | null {
  const context = completionContext(rule, pos);
  switch (context.kind) {
    case 'property':
      return {
        from: context.from,
        options: [
          // Natural order (extensionAttribute2 before extensionAttribute10); boost keeps it.
          ...[...properties]
            .sort((a, b) => a.name.localeCompare(b.name, 'en', { numeric: true }))
            .map((p, index, list) => ({
              label: p.name,
              detail: t.editor.typeNames[p.type],
              type: 'property',
              boost: 99 - Math.round((index * 198) / list.length),
            })),
          { label: 'extension_', detail: t.editor.typeNames.Extension, type: 'property', apply: 'extension_', boost: -99 },
        ],
      };
    case 'operator': {
      const ops = operatorsByType[context.type ?? 'String'];
      return { from: context.from, options: ops.map((op) => ({ label: `-${op}`, detail: t.editor.operatorInfo, type: 'keyword' })) };
    }
    case 'logical':
      return { from: context.from, options: ['-and', '-or'].map((label) => ({ label, detail: t.editor.keywordInfo, type: 'keyword' })) };
    case 'start':
      if (!explicit && pos > 0 && !/\(\s*$|^\s*$/.test(rule.slice(0, pos))) return null;
      return {
        from: context.from,
        options: [
          { label: 'user.', type: 'property', detail: t.editor.keywordInfo },
          { label: '-not', type: 'keyword', detail: t.editor.keywordInfo },
        ],
      };
    default:
      return null;
  }
}

function completionSource(context: CmContext): CompletionResult | null {
  const rule = context.state.doc.toString();
  const result = ruleCompletions(rule, context.pos, context.explicit);
  if (!result) return null;
  // Typing more letters filters the list instead of asking again.
  return { from: result.from, options: result.options, validFor: /^[-\w]*$/ };
}

/** Turns API errors into CodeMirror diagnostics, clipped to the document. */
export function toDiagnostics(errors: RuleError[], length: number): Diagnostic[] {
  return errors.map((error) => {
    const from = Math.min(Math.max(error.position, 0), length);
    const to = Math.min(from + Math.max(error.length, 1), length);
    return { from, to: Math.max(to, from), severity: 'error', message: error.message };
  });
}

const useStyles = makeStyles({
  frame: {
    border: `1px solid ${fluent.colorNeutralStroke1}`,
    borderBottomColor: fluent.colorNeutralStrokeAccessible,
    borderRadius: fluent.borderRadiusMedium,
    overflow: 'hidden',
    backgroundColor: fluent.colorNeutralBackground1,
    ':focus-within': { borderBottomColor: fluent.colorCompoundBrandStroke, boxShadow: `inset 0 -1px 0 ${fluent.colorCompoundBrandStroke}` },
  },
  frameInvalid: { borderBottomColor: fluent.colorPaletteRedBorder2 },
  status: { display: 'flex', alignItems: 'center', gap: '8px', marginTop: '8px', fontSize: fluent.fontSizeBase200 },
  valid: { color: fluent.colorPaletteGreenForeground1 },
  errors: {
    marginTop: '8px',
    padding: '8px 12px',
    borderRadius: fluent.borderRadiusMedium,
    backgroundColor: fluent.colorPaletteRedBackground1,
    color: fluent.colorPaletteRedForeground1,
    fontSize: fluent.fontSizeBase200,
    '& ul': { margin: 0, paddingLeft: '0', listStyleType: 'none' },
    '& li + li': { marginTop: '4px' },
  },
  muted: { color: fluent.colorNeutralForeground3 },
});

function editorTheme(dark: boolean): Extension {
  const colors = dark
    ? { property: '#82C7FF', operator: '#D59DFF', string: '#6CCB5F', gutter: '#adadad' }
    : { property: '#0F548C', operator: '#7A2E8E', string: '#0E700E', gutter: '#707070' };
  return EditorView.theme(
    {
      '&': { fontSize: '13px', backgroundColor: 'transparent' },
      '.cm-content': { fontFamily: '"Cascadia Code", Consolas, ui-monospace, monospace', lineHeight: '22px', padding: '6px 0' },
      '.cm-gutters': { backgroundColor: 'transparent', border: 'none', color: colors.gutter },
      '.cm-rule-property': { color: colors.property },
      '.cm-rule-operator': { color: colors.operator },
      '.cm-rule-string': { color: colors.string },
      '.cm-lintRange-error': {
        backgroundImage: 'none',
        textDecoration: 'underline wavy #C50F1F',
        textUnderlineOffset: '3px',
      },
      '&.cm-focused': { outline: 'none' },
      '.cm-tooltip-autocomplete ul li[aria-selected]': { backgroundColor: dark ? '#2B3F55' : '#EBF3FC', color: 'inherit' },
      '.cm-completionDetail': { marginLeft: '12px', fontStyle: 'normal', opacity: 0.7 },
    },
    { dark },
  );
}

export interface RuleEditorProps {
  value: string;
  onChange?: (value: string) => void;
  groupType?: GroupType;
  readOnly?: boolean;
  onValidation?: (state: ValidationState) => void;
  /** id of the label element. */
  labelledBy?: string;
  minHeight?: string;
}

export function RuleEditor({
  value,
  onChange,
  groupType,
  readOnly = false,
  onValidation,
  labelledBy,
  minHeight = '120px',
}: RuleEditorProps) {
  const styles = useStyles();
  const scheme = useColorScheme();
  const ref = useRef<ReactCodeMirrorRef>(null);
  const [validation, setValidation] = useState<ValidationState>({ state: 'idle' });
  const report = useRef(onValidation);
  report.current = onValidation;

  const extensions = useMemo(
    () => [
      ruleHighlighting,
      editorTheme(scheme === 'dark'),
      EditorView.lineWrapping,
      EditorView.contentAttributes.of({ 'aria-labelledby': labelledBy ?? '', 'aria-multiline': 'true', spellcheck: 'false' }),
      ...(readOnly
        ? [EditorState.readOnly.of(true), EditorView.editable.of(false)]
        : [
            autocompletion({ override: [completionSource], icons: false }),
            keymap.of(completionKeymap),
            // The lint state must exist before the first setDiagnostics, or the first underline is lost.
            linter(null),
            lintGutter(),
          ]),
    ],
    [scheme, readOnly, labelledBy],
  );

  // Live validation, 400 ms after the last change.
  useEffect(() => {
    if (readOnly) return undefined;
    if (!value.trim()) {
      const idle: ValidationState = { state: 'idle' };
      setValidation(idle);
      report.current?.(idle);
      const view = ref.current?.view;
      if (view) view.dispatch(setDiagnostics(view.state, []));
      return undefined;
    }
    const controller = new AbortController();
    const checking: ValidationState = { state: 'checking' };
    setValidation(checking);
    report.current?.(checking);
    const timer = window.setTimeout(() => {
      validateRule(value, groupType, controller.signal)
        .then((result) => {
          const errors = [...result.errors];
          const next: ValidationState =
            result.valid && !result.unknownGroupIds?.length
              ? { state: 'valid', result }
              : { state: 'invalid', result: { ...result, errors } };
          setValidation(next);
          report.current?.(next);
          const view = ref.current?.view;
          if (view && view.state.doc.toString() === value) {
            view.dispatch(setDiagnostics(view.state, toDiagnostics(errors, value.length)));
          }
        })
        .catch((error: unknown) => {
          if (error instanceof DOMException && error.name === 'AbortError') return;
          const failed: ValidationState = { state: 'failed' };
          setValidation(failed);
          report.current?.(failed);
        });
    }, 400);
    return () => {
      controller.abort();
      window.clearTimeout(timer);
    };
  }, [value, groupType, readOnly]);

  const applySuggestion = (error: RuleError) => {
    if (!error.suggestion || !onChange) return;
    const original = value.slice(error.position, error.position + error.length);
    // The engine underlines "user.extensionAtribute3"; keep the "user." prefix if it was part of it.
    const replacement = /^user\./i.test(original) && !/^user\./i.test(error.suggestion) ? `user.${error.suggestion}` : error.suggestion;
    onChange(value.slice(0, error.position) + replacement + value.slice(error.position + error.length));
  };

  const invalid = validation.state === 'invalid';
  return (
    <div>
      <div className={`${styles.frame} ${invalid ? styles.frameInvalid : ''}`} data-testid="rule-editor">
        <CodeMirror
          ref={ref}
          value={value}
          onChange={(text) => onChange?.(text)}
          extensions={extensions}
          theme={scheme === 'dark' ? 'dark' : 'light'}
          editable={!readOnly}
          readOnly={readOnly}
          minHeight={readOnly ? undefined : minHeight}
          basicSetup={{
            lineNumbers: true,
            foldGutter: false,
            highlightActiveLine: false,
            highlightActiveLineGutter: false,
            autocompletion: false,
            bracketMatching: true,
            closeBrackets: !readOnly,
            searchKeymap: false,
            highlightSelectionMatches: false,
            syntaxHighlighting: false,
            lintKeymap: true,
          }}
        />
      </div>
      {!readOnly && <ValidationStatus validation={validation} onSuggestion={applySuggestion} rule={value} />}
    </div>
  );
}

/** The engine appends "; did you mean X?" to the message; the link replaces that text. */
export function withoutHint(error: RuleError): string {
  return error.suggestion ? error.message.replace(/;\s*did you mean [^?]*\?\s*$/i, '') : error.message;
}

function ValidationStatus({
  validation: v,
  onSuggestion,
  rule,
}: {
  validation: ValidationState;
  onSuggestion: (e: RuleError) => void;
  rule: string;
}) {
  const styles = useStyles();
  if (v.state === 'checking') {
    return (
      <div className={styles.status} role="status">
        <Spinner size="extra-tiny" />
        <Text className={styles.muted}>{t.editor.checking}</Text>
      </div>
    );
  }
  if (v.state === 'failed') {
    return (
      <div className={styles.status} role="status">
        <Text className={styles.muted}>{t.editor.checkFailed}</Text>
      </div>
    );
  }
  if (v.state === 'valid') {
    return (
      <div className={styles.status} role="status">
        <Text className={styles.valid}>{t.editor.valid(countConditions(rule), v.result.referencedGroupIds.length)}</Text>
      </div>
    );
  }
  if (v.state === 'invalid') {
    const unknown = v.result.unknownGroupIds ?? [];
    return (
      <div className={styles.errors} role="alert">
        <ul>
          {v.result.errors.map((error) => (
            <li key={`${error.position}-${error.message}`}>
              <strong>{t.editor.errorAt(error.line, error.column)}</strong> {withoutHint(error)}
              {error.suggestion && (
                <>
                  {`. ${t.editor.didYouMean} `}
                  <Link as="button" inline onClick={() => onSuggestion(error)}>
                    {error.suggestion}
                  </Link>
                  ?
                </>
              )}
            </li>
          ))}
          {unknown.length > 0 && <li>{t.editor.unknownGroups(unknown.length)}</li>}
        </ul>
      </div>
    );
  }
  return null;
}
