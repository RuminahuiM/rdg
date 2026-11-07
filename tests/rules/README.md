# Rule conformance suite

Rule behaviour as data. Each JSON file holds a list of cases on one topic; `tools/Invoke-RuleConformance.ps1` runs them (no Pester needed), and `tests/DgEngine/Rules/Conformance.Tests.ps1` reports each case as a Pester test in CI.

```json
{
  "title": "Rule syntax",
  "cases": [
    { "id": "cmp-eq", "rule": "user.department -eq \"Sales\"", "valid": true,
      "tree": "(eq user.department \"Sales\")" },
    { "id": "err-missing-value", "rule": "(user.department -eq )", "valid": false,
      "error": { "position": 21, "message": "expected a value after -eq" } }
  ]
}
```

- `tree` is the syntax tree as `Format-DgRuleAst` renders it: operators lower-case canonical, lists in `[ ]`, dates as `@2020-06-10T18:13:20Z`, `system.now -plus P1D` as `now+P1D`.
- `error.position` is the 0-based character offset; `error.message` must be contained in the actual message.
- `note` (optional) says why a case exists.
- Evaluation files also hold `users` (keyed by a short name, with Graph field names), `groups` (group ID to user keys, for memberOf) and a fixed `now`; a case then lists the users the rule must `matches`. This is the raw rule result: disabled accounts and guests are filtered afterwards.

| File | Covers |
|---|---|
| `syntax.json` | Grammar: every operator, values, escaping, precedence, collections, Direct Reports, and parse errors |
| `validation.json` | Unknown properties, operator and value types, regexes, and the shapes -any/-all and memberOf allow |
| `evaluation.json` | Who each rule matches among five invented users: every operator, null handling, collections, memberOf, Direct Reports |

Real-world rules go in with their structure but invented values; no data from a real tenant.
