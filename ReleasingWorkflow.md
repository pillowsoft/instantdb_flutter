# InstantDB Flutter Release Workflow

This document provides a comprehensive guide for releasing InstantDB Flutter to both GitHub Releases and pub.dev.

## Table of Contents

1. [Pre-Release Checklist](#pre-release-checklist)
2. [Version Management](#version-management)
3. [Publishing to pub.dev](#publishing-to-pubdev)
4. [Creating GitHub Releases](#creating-github-releases)
5. [Complete Release Workflow](#complete-release-workflow)
6. [Post-Release Tasks](#post-release-tasks)
7. [Troubleshooting](#troubleshooting)

---

## Pre-Release Checklist

Before starting any release process, ensure all prerequisites are met:

### ✅ Code Quality Requirements

```bash
# 1. Run the complete quality check pipeline
just publish-workflow

# 2. Check current package status
just version-check
just publish-check

# 3. Fix any remaining issues
just publish-fix  # Auto-fixes common issues
```

**Manual checks:**
- [ ] All tests passing (`just test`)
- [ ] Static analysis clean (`just analyze`)
- [ ] Code formatted (`just format-check`)
- [ ] Documentation up to date (`just docs`)
- [ ] Example app working (`just example-run`)

### ✅ Version & Documentation

```bash
# Check current version status
just version-check
```

**Verify:**
- [ ] `pubspec.yaml` version is correct
- [ ] `CHANGELOG.md` has entry for current version
- [ ] All breaking changes documented
- [ ] Migration guide updated (if needed)

### ✅ Authentication Setup

**For pub.dev (first time only):**
- [ ] Run `dart pub login` or `flutter pub login`
- [ ] Verify access with `dart pub deps` 

**For GitHub (verify access):**
- [ ] Test with `gh auth status`
- [ ] Ensure you have push access to repository

---

## Version Management

### Semantic Versioning Guidelines

- **Patch** (`0.1.0` → `0.1.1`): Bug fixes, small improvements
- **Minor** (`0.1.0` → `0.2.0`): New features, backward compatible
- **Major** (`0.1.0` → `1.0.0`): Breaking changes

### Version Bump Process

```bash
# Choose appropriate version bump
just version-patch   # For bug fixes
just version-minor   # For new features  
just version-major   # For breaking changes

# Verify the version was updated correctly
just version-check
```

### Update Changelog

```bash
# Option 1: Auto-generate from git commits
just changelog-generate

# Option 2: Manual edit
# Edit CHANGELOG.md manually for better control
```

**Commit the version bump:**
```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "Bump version to X.Y.Z

- List key changes here
- Highlight breaking changes
- Reference any issues closed"
git push
```

---

## Publishing to pub.dev

### 🚨 Important: First Release Must Be Manual

pub.dev requires the **first version** of any package to be published manually. Automation can only be set up after the initial publish.

### Step 1: Pre-Publish Validation

```bash
# Run complete validation suite
just publish-check

# If any issues found, fix them:
just publish-fix

# Estimate your pub.dev score
just publish-score  # Aim for 130+ points
```

### Step 2: Final Dry Run

```bash
# Test publish without actually publishing
just publish-dry

# Review what will be published
# Check file list, package size, warnings
```

### Step 3: Publish to pub.dev

**Option A: Interactive Publishing (Recommended)**
```bash
just publish-interactive
```
This wizard will:
- Confirm version
- Run all checks
- Show package preview
- Ask for final confirmation

**Option B: Direct Publishing**
```bash
just publish
```

### Step 4: Verification

After successful publishing:

1. **Visit your package page:** `https://pub.dev/packages/instantdb_flutter`
2. **Check package score** (may take a few minutes to calculate)
3. **Test installation** in a new project:
   ```bash
   flutter pub add instantdb_flutter
   ```

---

## Creating GitHub Releases

### Option 1: Create Release with Auto-Generated Notes

```bash
# Creates release with automatic release notes from commits
just release-create
```

### Option 2: Create Release from Changelog

```bash
# Uses your CHANGELOG.md content for release notes
just release-from-changelog
```

### Option 3: Create Draft Release (Recommended)

```bash
# Create draft for review before publishing
just release-draft

# Review and edit at: https://github.com/your-org/instantdb_flutter/releases
# Then publish when ready
```

### Option 4: Manual Git Tag + Release

```bash
# Create and push tag manually
just tag-create

# Then create release from tag
just release-create
```

---

## Complete Release Workflow

Here's the **recommended end-to-end process** for a complete release:

### Phase 1: Preparation

```bash
# 1. Ensure clean working directory
git status  # Should be clean

# 2. Run complete validation
just publish-workflow

# 3. Fix any issues found
just publish-fix  # If needed
```

### Phase 2: Version Management

```bash
# 4. Bump version (choose appropriate type)
just version-minor  # Example for new features

# 5. Update changelog
just changelog-generate  # Or edit manually

# 6. Commit version changes
git add .
git commit -m "Release v$(grep '^version:' pubspec.yaml | cut -d' ' -f2)"
git push
```

### Phase 3: Create Git Tag

```bash
# 7. Create version tag
just tag-create
```

### Phase 4: Publish to pub.dev

```bash
# 8. Final validation
just publish-check

# 9. Publish interactively
just publish-interactive
```

### Phase 5: Create GitHub Release

```bash
# 10. Create GitHub release (choose one)
just release-from-changelog  # Uses CHANGELOG.md
# OR
just release-draft          # Review before publishing
```

### Phase 6: Verification

```bash
# 11. Verify everything worked
just release-list           # Check GitHub release
just version-check         # Verify versions match
```

Visit:
- **pub.dev**: `https://pub.dev/packages/instantdb_flutter`
- **GitHub**: `https://github.com/your-org/instantdb_flutter/releases`

---

## Post-Release Tasks

### Immediate Tasks

1. **Verify pub.dev listing**
   - Package appears in search
   - Documentation renders correctly
   - Example code works

2. **Update project documentation**
   - README installation instructions
   - Getting started guide
   - API documentation

3. **Test installation**
   ```bash
   # In a new Flutter project
   flutter pub add instantdb_flutter
   ```

### Communication

1. **Discord/Community announcements**
2. **Twitter/Social media updates**
3. **Documentation site updates**
4. **Blog post** (for major releases)

### Prepare for Next Release

```bash
# Bump to next development version if needed
just version-patch  # e.g., 1.0.0 → 1.0.1-dev

# Update CHANGELOG.md with "Unreleased" section
```

---

## Troubleshooting

### Common pub.dev Issues

**❌ "Package validation failed"**
```bash
# Run diagnostics
just publish-check

# Auto-fix common issues
just publish-fix

# Check specific error messages in output
```

**❌ "Static analysis errors"**
```bash
# View detailed errors
flutter analyze

# Fix automatically where possible
dart fix --apply lib/

# Manual fixes may be needed for some issues
```

**❌ "Authentication failed"**
```bash
# Re-authenticate with pub.dev
flutter pub logout
flutter pub login
```

**❌ "Version already exists"**
```bash
# Check current published version
# Bump version appropriately
just version-patch  # or minor/major
```

### Common GitHub Release Issues

**❌ "Tag already exists"**
```bash
# List existing tags
just tag-list

# Delete tag if needed (careful!)
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
```

**❌ "Release creation failed"**
```bash
# Check GitHub authentication
gh auth status

# Try creating draft first
just release-draft
```

### Emergency Procedures

**🚨 Need to unpublish from pub.dev?**
- Contact pub.dev support - packages cannot be unpublished automatically
- Can only retract versions within 7 days of publishing

**🚨 Need to delete GitHub release?**
```bash
# Delete release (keeps tag)
just release-delete v1.0.0

# Delete tag as well (if needed)
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
```

---

## Quick Reference Commands

| Task | Command |
|------|---------|
| **Check readiness** | `just publish-workflow` |
| **Bump version** | `just version-patch/minor/major` |
| **Publish to pub.dev** | `just publish-interactive` |
| **Create GitHub release** | `just release-from-changelog` |
| **Full workflow** | `just release-full` |
| **Fix issues** | `just publish-fix` |
| **Check status** | `just version-check` |

---

## Resources

- [pub.dev Publishing Guide](https://dart.dev/tools/pub/publishing)
- [Semantic Versioning](https://semver.org/)
- [GitHub Releases Documentation](https://docs.github.com/en/repositories/releasing-projects-on-github)
- [Flutter Package Development](https://docs.flutter.dev/development/packages-and-plugins/developing-packages)

---

**🎉 Happy releasing!** 

For questions or issues with this workflow, check the [troubleshooting section](#troubleshooting) or open an issue in the repository.