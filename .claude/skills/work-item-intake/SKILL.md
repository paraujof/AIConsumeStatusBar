---
name: work-item-intake
description: Schema of .agents/runs/<id>/work-item.md and how to build it from a Jira ticket, a Datadog error, a Snyk vulnerability or a free-text prompt — source reading, type classification, severity mapping and scope owner. Use when normalizing any incoming work item.
---

# Work item intake

Every run of `/work` starts by turning the raw input into one normalized file:
`.agents/runs/<id>/work-item.md`. All later agents read ONLY this file to know what
the work is about; nobody but the `intake` agent ever reads the original source.

## 1. Source detection (done by the orchestrator, confirmed by intake)

| Input pattern | source | id |
|---|---|---|
| `^[A-Z][A-Z0-9]+-\d+$` (e.g. `PROJ-123`) or a `.../browse/PROJ-123` URL | `jira` | the Jira key |
| URL on `app.datadoghq.*` / `*.datadoghq.*` containing `error-tracking` or `issueId=` | `datadog` | the Datadog issue id |
| `snyk:<id>` or a URL on `app.snyk.io` | `snyk` | the Snyk issue id (e.g. `SNYK-JS-LODASH-1018905`) |
| anything else | `prompt` | `req-<YYYYMMDD>-<slug>` (slug = 3–6 lowercase words from the request, `-` separated) |

## 2. Schema of work-item.md

```markdown
---
id: PROJ-123 | <datadog-issue-id> | SNYK-... | req-20261015-short-slug
source: jira | datadog | snyk | prompt
source_link: <URL to the original item, or "n/a" for prompt>
tracking_ticket: <Jira key created by the orchestrator, or "none">
type: feature | bug | vulnerability
severity: low | medium | high | critical
scope_owner: <name/role/handle>
---

## Summary
One paragraph: what is wrong or what is wanted, who is affected, why it matters.

## Evidence
<source-specific block, see §4 — copied verbatim where possible, never paraphrased into new facts>

## Classification rationale
- type: <rule from §5 that applied>
- severity: <rule from §6 that applied>
- scope_owner: <rule from §7 that applied>

## Open questions
- <anything the source does not say that later stages will need; empty list if none>
```

Rules:
- Every front-matter field is mandatory. If a value cannot be determined from the source,
  the file contains only `BLOCKED: <which field and why>` and nothing else.
- Never invent evidence. Quote the source; mark inferences explicitly as `(inferred)`.
- For `prompt`, the Evidence block MUST include the original request verbatim under
  `### Request` — the orchestrator uses it to detect resumable runs.

## 3. How to read each source

Tools available in this environment were checked on 2026-10-15: **no Jira, Datadog or Snyk
MCP server, CLI or credentials were found.** Until the team configures them, only the
`prompt` source works; for the others intake must write `BLOCKED: <source> tool not configured`.

### Jira
- TODO(team): configure a Jira tool. Options: Atlassian MCP server (`claude mcp add ...`,
  then add its tool names, e.g. `mcp__atlassian__getJiraIssue`, to `.claude/agents/intake.md`
  `tools:`), or the `acli`/`jira` CLI with `JIRA_*` env vars.
- Read: summary, description, issue type, priority, labels, components, reporter, assignee,
  acceptance criteria field (TODO(team): custom field id), linked issues, attachments list.

### Datadog
- TODO(team): configure a Datadog tool (Datadog MCP server, or `DD_API_KEY` + `DD_APP_KEY` +
  `DD_SITE` for the Error Tracking API via curl).
- Read: error type and message, full stack trace, service, env, endpoint/resource,
  first seen, last seen, occurrence count and frequency, affected version/release, sample trace id.

### Snyk
- TODO(team): configure a Snyk tool (Snyk MCP server, or `snyk` CLI with `SNYK_TOKEN`).
- Read: CVE/CWE ids, package, installed version, fixed version(s), dependency path
  (direct vs transitive), reachability (if Snyk reports it), exploit maturity, CVSS, Snyk severity,
  project/manifest file.

### Prompt
- The input text itself is the source. Read the repo only to locate the area mentioned;
  do not read git history or previous runs to "fill in" intent.

## 4. Evidence block per source

- **jira**: ticket title, full description, issue type, priority, labels, any AC field, reporter.
- **datadog**: stack trace (code block), service, env, endpoint, first seen, last seen,
  frequency (events/period), release/version, sample trace link.
- **snyk**: CVE, CWE, package, installed version, fixed version, dependency path
  (`app > a@1 > b@2`), reachability (reachable / not reachable / unknown), exploit maturity, CVSS.
- **prompt**: `### Request` (verbatim), requester (if known), any files/areas mentioned.

## 5. Type classification

| Source | Rule |
|---|---|
| jira | issue type `Bug` → `bug`; `Vulnerability`/`Security` issue type or `security` label → `vulnerability`; `Story`, `Task`, `Improvement`, `Epic`, `Sub-task` → `feature`. TODO(team): confirm the project's issue types. |
| datadog | always `bug`. If the error is a security symptom (auth bypass, data leak), still `bug` but add it to Open questions and raise severity one level. |
| snyk | always `vulnerability`. TODO(team): decide how license issues are handled (out of scope by default → BLOCKED). |
| prompt | "add / allow / support / new" → `feature`; "broken / fails / error / regression / should not" → `bug`; mentions CVE, a vulnerable dependency or a security flaw → `vulnerability`. If ambiguous → BLOCKED and ask. |

## 6. Severity mapping

| Source | Mapping |
|---|---|
| jira | Highest/Blocker → critical, High/Critical → high, Medium → medium, Low/Lowest/Trivial → low |
| datadog | critical: core flow down or data loss/corruption; high: user-facing errors on a main endpoint or rising frequency after a release; medium: recurring but with workaround; low: rare/noise. TODO(team): numeric thresholds (events/hour, % of requests). |
| snyk | start from Snyk severity. Raise one level if reachable AND exploit mature; lower one level (never below low) if reported not reachable. TODO(team): confirm security policy. |
| prompt | as stated by the requester; otherwise `medium`, noted in the rationale. |

## 7. Scope owner

| type | scope_owner |
|---|---|
| feature | Product Owner — TODO(team): name/handle |
| bug | owner of the affected service — TODO(team): service → owner map (CODEOWNERS?) |
| vulnerability | security team (TODO(team): handle) for high/critical; service owner otherwise |
| any, source = prompt | the requester, when no specific owner above applies |
