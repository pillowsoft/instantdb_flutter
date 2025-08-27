# /commit — Flutter/Melos Conventional Commit (with emoji)

You are Claude Code running inside a Flutter/Dart (optionally Melos) repo.
Your job: perform safe, atomic commits with conventional-commit messages + emojis.

## Parse args
- Accept optional flags from `$ARGUMENTS`:
  - `--no-verify` → skip pre-commit checks
  - `--scope=<name>` → add `(<name>)` scope in commit type (e.g., `feat(<name>): ...`)
  - `--allow-large` → don’t suggest splitting even if changes are broad
  - `--skip-tests` → skip `flutter test`
  - `--workspace` → force Melos flow even if autodetect fails

## Project autodetect
- If `melos.yaml` exists **or** `--workspace` is passed → workspace mode.
- Otherwise → single-package mode.

## Pre-commit checks (skip if `--no-verify`)
Perform the lightest, fast-but-useful checks for Flutter/Dart repos:
1. **Get deps**
   - Workspace: `melos bs` (bootstrap)
   - Single: `flutter pub get`
2. **Format (fail on diffs)**
   - `dart format --set-exit-if-changed .`
3. **Analyze**
   - `flutter analyze`
4. **Tests** (unless `--skip-tests`)
   - Preferred quick pass: `flutter test`
5. **(Optional codegen if configured)**
   - If any of these scripts exist in `melos.yaml` or `pubspec.yaml` scripts: run them in this order when present:
     - `melos run build_runner` or `dart run build_runner build --delete-conflicting-outputs`
     - `melos run gen` or `flutter gen-l10n` (if `l10n.yaml` exists)

If any step fails:
- Show concise failure summary + last 60 lines of stderr.
- Ask whether to:
  1) proceed anyway, 2) fix and retry checks, or 3) abort.

## Stage handling
- Show staged files: `git status --porcelain`
- If **0 staged**: `git add -A` (explain you auto-staged; user can undo later)
- Re-list staged paths.

## Diff analysis & split suggestion
- Run `git diff --cached --name-status` and `git diff --cached`.
- Infer logical groups using these heuristics:
  - Separate **tests** (`*_test.dart`, `test/**`) from **src**.
  - Separate **docs/config** (`README.md`, `CHANGELOG.md`, `*.md`, `analysis_options.yaml`, `melos.yaml`, `.github/**`) from **code**.
  - Separate **generated** (`*.g.dart`, `*.freezed.dart`, `*.gen.dart`) from **handwritten**.
  - Separate **UI-only** changes (widget/layout/style) from **logic** where obvious.
- If multiple concerns and **no** `--allow-large`, propose a split plan:
  - Present 1–N groups with file lists.
  - Ask to confirm:
    - `[Proceed as one commit]`
    - `[Split as suggested]`
    - `[Edit groups]` (user can move files between groups)
- If splitting, for each group:
  - `git reset` then `git add <files for group>`
  - Continue to “Message generation & commit” for that group.
  - After commit, re-stage remaining group files and repeat.

## Message generation & commit
Use **conventional commits + emoji**. Map common types:

- ✨ `feat` — new feature
- 🐛 `fix` — bug fix
- 📝 `docs` — docs only
- 💄 `style` — formatting/style
- ♻️ `refactor` — refactor
- ⚡️ `perf` — perf
- ✅ `test` — tests
- 🔧 `chore` — tooling/config/build
- 🚀 `ci` — CI/CD
- ⏪️ `revert` — revert

### Choosing type & scope
- Infer type from diff + filenames + hints in `$ARGUMENTS`.
- If `--scope=X` passed → use `(X)` after type, e.g. `feat(ui): ...`.
- Otherwise infer simple scope (e.g. `player`, `analytics`, `l10n`, `build`, `tests`) when obvious.

### Compose the message
- **Title (<=72 chars)**: `<emoji> <type>(<scope>)?: <imperative, present-tense summary>`
  - Examples:
    - `✨ feat(player): add AB repeat controls`
    - `🐛 fix(analytics): resolve null timestamps in segment export`
- **Body (bullets, short lines)**: what changed + why; mention edge cases.
- **Footer (optional)**:
  - `BREAKING CHANGE:` if applicable
  - `Refs:` or `Closes:` issue IDs

Show the candidate message, then:
- If user confirms → commit:
  - `git commit -m "<title>" -m "<body>" -m "<footer-if-any>"`
- If user edits → commit with edits.

## Post-commit
- Show `git log -1 --stat`.
- If more groups remain (in split mode), continue.
- If workspace and `melos version` or `melos run changelog` is part of your flow, offer to run it.

## Safety/notes
- Never push automatically.
- Never run `flutter build <platform>` unless explicitly asked (too slow for a commit).
- Keep output concise.

## Now execute
Follow the flow above using the shell tool. Use interactive confirmations only where asked.
Use `$ARGUMENTS` for flags. Prefer fast feedback.
