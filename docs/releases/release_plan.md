Plan: Automated Release Workflow with Target-Branch Methodology

 Context

 The current release process is manual: bump version, update changelog, commit, push, then run scripts/release.sh to create a tag, which triggers GitHub Actions to create a release. This plan replaces that with an
 automated workflow that triggers on PR merge, using the target-branch methodology adapted from mountainash-data. The branch model adds a develop integration branch with full RC and beta pre-release support.

 Branch Model
 ┌─────────────────────┬─────────────────┬─────────────────────┬───────────────────────────┐
 │       Branch        │     Purpose     │      PRs From       │       Release Type        │
 ├─────────────────────┼─────────────────┼─────────────────────┼───────────────────────────┤
 │ main                │ Production only │ release/*, hotfix/* │ Production (vX.Y.Z)       │
 ├─────────────────────┼─────────────────┼─────────────────────┼───────────────────────────┤
 │ develop             │ Integration     │ feature/*, bugfix/* │ RC (vX.Y.Z-rc.N)          │
 ├─────────────────────┼─────────────────┼─────────────────────┼───────────────────────────┤
 │ feature/*, bugfix/* │ Development     │ topic branches      │ Beta (vX.Y.Z-beta.NAME.N) │
 └─────────────────────┴─────────────────┴─────────────────────┴───────────────────────────┘
 Files to Modify

 1. .github/workflows/release.yaml (REPLACE)

 Replace entirely with target-branch release workflow:

 Triggers: PR merge (pull_request: types: [closed]) to main/develop/release*/feature*/bugfix*/hotfix* + manual workflow_dispatch with release_type (production/rc/beta) and source_branch inputs.

 Job guard: if: github.event.pull_request.merged == true || github.event_name == 'workflow_dispatch'

 Steps:
 1. Checkout (merge_commit_sha for PRs, source_branch for manual)
 2. Install yq
 3. Set branch vars (SOURCE_BRANCH, TARGET_BRANCH)
 4. Get base version from package.yaml via yq -r '.version', validate semver
 5. Determine release config (core logic):
   - main target + release/* or hotfix/* source = production (vX.Y.Z, prerelease=false)
   - main target + anything else = ERROR ("Only release/hotfix branches can target main")
   - develop target = RC (vX.Y.Z-rc.N, prerelease=true)
   - Other target = beta (vX.Y.Z-beta.NAME.N, prerelease=true)
   - Auto-increment N via gh release list --json tagName --jq (cleaner than mountainash's curl approach)
   - Manual dispatch maps release_type input to same logic
 6. Verify plugin.json version matches package.yaml (production only)
 7. Validate tag doesn't already exist
 8. Extract release notes: changelog section for production, generated notes for pre-releases
 9. Create and push annotated tag
 10. Create GitHub Release via gh release create (with --prerelease flag for RC/beta)
 11. Summary with release URL + raw URL verification command

 Key design choices:
 - Semver pre-release format: 3.0.0-rc.1 (proper semver, not PEP 440 3.0.0rc1 like mountainash)
 - No version file mutation for pre-releases: package.yaml stays at base version, suffix is computed
 - Use gh release create instead of deprecated actions/create-release@v1

 2. RELEASING.md (REWRITE)

 Complete rewrite documenting:
 - Automated workflow overview (PR merge triggers release)
 - Branch model table (from above)
 - Version pinning strategy (updated with pre-release references: @v3.0.0-rc.1, @v3.1.0-beta.new-types.1)
 - Production release workflow: feature branch -> PR to develop (RC) -> release branch -> PR to main (production)
 - Hotfix workflow: hotfix branch -> PR to main
 - Manual trigger: gh workflow run release.yaml -f release_type=rc -f source_branch=develop
 - Emergency manual release: reference scripts/release.sh (deprecated for normal use)
 - Troubleshooting (keep existing sections, add pre-release guidance)

 3. scripts/release.sh (MINOR MODIFY)

 Add deprecation notice at top of main():
 log_warning "DEPRECATED: Releases are now automated via GitHub Actions on PR merge."
 log_warning "This script is retained for emergency/manual use and backfill operations."
 log_warning "See RELEASING.md for the current release process."
 Keep all existing functionality intact as emergency fallback.

 4. CLAUDE.md (MODIFY)

 Update Git Workflow section (lines ~172-175) to document the new branch model:
 ## Git Workflow

 - Main branch: `main` (production releases only)
 - Develop branch: `develop` (integration, RC releases)
 - Feature branches: `feature/*`, `bugfix/*` (beta releases on merge)
 - Release branches: `release/*` (merge to main for production)
 - Hotfix branches: `hotfix/*` (merge to main for production)
 - Releases are tagged automatically on PR merge by GitHub Actions
 - Tags follow semver: `v3.0.0`, `v3.1.0-rc.1`, `v3.1.0-beta.my-feature.2`

 5. skills/pr-version-bump/SKILL.md (MINOR MODIFY)

 Update Phase 6: REPORT Prepare Mode Report next steps from:
 1. Review the PR and get approval
 2. After merge, tag release: `./scripts/release.sh`
 To:
 1. Review the PR and get approval
 2. Merge the PR -- GitHub Actions will automatically create a tagged release

 Post-Implementation Setup

 Create develop branch (one-time, after workflow is merged):
 git checkout main && git checkout -b develop && git push -u origin develop

 Verification

 1. actionlint .github/workflows/release.yaml for workflow syntax
 2. Test PR-to-main: merge release/* to main, verify production tag + release created
 3. Test PR-to-develop: merge feature to develop, verify RC tag (v3.0.0-rc.1)
 4. Test auto-increment: second merge to develop produces v3.0.0-rc.2
 5. Test guard: feature/* PR to main should fail with error message
 6. Test manual dispatch with each release type
 7. Raw URL verification: curl -sf https://raw.githubusercontent.com/.../vX.Y.Z/package.yaml
