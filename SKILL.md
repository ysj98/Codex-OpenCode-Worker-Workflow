---
name: codex-opencode-deepseek-workflow
description: Use this explicit-only workflow when the user asks Codex CLI to coordinate development through OpenCode and DeepSeek V4: Codex analyzes requirements, writes an AI development task order, invokes DeepSeek via OpenCode to modify code, reviews git diff, and prepares repair feedback while leaving final run confirmation and Git commits to the user.
---

# Codex + OpenCode + DeepSeek Workflow

## Trigger

Use this skill only when the user explicitly asks for OpenCode/DeepSeek execution, names `$codex-opencode-deepseek-workflow`, or says that Codex should plan and review while DeepSeek modifies code.

Do not use this skill for ordinary Codex coding requests.

## Roles

- Codex: analyze the request, inspect the project, write the AI development task order, invoke the worker script, review `git diff`, and write repair feedback.
- DeepSeek V4 through OpenCode: modify code only according to the task order and repair feedback.
- User: run the application, confirm product/UI behavior, and make final Git commits or pushes.

## Codex Workflow

1. Inspect the target Git project before delegation.
   - Read project instructions such as `AGENTS.md`, `README*`, manifests, scripts, and relevant source files.
   - Identify likely verification commands without inventing project-specific rules.
   - If the repository has documentation sync rules, include them in the task order.
2. Write an AI development task order with these exact sections:
   - `任务目标`
   - `当前项目背景`
   - `必须遵守的项目规则`
   - `允许修改范围`
   - `禁止事项`
   - `实现要求`
   - `验收标准`
   - `建议验证命令`
   - `交付物要求`
3. Save the task order outside the project, normally under:
   `C:\Users\yshij\.codex\runs\codex-opencode-deepseek-workflow\`
4. Run `scripts/run-opencode-worker.ps1` with the project path and task order.
   - The script requires a clean source Git worktree.
   - It creates an external Git worktree under `C:\Users\yshij\.codex\worktrees`.
   - It calls `opencode run` with the `codex-worker` agent and the configured DeepSeek V4 model.
5. Review the worker result.
   - Inspect `git status`, `git diff --stat`, and `git diff` in the generated worktree.
   - Run the relevant verification commands yourself in the generated worktree.
   - Check project-specific documentation rules when behavior or contracts changed.
6. If repair is needed, write a review/fix note with:
   - `diff 摘要`
   - `问题清单`
   - `必须返修项`
   - `建议优化项`
   - `是否允许进入人工运行确认`
   Then run the worker script again with the same generated worktree and the review note.
7. Stop after at most two automatic repair rounds. Report unresolved issues instead of claiming success.

## Guardrails

- Never commit, merge, push, create a PR, or stage files as part of this workflow.
- Never copy or print API keys. OpenCode owns provider credentials.
- Do not run the worker when the source project has uncommitted changes.
- Keep all run artifacts outside the project unless the user explicitly asks otherwise.
- Final delivery should tell the user the generated worktree path, branch name, changed files, verification result, and whether user runtime confirmation is still needed.

## Resources

- `scripts/new-ai-task.ps1`: create a task-order template in the user-level run directory.
- `scripts/run-opencode-worker.ps1`: create or reuse an isolated Git worktree and invoke OpenCode.
- `worker.config.json`: default model, agent, run directory, and worktree directory.
