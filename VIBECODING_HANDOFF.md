# Meeting Transcriber Vibe Coding Handoff

## Shared Vibe Coding workflow rules (2026-10-08)

### Documentation-only handoff exception
- When the user explicitly requests a documentation-only update, ChatGPT may edit the existing root `VIBECODING_HANDOFF.md` directly through GitHub without requiring a Mac build or a local checkout step.
- First inspect the actual repository, target branch, and existing handoff. Change only the handoff, preserve historical project context, and verify the resulting GitHub file and commit. Do not use this exception for application code, tests, scripts, configuration, workflows, version/build changes, release assets, or other build-affecting files.
- Before the next local development change, fetch the remote branch and reconcile the updated handoff with the local checkout. Never overwrite or silently reset unrelated local changes.
- The normal rule remains: validate the exact executable/build-affecting changes in the real Mac checkout before committing or pushing those changes. Include a current handoff with every meaningful validated development commit.

### Temporary worktrees, releases, and logs
- Create temporary Git worktrees under `/Users/alex/Desktop/tmp/<project>-...` using a project-specific name.
- Put release working folders, temporary release artifacts, staging directories, and build/release logs under `/Users/alex/Desktop/tmp/<project>-release-...`.
- Do not create disposable worktrees inside `/Users/alex/Documents/Vibe Coding`.
- Do not place release artifacts or logs directly on the Desktop root.
- After a successful verified release, remove temporary worktrees and temporary release artifacts when safe. Do not remove active worktrees, uncommitted work, published assets, or permanent project files.
- Retain failure logs only when useful for debugging; remove unnecessary temporary logs.
- These instructions govern future operations and take precedence over historical temporary-path examples elsewhere in this handoff.

### Low-overhead development defaults
- Use ChatGPT plus GitHub inspection and Mac-local Terminal scripts by default; do not use Codex, ChatGPT Work, separately billed API agents, or GitHub Actions runners unless explicitly requested.
- Prefer existing project scripts. Give one local command block to apply, build, test, and launch an executable change, then a separate commit/push block only after required validation is confirmed.
- Documentation-only updates under the exception above do not require a rebuild.

## Project

Meeting Transcriber is a local-first macOS menu-bar app for recording meeting audio, transcribing locally with WhisperKit or Parakeet, diarizing speakers, and generating Markdown meeting protocols.

## Repository and release state

- Repository: `TheCuriousProcrastinator/meeting-transcriber`
- Local checkout created for this migration: `/Users/alex/Documents/Vibe Coding/MeetingTranscriber`
- Default branch: `main`
- `main` policy-migration baseline: `c716a52958981a7a5ab14d2167a9dbdcbe82ef6f`
- Custom development/release branch: `alex`
- `alex` policy-migration baseline: `89c02d1c637bb200063c10b3058478a7ecdddf09`
- Latest custom published release verified during migration: `v0.8.6`
- `v0.8.6` targets `89c02d1c637bb200063c10b3058478a7ecdddf09`.
- The `VERSION` value on `main` is not sufficient by itself to identify the latest custom published release.

## Architecture

- Swift macOS app: `app/MeetingTranscriber`
- Swift package: `app/MeetingTranscriber/Package.swift`
- App sources: `app/MeetingTranscriber/Sources`
- Tests: `app/MeetingTranscriber/Tests`
- AudioTap support: `tools/audiotap`
- Development build and launch: `scripts/run_app.sh`
- Distribution build: `scripts/build_release.sh`
- GitHub workflows: `.github/workflows`

## Authoritative development workflow

The user's actual Mac is authoritative for development and release validation.

Before any normal development GitHub write:

- fetch the relevant remote branch
- verify the expected branch and HEAD
- inspect local status
- preserve unrelated local work
- validate the exact changed files locally
- use the project's local build/test process
- for UI and behavioral changes, leave the fresh development build running and wait for explicit user PASS when manual verification is required

Only the exact locally validated files may be committed and pushed.

## GitHub Actions policy

GitHub Actions must never run automatically.

All 18 workflow files under `.github/workflows` are intentionally manual-only through `workflow_dispatch`.

Automatic Actions are disabled for:

- branch pushes
- pull requests
- release/version tags
- schedules
- Dependabot activity
- PR labels
- Pages changes
- every other repository event

Actions may run only when explicitly requested by the user as optional clean-environment verification.

Several retained workflows were originally designed around event-specific context. Some may skip or be unsuitable when manually dispatched. Do not restore automatic triggers to make them run.

## Release policy

Normal release validation and artifact creation happens locally.

`scripts/build_release.sh` remains the local distribution build path.

A release must not depend on push-triggered or tag-triggered GitHub Actions.

GitHub remains the host for committed source/history, branches, tags, releases, and downloadable assets.

At the 2026-10-02 migration audit, the `TheCuriousProcrastinator/meeting-transcriber` repository had no active GitHub repository rulesets. `.github/tag-ruleset.json` is upstream-oriented, and `scripts/configure-tag-ruleset.sh` defaults to `pasrom/meeting-transcriber`. Do not apply that required-status-check ruleset to this fork while the manual-only policy is active.

GitHub does not back up signing identities/private keys, Keychain credentials, local secrets, ignored files, or uncommitted work.

## 2026-10-02 policy migration scope

This migration changes only:

- trigger declarations in the 18 existing `.github/workflows` files
- `AGENTS.md`
- `CLAUDE.md`
- `.claude/skills/distribution/SKILL.md`
- `VIBECODING_HANDOFF.md`

It does not change app source, tests, `VERSION`, build scripts, release artifacts, or runtime behavior.

The same workflow policy is intentionally applied to both `main` and `alex`.

## Next development task

After the policy migration is committed to both `main` and `alex`, resume development from the branch appropriate to the task. Verify current repository state first and preserve unrelated work.
