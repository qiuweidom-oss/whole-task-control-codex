---
name: whole-task-control
description: Use when the root/main Codex agent must integrate context beyond the latest message, including multi-turn decisions, corrections, plans, resumed work, coordinated subagents, or canonical outputs; never use for self-contained low-risk single-step requests or spawned/delegated subagents.
---

# Whole Task Control

## Scope gate

Use only as the root agent directly serving the user. Children never load this skill; they follow the root's bounded brief.

Do not use when the request is self-contained, low-risk, and single-step, no prior decision/progress affects the answer, and no coordination or durable artifact is needed. If the task depends on accumulated intent or state, continue below.

This skill is standalone. It requires no other skill or global framework and does not override system, developer, project, or other higher-priority instructions.

## Core principle

Treat the conversation as one evolving task. A new message updates that task; recency alone does not replace prior decisions. Respond and act from the relevant whole, never the latest sentence alone.

## Whole-task model

Maintain internally without reciting it every turn:

- desired outcome and current blocking problem;
- confirmed decisions;
- constraints, non-goals, and quality bar;
- evidence/examples versus reusable rules;
- real progress and next unfinished step;
- phase: discussion, decision, authorized execution, correction, acceptance;
- unresolved decision and legitimate stop point.

## Control loop

1. **Restore:** Read relevant conversation context. After compaction or handoff, also inspect whichever active goal, canonical plan/spec, files, Git state, and progress records exist and are relevant to the current task. Skip Git and code-state checks when they cannot affect a non-code task.
2. **Classify:** Is the new message evidence, refinement, correction, supersession, priority change, example, authorization, pause, or status request?
3. **Merge:** Update only affected fields. Preserve unrelated confirmed decisions and valid progress.
4. **Reconcile:** Check the intended response/action against outcome, phase, constraints, progress, and stop point.
5. **Respond or act:** Lead with the integrated conclusion. Ask one question only when an unresolved choice materially changes the result; otherwise make the smallest safe assumption and proceed.
6. **Persist:** On long work, update the existing active goal or canonical artifact at material decisions. Never create competing sources of truth.

User-intent precedence: explicit correction/supersession → latest confirmed decision → proposal under discussion → example/analogy/hypothesis. A local correction changes only its target unless clearly expanded. Discard stale assumptions; do not accumulate everything blindly.

## Evidence and authorization

Samples are evidence. Infer a reusable failure type or principle and use the sample for regression/acceptance. Never generalize names, IDs, coordinates, counts, colors, or wording unless explicitly defined as rules.

Discussion does not authorize mutation. Approval authorizes the integrated agreed design, not only the final sentence. Corrections preserve valid progress. Acceptance judges the requested outcome, not whether process steps merely ran.

## Workflow gate

Before recommending or invoking another workflow, read its complete instructions and mandatory integrations. Compare its actual reviews, stop points, subagents, worktrees, commits, and expansion with current constraints. Do not invoke hidden ceremony that conflicts with the agreed method. Permission to use tools or subagents is not permission to add mandatory process.

## Subagent contract

Give each child only the relevant outcome/context, exact scope/inputs, allowed and forbidden changes, acceptance evidence, and return format. The root verifies and integrates results; children do not reinterpret the user's whole conversation.

## Canonical outputs

For a final plan, directive, prompt, or goal update after several rounds, regenerate one complete artifact, explicitly supersede earlier drafts, and preserve scope, progress, execution method, acceptance, persistence, and stop point. Never make the user combine serial patches.

## Final gate

Before a meaningful response or action, verify:

- it serves the outcome, not merely the latest wording;
- the new message and any supersession were classified correctly;
- confirmed decisions, progress, and authorization remain intact;
- examples remain separate from general rules;
- unrequested expansion and ceremony are excluded;
- recommended workflows were fully inspected;
- compaction can recover the same task and next step.

If any check fails, reconcile before proceeding.

## Rationalizations to reject

| Excuse | Reality |
|---|---|
| "The latest sentence is what matters." | It updates the task; it is not automatically the whole task. |
| "Another patch is faster." | Deliver one canonical artifact; do not make the user merge versions. |
| "The workflow name sounds right." | Read its complete integrations before selecting it. |
| "This sample proves the rule." | Samples prove cases; reusable logic needs general evidence. |

Red flags: redoing completed work after correction/compaction; asking the user to repeat available context; named-sample special cases; or expanding into unrelated reviews, infrastructure, security, refactors, or polish.
