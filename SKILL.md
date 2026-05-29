---
name: codex-opencode-deepseek-workflow
description: >-
  Explicit-only personal Codex skill for Git projects when the user asks Codex
  to minimize its own token/cost usage by delegating implementation to
  OpenCode, DeepSeek, or another configured worker model. Use only when the
  user names $codex-opencode-deepseek-workflow, asks for OpenCode/DeepSeek to
  execute code changes, or explicitly wants Codex to write a lightweight task
  order and launch a worker model. Codex acts as a low-cost dispatcher: create a
  compact AI development task order, invoke OpenCode in the current Git working
  directory, report artifacts, and stop before review, validation, or Git
  finalization.
---

# Codex OpenCode Worker Workflow

## Purpose

This skill exists to reduce Codex consumption as much as possible while still
using Codex's strengths for task framing, safety boundaries, and orchestration.
The token-heavy work, including repository reading and code editing, belongs to
OpenCode with the configured worker model, usually DeepSeek.

## Trigger

Use this skill only when the user explicitly asks for one of these:

- `$codex-opencode-deepseek-workflow`
- OpenCode execution
- DeepSeek or another non-Codex worker model to implement code changes
- Codex to create a lightweight task order and launch a worker
- a low-Codex-token / low-Codex-cost implementation workflow

Do not use this skill for ordinary Codex coding requests, code reviews, test
runs, debugging, or implementation work unless the user explicitly asks to
delegate execution to OpenCode or a worker model.

## Core Contract

- Treat this as a user-level, project-agnostic workflow for any Git repository.
- Codex is the dispatcher, not the implementer.
- Minimize Codex context use: do not read broad project files, inspect large
  diffs, run searches, or infer architecture unless the task cannot be safely
  framed without that context.
- Prefer the user's prompt as the source of truth. Ask one short question only
  when missing information would make the worker likely to damage unrelated
  code.
- Keep task orders, logs, and summaries outside the target project by default.
- Let OpenCode modify code directly in the current Git working directory.
- Leave diff review, runtime validation, repair rounds, staging, commits,
  pushes, and PRs to the user unless the user starts a separate Codex task.

## Roles

- Codex: verify the target is a Git repo, create a compact task order, invoke
  OpenCode, report the worker result and artifact paths, then stop.
- OpenCode worker model: read only the project context it needs and modify code
  according to the task order. DeepSeek V4 Pro is the default profile, but any
  configured model can be used.
- User: inspect `git diff`, run project/tests, confirm UI or business behavior,
  and decide whether to `git add`, `commit`, `push`, or create a PR.

## Low-Codex-Consumption Rules

- Spend Codex tokens on boundaries, not implementation details.
- Do not summarize the repository for the worker. The worker can read files
  itself through OpenCode.
- Do not pre-solve the task in Codex. Give the worker goals, constraints,
  allowed scope, forbidden actions, and validation suggestions.
- Keep `AI-DEV-TASK.md` concise, usually under 120 lines.
- Do not run `git diff`, tests, linters, builds, browsers, or repair loops after
  the worker finishes in this lightweight workflow.
- If the worker fails, report the log path and blocker. Do not automatically
  start a second implementation round.

## Workflow

1. Confirm the target path is inside a Git repository.
2. Write a lightweight `AI-DEV-TASK.md` outside the target project.
   - Include the user's goal, known constraints, forbidden actions, allowed
     scope, acceptance criteria, and suggested validation commands if already
     known.
   - Do not scan large parts of the repository just to fill in the task order.
   - Use "not specified by user" where details are unknown but safe for the
     worker to discover.
3. Run `scripts/run-opencode-worker.ps1` with the project path and task order.
   - The script calls `opencode run <message> --dir <repo-root> --agent
     <configured-agent> --model <configured-model> --file <task>`.
   - The script does not require a clean working tree, create a separate
     checkout, create a branch, inspect `git diff`, or run validation.
4. Final output must include the target repo path, run directory, task file,
   OpenCode log path, worker exit status, model, and a clear note that the user
   must review and validate the current working directory.

## Task Order Format

Write the task order with these exact sections:

- `任务目标`
- `当前项目背景`
- `必须遵守的项目规则`
- `允许修改范围`
- `禁止事项`
- `实现要求`
- `验收标准`
- `建议验证命令`
- `交付物要求`

Keep the task order short. Prefer concise bullets over detailed analysis.

## Model Configuration

Resolve the OpenCode model in this order:

1. `-Model` passed to `scripts/run-opencode-worker.ps1`
2. `CODEX_OPENCODE_MODEL` environment variable
3. `-ModelProfile` passed to the script
4. `CODEX_OPENCODE_MODEL_PROFILE` environment variable
5. `defaultModelProfile` in `worker.config.json`

If no model resolves, stop and ask the user to configure `worker.config.json` or
pass `-Model`.

Keep DeepSeek V4 Pro as the default profile unless the user explicitly changes
it. To switch later, add a `modelProfiles` entry after confirming the model id
with `opencode models`, then set `defaultModelProfile` to that profile name. Do
not put a `model:` field in `opencode/agents/codex-worker.md`; the agent defines
permissions and behavior only.

## Guardrails

- Never stage, commit, merge, reset, push, create a PR, or run release steps.
- Never copy, print, or store API keys. OpenCode owns provider credentials.
- Do not use OpenCode automatic permission approval or dangerous permission-skip
  modes.
- Do not write run artifacts into the target project unless the user explicitly
  asks.
- Do not perform Codex diff review, validation, browser checks, or automatic
  repair rounds in this lightweight workflow.
- Do not claim the code is accepted or verified; user review and runtime
  validation are required.

## Final Response Template

Use a compact final response:

```text
已把任务交给 OpenCode worker 执行。

目标仓库: <path>
模型: <model>
运行目录: <runDir>
任务单: <taskFile>
日志: <opencodeLog>
退出码: <opencodeExitCode>

下一步请人工查看 git diff，并运行项目验证命令。此 workflow 不自动验收、不提交 Git。
```

## Resources

- `scripts/new-ai-task.ps1`: create a lightweight task-order template in the
  user-level run directory.
- `scripts/run-opencode-worker.ps1`: invoke OpenCode in the current Git working
  directory and save run artifacts.
- `worker.config.json`: model profiles, default model profile, agent, and run
  directory.
- `opencode/agents/codex-worker.md`: OpenCode worker agent permissions and
  behavior.
