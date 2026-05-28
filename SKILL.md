---
name: codex-opencode-deepseek-workflow
description: Explicit-only personal Codex skill for any Git project when the user asks for OpenCode/DeepSeek execution or names $codex-opencode-deepseek-workflow. Codex orchestrates the work: inspect the target repository, write an AI development task order, invoke OpenCode with the configured worker model (DeepSeek V4 Pro by default), review and verify the resulting git diff, request repairs when needed, and stop before user runtime confirmation or any Git finalization.
---

# Codex OpenCode Worker Workflow

## Trigger

Use this skill only when the user explicitly asks for OpenCode/DeepSeek execution, names `$codex-opencode-deepseek-workflow`, or asks Codex to plan/review while OpenCode executes code changes.

Do not use this skill for ordinary Codex coding requests.

## Contract

- Treat this as a user-level, project-agnostic workflow for any Git repository.
- Never encode business-specific assumptions in the skill, scripts, or run artifacts.
- Read target-project rules from that project at runtime: `AGENTS.md`, `README*`, manifests, scripts, docs rules, and relevant source files.
- Keep task orders, logs, review notes, and summaries outside the target project by default.
- Let OpenCode modify code only in an isolated Git worktree created by this workflow.
- Leave final app/runtime confirmation and all Git finalization to the user.

## Roles

- Codex: inspect the project, create the task order, invoke OpenCode, review the diff, run validation commands, request repairs, and produce the final acceptance result.
- OpenCode worker model: modify code only according to the task order and Codex repair notes. DeepSeek V4 Pro is the default model profile, not a hard requirement.
- User: confirm real UI/business behavior and decide whether to `git add`, `commit`, `push`, or create a PR.

## Workflow

1. Confirm the target path is a Git repository with a clean source worktree.
2. Inspect project context before delegation.
   - Read project instructions and conventions.
   - Identify relevant files and likely validation commands.
   - Include any documentation-sync or contract-update rules in the task order.
3. Write an `AI-DEV-TASK.md` task order outside the target project.
4. Run `scripts/run-opencode-worker.ps1` with the project path and task order.
   - The script creates or reuses an external worktree.
   - The script calls `opencode run --agent codex-worker --model <configured-model>`.
5. Perform Codex acceptance on the generated worktree.
   - Inspect `git status --short`, `git diff --stat`, and `git diff`.
   - Check the diff against the task order, project rules, allowed scope, and forbidden actions.
   - Run the relevant validation commands in the generated worktree when feasible.
   - Check documentation updates when behavior, APIs, contracts, or user-visible behavior changed.
6. If required repairs exist, write `CODEX-REVIEW-FINDINGS.md` outside the project and run the worker again with the same worktree.
7. Stop after at most two automatic repair rounds.
8. Final output must include the worktree path, branch name, changed files, validation commands/results, acceptance status, unresolved issues, and whether user runtime confirmation is still required.

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

## Review And Acceptance Format

Write Codex review and acceptance notes with these exact sections:

- `diff 摘要`
- `问题清单`
- `必须返修项`
- `建议优化项`
- `验证结果`
- `最终验收结论`
- `是否允许进入人工运行确认`

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
- Do not run the worker when the source project has uncommitted changes.
- Do not write run artifacts into the target project unless the user explicitly asks.
- Do not claim success if validation failed, was skipped for a nontrivial reason, or required user runtime confirmation is still pending.

## Resources

- `scripts/new-ai-task.ps1`: create a task-order template in the user-level run directory.
- `scripts/run-opencode-worker.ps1`: create or reuse an isolated Git worktree and invoke OpenCode.
- `worker.config.json`: model profiles, default model profile, agent, run directory, and worktree directory.
