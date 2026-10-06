# AGENTS.md

DankMaterialShell plugin for mise (QML). Dev setup and reload rules: README → *Development*.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <summary>`.

- Types: `feat`, `fix`, `refactor`, `perf`, `style`, `docs`, `chore`, `build`, `ci`.
- Scope = component, optional: `widget`, `panel`, `launcher`, `daemon`, `service`, `settings`.
- Summary: imperative, lowercase, no trailing period, ≤72 chars.
- Body explains why, wrapped at 72. Breaking change: `!` after type/scope plus a `BREAKING CHANGE:` footer.
- One logical change per commit.
- Release commit: `chore(release): 0.2.3`, touching only the `version` in `plugin.json`.

History before this file predates the convention; leave it.

## Branches and PRs

- Branch from `main` as `<type>/<kebab-summary>` (`feat/remote-search`, `fix/chip-row-height`, `release/0.2.2`).
- Land through a PR with a merge commit.
- PR title follows the commit format.

## Releases

Bump `version` in `plugin.json`, merge, then tag `vX.Y.Z` on `main`.

## Code

- Style from theme tokens (spacing, radius, font sizes); no hardcoded sizes or fonts.
- User-facing text and docs in English.
- New user-visible behaviour updates README in the same PR.
