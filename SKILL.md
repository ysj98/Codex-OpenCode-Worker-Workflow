---
name: codex-opencode-deepseek-workflow
description: >-
  Explicit-only personal Codex skill for Git projects when the user wants
  Codex to minimize its own token/cost usage while using its reasoning ability
  to guide OpenCode, DeepSeek, or another configured worker model. Use only
  when the user names $codex-opencode-deepseek-workflow, asks for
  OpenCode/DeepSeek execution, asks Codex to write an implementation plan for a
  worker model, or explicitly wants low-Codex-cost delegated coding. Codex acts
  as architect/planner: perform bounded targeted reconnaissance, write a
  construction-grade AI development task order, launch OpenCode in the current
  Git working directory, return run artifacts immediately by default, and leave
  final review and Git decisions to the user.
---

# Codex OpenCode Worker Workflow

## Purpose

This skill reduces Codex consumption while still using Codex where it is most
valuable: understanding the user's intent, framing the implementation strategy,
choosing safety boundaries, and writing a high-quality task order for another
model.

The token-heavy work belongs to OpenCode with the configured worker model,
usually DeepSeek: broad repository reading, searches, implementation, test
execution, and verification. The default run mode is async-first so Codex does
not wait while the worker spends tokens.

## Trigger

Use this skill only when the user explicitly asks for one of these:

- `$codex-opencode-deepseek-workflow`
- OpenCode execution
- DeepSeek or another non-Codex worker model to implement code changes
- Codex to guide, brief, or write a task order for OpenCode/DeepSeek
- low-Codex-token or low-Codex-cost delegated implementation

Do not use this skill for ordinary Codex coding requests, code reviews, or
debugging unless the user explicitly asks to delegate implementation to
OpenCode or a worker model.

## Core Contract

- Codex is the architect/planner, not the implementer.
- OpenCode/DeepSeek is the implementer/verifier and may spend substantial
  tokens reading, searching, editing, and running validation commands.
- Default to background worker execution: Codex launches the worker, reports the
  run directory and process id, then stops.
- Keep task orders, logs, and summaries outside the target project by default.
- Let OpenCode modify code directly in the current Git working directory.
- Leave final diff review, business validation, staging, commits, pushes, and
  PRs to the user.

## Codex Reconnaissance Budget

Pick the lightest mode that can produce a useful task order:

- `fast`: read repository guidance files and manifests only. Use for small or
  obvious tasks.
- `guided` (default): read guidance files, manifests, and at most 5 clearly
  relevant project files.
- `deep-plan`: read guidance files, manifests, and at most 12 relevant files.
  Use only when the user asks for deeper planning or the task is risky.

Always prefer `rg`/`rg --files` to locate likely files. Do not do full-repo
analysis, implement code, run final validation, or review the worker's final
diff in this workflow. Spend Codex tokens on the implementation strategy and
boundaries; let the worker spend tokens on execution.

## Roles

- Codex: confirm the target is a Git repo, do bounded targeted reconnaissance,
  write a construction-grade task order, launch OpenCode in the background,
  report artifacts, then stop.
- OpenCode worker model: follow the task order, discover additional context,
  implement the change, run appropriate validation commands, and summarize what
  changed and what validation passed or failed.
- User: later inspect `git diff`, check the worker summary, confirm
  runtime/business behavior, and decide whether to `git add`, `commit`, `push`,
  or create a PR.

## Workflow

1. Confirm the target path is inside a Git repository.
2. Do bounded reconnaissance using the budget above.
3. Write `AI-DEV-TASK.md` outside the target project.
   - Include the user's goal, Codex's reconnaissance findings, likely entry
     points, a suggested implementation route, worker execution steps, risks,
     allowed scope, forbidden actions, acceptance criteria, and validation
     commands.
   - Be specific enough that OpenCode/DeepSeek can execute efficiently.
   - Do not claim the suggested route is exhaustive; instruct the worker to
     verify by reading the code.
4. Run `scripts/run-opencode-worker.ps1` with `-Background` by default.
   - The script launches `opencode run <message> --dir <repo-root> --agent
     <configured-agent> --model <configured-model> --file <task>`.
   - Background mode writes logs and completion state under the run directory,
     returns JSON immediately, and avoids Codex waiting for worker completion.
   - Only omit `-Background` when the user explicitly asks Codex to wait.
5. Final output must include the target repo path, run directory, task file,
   OpenCode log path, worker status, process id, model, and the check command.
6. When the user later asks to check progress, run
   `scripts/check-opencode-worker.ps1 -RunDir <runDir>`.
   - Default check reads `worker-summary.json`, optional `worker-completion.json`,
     process status, and only a small log tail.
   - Do not read or paste the full OpenCode log unless the user explicitly asks.

## Task Order Format

Write the task order with these exact sections:

- `任务目标`
- `Codex 定向侦察摘要`
- `关键文件与入口线索`
- `建议实现路线`
- `Worker 执行步骤`
- `风险与边界`
- `允许修改范围`
- `禁止事项`
- `验收标准`
- `建议验证命令`
- `交付物要求`

Guidance for sections:

- `Codex 定向侦察摘要`: concise facts Codex discovered, including files read and
  constraints found.
- `关键文件与入口线索`: list likely files, symbols, routes, commands, or search
  terms the worker should inspect first.
- `建议实现路线`: provide an executable strategy: where to start, how to trace
  call paths, likely changes, compatibility concerns, and how to avoid unrelated
  edits.
- `Worker 执行步骤`: explicitly tell OpenCode/DeepSeek to supplement context,
  implement, run validation, and stop with a blocker summary if the plan is
  unsafe or contradicted by the repository.

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
- Do not perform Codex final diff review, business validation, browser checks,
  or automatic repair rounds after the worker finishes.
- Do not claim the code is accepted or verified by Codex; user review is
  required even when the worker reports passing tests.

## Final Response Template

Use a compact final response:

```text
已在后台启动 OpenCode worker。

目标仓库: <path>
模型: <model>
状态: <status>
PID: <processId>
运行目录: <runDir>
任务单: <taskFile>
日志: <opencodeLog>

稍后检查:
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/check-opencode-worker.ps1" -RunDir "<runDir>"

此 workflow 不等待 worker 完成、不自动提交 Git。worker 完成后请人工查看 git diff 和验证摘要。
```

## Resources

- `scripts/new-ai-task.ps1`: create a construction-grade task-order template in
  the user-level run directory.
- `scripts/run-opencode-worker.ps1`: invoke OpenCode in the current Git working
  directory and save run artifacts; pass `-Background` for the default optimized
  async mode.
- `scripts/check-opencode-worker.ps1`: check a background worker run using
  summary files and a bounded log tail.
- `worker.config.json`: model profiles, default model profile, agent, and run
  directory.
- `opencode/agents/codex-worker.md`: OpenCode worker agent permissions and
  behavior.
