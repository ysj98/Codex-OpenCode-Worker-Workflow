---
name: codex-opencode-deepseek-workflow
description: >-
  Explicit-only personal Codex skill for any Git project when the user asks for
  OpenCode/DeepSeek execution or names $codex-opencode-deepseek-workflow. Codex
  creates a lightweight AI development task order, invokes OpenCode with the
  configured worker model in the current working directory, and stops for human
  code review, runtime validation, and Git finalization.
---

# Codex OpenCode Worker Workflow

## Trigger

Use this skill only when the user explicitly asks for OpenCode/DeepSeek execution, names `$codex-opencode-deepseek-workflow`, or asks Codex to create a lightweight task order while OpenCode executes code changes.

Do not use this skill for ordinary Codex coding requests.

## Contract

- Treat this as a user-level, project-agnostic workflow for any Git repository.
- Minimize Codex token usage: avoid broad project analysis unless the user explicitly asks for it.
- Never encode business-specific assumptions in the skill, scripts, or run artifacts.
- Keep task orders, logs, and summaries outside the target project by default.
- Let OpenCode modify code directly in the current Git working directory.
- Leave code review, app/runtime validation, and all Git finalization to the user.

## Roles

- Codex: create a short task order, invoke OpenCode, report the worker result and log path, then stop.
- OpenCode worker model: read the project context it needs and modify code according to the task order. DeepSeek V4 Pro is the default model profile, not a hard requirement.
- User: inspect `git diff`, run the project/tests, confirm UI/business behavior, and decide whether to `git add`, `commit`, `push`, or create a PR.

## Workflow

1. Confirm the target path is a Git repository.
2. Write a lightweight `AI-DEV-TASK.md` task order outside the target project.
   - Include the user's goal, obvious constraints, forbidden actions, and suggested validation when already known.
   - Do not spend tokens reading large parts of the repository unless required to clarify the task.
3. Run `scripts/run-opencode-worker.ps1` with the project path and task order.
   - The script calls `opencode run <message> --dir <repo-root> --agent codex-worker --model <configured-model> --file <task>`.
   - The script does not require a clean working tree, create a separate checkout, create a branch, inspect `git diff`, or run validation.
4. Final output must include the target repo path, run directory, task file, OpenCode log path, worker exit status, and a clear note that the user must review and validate the current working directory.

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

1. `-Model` passed to `scripts/run-opencode-worker.ps1`.
2. `CODEX_OPENCODE_MODEL` environment variable.
3. `-ModelProfile` or `CODEX_OPENCODE_MODEL_PROFILE`.
4. `defaultModelProfile` in `worker.config.json`.

If no model resolves, stop and ask the user to configure `worker.config.json` or pass `-Model`.

Keep DeepSeek V4 Pro as the default profile unless the user explicitly changes it. To switch later, add a `modelProfiles` entry after confirming the model id with `opencode models`, then set `defaultModelProfile` to that profile name. Do not put a `model:` field in `opencode/agents/codex-worker.md`; the agent defines permissions and behavior only.

## Guardrails

- Never stage, commit, merge, reset, push, create a PR, or run release steps.
- Never copy, print, or store API keys. OpenCode owns provider credentials.
- Do not use OpenCode automatic permission approval or dangerous permission-skip modes.
- Do not write run artifacts into the target project unless the user explicitly asks.
- Do not perform Codex diff review, validation, or automatic repair rounds in this lightweight workflow.
- Do not claim the code is accepted or verified; user review and runtime validation are required.

## Resources

- `scripts/new-ai-task.ps1`: create a lightweight task-order template in the user-level run directory.
- `scripts/run-opencode-worker.ps1`: invoke OpenCode in the current Git working directory and save run artifacts.
- `worker.config.json`: model profiles, default model profile, agent, and run directory.
