# InstantDB Flutter Package Development Tasks
# Use `just --list` to see all available tasks

# Default task - show help
default:
    @just --list

# === CORE DEVELOPMENT TASKS ===

# Install all dependencies for the package and example app
install:
    @echo "📦 Installing dependencies..."
    flutter pub get
    cd example && flutter pub get
    @echo "✅ Dependencies installed"

# Clean build artifacts and caches
clean:
    @echo "🧹 Cleaning build artifacts..."
    flutter clean
    cd example && flutter clean
    rm -rf .dart_tool
    rm -rf example/.dart_tool
    rm -rf build
    rm -rf example/build
    @echo "✅ Clean completed"

# Clean and rebuild everything
rebuild: clean install
    @echo "🔄 Rebuild completed"

# Run code generation (json_serializable, etc.)
generate:
    @echo "⚙️ Running code generation..."
    flutter packages pub run build_runner build --delete-conflicting-outputs
    @echo "✅ Code generation completed"

# Watch for changes and run tests automatically
watch:
    @echo "👀 Watching for changes..."
    flutter test --reporter=expanded --coverage

# === TESTING TASKS ===

# Run all tests
test:
    @echo "🧪 Running all tests..."
    flutter test --reporter=expanded

# Run all tests with coverage report
test-coverage:
    @echo "🧪 Running tests with coverage..."
    flutter test --coverage
    @echo "📊 Coverage report generated in coverage/lcov.info"

# Run unit tests only (excluding integration tests)
test-unit:
    @echo "🧪 Running unit tests..."
    flutter test test/ --exclude-tags=integration

# Run integration tests only
test-integration:
    @echo "🧪 Running integration tests..."
    flutter test test/ --tags=integration

# Watch mode for tests
test-watch:
    @echo "👀 Watching tests..."
    flutter test --reporter=expanded --coverage

# Run a specific test file
test-specific file:
    @echo "🧪 Running specific test: {{file}}"
    flutter test {{file}} --reporter=expanded

# Run performance/benchmark tests
test-perf:
    @echo "⚡ Running performance tests..."
    flutter test test/ --plain-name="Performance Tests"

# === QUALITY & ANALYSIS TASKS ===

# Run static analysis
analyze:
    @echo "🔍 Running static analysis..."
    flutter analyze --fatal-infos

# Format all Dart code
format:
    @echo "✨ Formatting code..."
    dart format lib/ test/ example/lib/

# Check code formatting without making changes
format-check:
    @echo "🔍 Checking code format..."
    dart format --output=none --set-exit-if-changed lib/ test/ example/lib/

# Run linter
lint:
    @echo "📏 Running linter..."
    flutter analyze --fatal-infos --fatal-warnings

# Auto-fix linting issues where possible
fix:
    @echo "🔧 Auto-fixing issues..."
    dart fix --apply

# Run all quality checks
check: format-check analyze test
    @echo "✅ All checks passed!"

# === EXAMPLE APP TASKS ===

# Run the example app (default device)
example-run:
    @echo "📱 Running example app..."
    cd example && flutter run

# Run example app on iOS simulator
example-ios:
    @echo "📱 Running example app on iOS..."
    cd example && flutter run -d ios

# Run example app on Android emulator
example-android:
    @echo "📱 Running example app on Android..."
    cd example && flutter run -d android

# Run example app on web
example-web:
    @echo "🌐 Running example app on web..."
    cd example && flutter run -d chrome

# Run example app on macOS
example-macos:
    @echo "💻 Running example app on macOS..."
    cd example && flutter run -d macos

# Build example app for all platforms
example-build:
    @echo "🏗️ Building example app for all platforms..."
    cd example && flutter build apk
    cd example && flutter build ios --no-codesign
    cd example && flutter build web
    cd example && flutter build macos

# === WEB BUILD & DEPLOYMENT TASKS ===

# Build example app for web (release mode)
web-build:
    @echo "🌐 Building web app for release..."
    cd example && flutter build web --release --source-maps
    @echo "✅ Web build completed in example/build/web/"

# Build example app for web (development mode)
web-build-dev:
    @echo "🌐 Building web app for development..."
    cd example && flutter build web --source-maps
    @echo "✅ Development web build completed"

# Serve built web app locally
web-serve:
    @echo "🌐 Serving web app locally at http://localhost:8000"
    cd example/build/web && python3 -m http.server 8000

# Clean web build artifacts
web-clean:
    @echo "🧹 Cleaning web build artifacts..."
    rm -rf example/build/web
    @echo "✅ Web build artifacts cleaned"

# Deploy to Cloudflare Pages (production)
cf-deploy:
    @echo "🚀 Deploying to Cloudflare Pages..."
    just web-build
    cd example && wrangler pages deploy build/web --project-name instantdb-flutter-demo
    @echo "✅ Deployed to production!"

# Deploy preview to Cloudflare Pages
cf-preview:
    @echo "🚀 Deploying preview to Cloudflare Pages..."
    just web-build
    cd example && wrangler pages deploy build/web --project-name instantdb-flutter-demo --compatibility-flags="nodejs_compat" --env preview
    @echo "✅ Preview deployed!"

# Tail Cloudflare Pages deployment logs
cf-logs:
    @echo "📋 Tailing Cloudflare Pages logs..."
    cd example && wrangler pages deployment tail --project-name instantdb-flutter-demo

# Open deployed Cloudflare Pages site
cf-open:
    @echo "🌐 Opening Cloudflare Pages site..."
    open https://instantdb-flutter-demo.pages.dev

# Full web deployment workflow
web-deploy: web-clean web-build cf-deploy
    @echo "🎉 Full web deployment completed!"

# === DOCUMENTATION TASKS ===

# Generate API documentation
docs:
    @echo "📚 Generating documentation..."
    dart doc

# Serve documentation locally
docs-serve: docs
    @echo "🌐 Serving documentation at http://localhost:8080"
    cd doc/api && python3 -m http.server 8080

# Update README with latest examples
readme-update:
    @echo "📝 Updating README..."
    @echo "Manual task: Update README.md with latest API examples"

# === WEBSITE DOCUMENTATION TASKS ===

# Install website dependencies
website-install:
    @echo "📦 Installing website dependencies..."
    cd website && bun install
    @echo "✅ Website dependencies installed"

# Start website development server
website-dev:
    @echo "🌐 Starting website development server..."
    cd website && bun run dev

# Build website for production
website-build:
    @echo "🏗️ Building website for production..."
    cd website && bun run build
    @echo "✅ Website built in website/dist/"

# Preview built website locally
website-preview: website-build
    @echo "👀 Previewing website locally..."
    cd website && bun run preview

# Deploy website to Cloudflare Pages
website-deploy: website-build
    @echo "🚀 Deploying website to Cloudflare Pages..."
    cd website && bun run deploy
    @echo "✅ Website deployed to production!"

# Clean website build artifacts
website-clean:
    @echo "🧹 Cleaning website build artifacts..."
    rm -rf website/dist
    rm -rf website/.astro
    rm -rf website/node_modules/.astro
    @echo "✅ Website build artifacts cleaned"

# Full website development setup
website-setup: website-install
    @echo "🚀 Website development environment ready!"

# Check website build without deploying
website-check:
    @echo "🔍 Checking website build..."
    cd website && bun run build
    @echo "✅ Website build check completed"

# Open deployed website
website-open:
    @echo "🌐 Opening deployed website..."
    open https://instantdb-flutter-docs.pages.dev

# === PUBLISHING & RELEASE TASKS ===

# Complete pre-publish validation
publish-check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Running complete pre-publish validation..."
    echo ""
    
    # Check static analysis
    echo "1. Static Analysis Check"
    if flutter analyze --fatal-infos 2>/dev/null; then
        echo "✅ Static analysis passed"
    else
        echo "❌ Static analysis failed - fix issues before publishing"
        echo "💡 Run 'just publish-fix' to auto-fix some issues"
        exit 1
    fi
    echo ""
    
    # Check LICENSE file
    echo "2. LICENSE File Check"
    if [ -f LICENSE ]; then
        if grep -q "TODO" LICENSE; then
            echo "❌ LICENSE file contains placeholder text"
            exit 1
        else
            echo "✅ LICENSE file looks good"
        fi
    else
        echo "❌ LICENSE file missing"
        exit 1
    fi
    echo ""
    
    # Check version consistency
    echo "3. Version Consistency Check"
    just version-check
    echo ""
    
    # Check for gitignored files
    echo "4. Gitignored Files Check"
    if flutter pub publish --dry-run 2>&1 | grep -q "gitignored"; then
        echo "⚠️  Found gitignored files that would be published"
        echo "💡 Consider creating .pubignore file"
    else
        echo "✅ No problematic gitignored files"
    fi
    echo ""
    
    # Check pubspec metadata
    echo "5. Pubspec Metadata Check"
    if grep -q "^description:" pubspec.yaml && grep -q "^homepage:" pubspec.yaml; then
        echo "✅ Basic pubspec metadata present"
    else
        echo "❌ Missing required pubspec metadata"
        exit 1
    fi
    echo ""
    
    echo "✅ All pre-publish checks passed!"

# Auto-fix common publishing issues
publish-fix:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔧 Auto-fixing publishing issues..."
    echo ""
    
    echo "1. Formatting code..."
    just format
    echo ""
    
    echo "2. Removing unused imports and fixing lints..."
    dart fix --apply lib/
    echo ""
    
    echo "3. Re-running analysis..."
    flutter analyze --fatal-warnings
    echo ""
    
    echo "✅ Auto-fixes completed!"
    echo "💡 Run 'just publish-check' to validate all issues are resolved"

# Estimate pub.dev package score
publish-score:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📊 Estimating pub.dev package score..."
    echo ""
    
    # Install pana if not available
    if ! command -v pana &> /dev/null; then
        echo "📦 Installing pana (pub.dev scoring tool)..."
        dart pub global activate pana
    fi
    echo ""
    
    echo "🔍 Running pana analysis..."
    pana --no-warning .
    echo ""
    
    echo "💡 This score estimation helps predict your pub.dev score"
    echo "🎯 Aim for 130+ points for a good score"

# Interactive publishing wizard
publish-interactive:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🧙 Interactive Publishing Wizard"
    echo "================================="
    echo ""
    
    # Get current version
    VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    echo "📋 Current version: $VERSION"
    echo ""
    
    # Confirm version
    read -p "Is this the correct version to publish? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Publishing cancelled"
        echo "💡 Update version in pubspec.yaml first"
        exit 1
    fi
    echo ""
    
    # Run checks
    echo "🔍 Running pre-publish checks..."
    if just publish-check; then
        echo "✅ All checks passed!"
    else
        echo "❌ Checks failed - fix issues before continuing"
        exit 1
    fi
    echo ""
    
    # Show what will be published
    echo "📦 Package contents preview:"
    flutter pub publish --dry-run | head -30
    echo ""
    
    # Final confirmation
    echo "⚠️  Ready to publish to pub.dev!"
    read -p "Continue with publishing? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        flutter pub publish
        echo "🎉 Package published successfully!"
        echo "🌐 View at: https://pub.dev/packages/instantdb_flutter"
    else
        echo "❌ Publishing cancelled"
    fi

# Semantic version bumping helpers
version-patch:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📈 Bumping patch version..."
    
    # Get current version
    CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    
    # Parse version parts
    IFS='.' read -ra PARTS <<< "$CURRENT"
    MAJOR=${PARTS[0]}
    MINOR=${PARTS[1]}
    PATCH=${PARTS[2]%+*}  # Remove build number if present
    
    # Increment patch
    NEW_PATCH=$((PATCH + 1))
    NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
    
    echo "📋 Current: $CURRENT"
    echo "📋 New: $NEW_VERSION"
    
    # Update pubspec.yaml
    sed -i.bak "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
    rm pubspec.yaml.bak
    
    echo "✅ Version updated to $NEW_VERSION"

version-minor:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📈 Bumping minor version..."
    
    # Get current version
    CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    
    # Parse version parts
    IFS='.' read -ra PARTS <<< "$CURRENT"
    MAJOR=${PARTS[0]}
    MINOR=${PARTS[1]}
    
    # Increment minor, reset patch
    NEW_MINOR=$((MINOR + 1))
    NEW_VERSION="$MAJOR.$NEW_MINOR.0"
    
    echo "📋 Current: $CURRENT"
    echo "📋 New: $NEW_VERSION"
    
    # Update pubspec.yaml
    sed -i.bak "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
    rm pubspec.yaml.bak
    
    echo "✅ Version updated to $NEW_VERSION"

version-major:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📈 Bumping major version..."
    
    # Get current version
    CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    
    # Parse version parts
    IFS='.' read -ra PARTS <<< "$CURRENT"
    MAJOR=${PARTS[0]}
    
    # Increment major, reset minor and patch
    NEW_MAJOR=$((MAJOR + 1))
    NEW_VERSION="$NEW_MAJOR.0.0"
    
    echo "📋 Current: $CURRENT"
    echo "📋 New: $NEW_VERSION"
    
    # Update pubspec.yaml
    sed -i.bak "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
    rm pubspec.yaml.bak
    
    echo "✅ Version updated to $NEW_VERSION"

# Generate changelog from git commits
changelog-generate:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📝 Generating changelog from git history..."
    
    # Get current version
    VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    
    # Get last tag or first commit
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
    
    echo "📋 Generating changelog for version $VERSION since $LAST_TAG"
    echo ""
    
    # Generate changelog entry
    CHANGELOG_ENTRY=$(mktemp)
    echo "## $VERSION ($(date +%Y-%m-%d))" > "$CHANGELOG_ENTRY"
    echo "" >> "$CHANGELOG_ENTRY"
    
    # Get commits since last tag
    git log --oneline --pretty=format:"- %s" "$LAST_TAG"..HEAD >> "$CHANGELOG_ENTRY"
    echo "" >> "$CHANGELOG_ENTRY"
    echo "" >> "$CHANGELOG_ENTRY"
    
    # Prepend to CHANGELOG.md
    if [ -f CHANGELOG.md ]; then
        cat CHANGELOG.md >> "$CHANGELOG_ENTRY"
    fi
    mv "$CHANGELOG_ENTRY" CHANGELOG.md
    
    echo "✅ Changelog updated with $VERSION entries"
    echo "💡 Edit CHANGELOG.md to improve the generated entries"

# Dry run for package publishing
publish-dry:
    @echo "🚀 Running publish dry run..."
    flutter pub publish --dry-run

# Publish package to pub.dev
publish:
    @echo "🚀 Publishing to pub.dev..."
    flutter pub publish

# Bump version number (deprecated - use version-patch/minor/major)
version-bump type="patch":
    @echo "📈 Bumping {{type}} version..."
    @echo "⚠️  Deprecated: Use 'just version-{{type}}' instead"
    @just version-{{type}}

# Update changelog (deprecated - use changelog-generate)
changelog:
    @echo "📝 Updating changelog..."
    @echo "⚠️  Deprecated: Use 'just changelog-generate' instead"
    @just changelog-generate

# Complete publishing workflow
publish-workflow:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🚀 Complete Publishing Workflow"
    echo "==============================="
    echo ""
    
    # Step 1: Pre-publish validation
    echo "Step 1: Pre-publish validation"
    just publish-check
    echo ""
    
    # Step 2: Run tests
    echo "Step 2: Running tests..."
    just test
    echo ""
    
    # Step 3: Build documentation
    echo "Step 3: Building documentation..."
    just docs
    echo ""
    
    # Step 4: Dry run
    echo "Step 4: Publish dry run..."
    just publish-dry
    echo ""
    
    echo "✅ All workflow checks passed!"
    echo ""
    echo "🎯 Ready for publishing. Choose next step:"
    echo "   • just publish-interactive  - Interactive publishing wizard"
    echo "   • just publish             - Direct publish to pub.dev"
    echo "   • just tag-create          - Create version tag first"
    echo "   • just release-create      - Create GitHub release"

# Full release process (maintained for compatibility)
release: check test-coverage docs publish-dry
    @echo "🎉 Ready for release! Run 'just publish-workflow' for the complete flow."

# === GITHUB RELEASES ===

# Get current version from pubspec.yaml
_get-version:
    @grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' '

# Create a new GitHub release (interactive)
release-create:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🚀 Creating GitHub release..."
    
    # Get current version
    VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    TAG="v$VERSION"
    
    echo "📋 Version: $VERSION"
    echo "🏷️  Tag: $TAG"
    echo ""
    
    # Create release with auto-generated notes
    gh release create "$TAG" \
        --title "v$VERSION" \
        --generate-notes \
        --latest
    
    echo "✅ Release $TAG created successfully!"
    echo "🌐 View at: https://github.com/$(gh repo view --json owner,name --template '{.owner.login}/{.name}')/releases"

# Create a draft release for review
release-draft:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📝 Creating draft release..."
    
    VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    TAG="v$VERSION"
    
    echo "📋 Version: $VERSION"
    echo "🏷️  Tag: $TAG"
    echo ""
    
    gh release create "$TAG" \
        --title "v$VERSION" \
        --generate-notes \
        --draft
    
    echo "✅ Draft release $TAG created!"
    echo "📝 Edit at: https://github.com/$(gh repo view --json owner,name --template '{.owner.login}/{.name}')/releases"

# Create release using CHANGELOG.md notes
release-from-changelog:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📚 Creating release from CHANGELOG..."
    
    VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    TAG="v$VERSION"
    
    echo "📋 Version: $VERSION"
    echo "🏷️  Tag: $TAG"
    echo ""
    
    # Extract notes from CHANGELOG for current version
    if [ ! -f CHANGELOG.md ]; then
        echo "❌ CHANGELOG.md not found"
        exit 1
    fi
    
    # Create temporary notes file
    NOTES_FILE=$(mktemp)
    trap "rm -f $NOTES_FILE" EXIT
    
    # Extract changelog section for current version
    awk "/^## $VERSION/ {flag=1; next} /^## / {flag=0} flag" CHANGELOG.md > "$NOTES_FILE"
    
    if [ ! -s "$NOTES_FILE" ]; then
        echo "⚠️  No changelog entry found for version $VERSION"
        echo "📝 Using auto-generated notes instead..."
        gh release create "$TAG" \
            --title "v$VERSION" \
            --generate-notes \
            --latest
    else
        echo "📝 Using changelog notes for release..."
        gh release create "$TAG" \
            --title "v$VERSION" \
            --notes-file "$NOTES_FILE" \
            --latest
    fi
    
    echo "✅ Release $TAG created with changelog notes!"

# Create a pre-release (beta/alpha)
release-prerelease:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🧪 Creating pre-release..."
    
    VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    TAG="v$VERSION"
    
    echo "📋 Version: $VERSION"
    echo "🏷️  Tag: $TAG"
    echo ""
    
    gh release create "$TAG" \
        --title "v$VERSION (Pre-release)" \
        --generate-notes \
        --prerelease
    
    echo "✅ Pre-release $TAG created!"
    echo "🧪 This release is marked as pre-release and won't be marked as 'latest'"

# List recent releases
release-list:
    @echo "📋 Recent releases:"
    @gh release list --limit 10

# Delete a release (with confirmation)
release-delete tag:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "⚠️  About to delete release: {{tag}}"
    echo "🗑️  This will delete the release but keep the git tag"
    echo ""
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        gh release delete "{{tag}}" --yes
        echo "✅ Release {{tag}} deleted"
    else
        echo "❌ Deletion cancelled"
    fi

# Create and push a version tag
tag-create:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🏷️  Creating version tag..."
    
    VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    TAG="v$VERSION"
    
    echo "📋 Version: $VERSION"
    echo "🏷️  Tag: $TAG"
    echo ""
    
    # Check if tag already exists
    if git tag --list | grep -q "^$TAG$"; then
        echo "⚠️  Tag $TAG already exists"
        exit 1
    fi
    
    # Create annotated tag with version info
    git tag -a "$TAG" -m "Release version $VERSION"
    git push origin "$TAG"
    
    echo "✅ Tag $TAG created and pushed"

# List all tags
tag-list:
    @echo "🏷️  All version tags:"
    @git tag --list --sort=-version:refname

# Check version consistency across files
version-check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Checking version consistency..."
    
    # Get version from pubspec.yaml
    PUBSPEC_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
    echo "📋 pubspec.yaml: $PUBSPEC_VERSION"
    
    # Check if CHANGELOG has entry for this version
    if [ -f CHANGELOG.md ]; then
        if grep -q "^## $PUBSPEC_VERSION" CHANGELOG.md; then
            echo "✅ CHANGELOG.md: Found entry for $PUBSPEC_VERSION"
        else
            echo "⚠️  CHANGELOG.md: No entry found for $PUBSPEC_VERSION"
        fi
    else
        echo "⚠️  CHANGELOG.md: File not found"
    fi
    
    # Check git tags
    TAG="v$PUBSPEC_VERSION"
    if git tag --list | grep -q "^$TAG$"; then
        echo "✅ Git tag: $TAG exists"
    else
        echo "ℹ️  Git tag: $TAG does not exist yet"
    fi
    
    echo ""
    echo "📋 Current version: $PUBSPEC_VERSION"

# Complete release workflow
release-full:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🚀 Starting complete release workflow..."
    echo ""
    
    # Step 1: Check version consistency
    echo "Step 1: Version consistency check"
    just version-check
    echo ""
    
    # Step 2: Run tests
    echo "Step 2: Running tests..."
    just test
    echo ""
    
    # Step 3: Run static analysis
    echo "Step 3: Static analysis..."
    just analyze
    echo ""
    
    # Step 4: Check formatting
    echo "Step 4: Format check..."
    just format-check
    echo ""
    
    # Step 5: Test coverage
    echo "Step 5: Coverage check..."
    just test-coverage
    echo ""
    
    # Step 6: Build documentation
    echo "Step 6: Building documentation..."
    just docs
    echo ""
    
    # Step 7: Publish dry run
    echo "Step 7: Publish dry run..."
    just publish-dry
    echo ""
    
    echo "✅ All checks passed!"
    echo ""
    echo "🎯 Ready to create release. Choose next step:"
    echo "   • just tag-create          - Create version tag"
    echo "   • just release-create      - Create GitHub release"
    echo "   • just release-draft       - Create draft release"
    echo "   • just publish            - Publish to pub.dev"

# === DATABASE & DEBUGGING TASKS ===

# Clean all local test databases
db-clean:
    @echo "🗄️ Cleaning local databases..."
    find . -name "*.db" -type f -delete
    find . -name "test_db_*" -type d -exec rm -rf {} + 2>/dev/null || true
    @echo "✅ Local databases cleaned"

# Show debug information
debug-info:
    @echo "🐛 Debug information:"
    @echo "Flutter version:"
    flutter --version
    @echo "\nDart version:"
    dart --version
    @echo "\nInstalled devices:"
    flutter devices

# Show logs from example app
logs:
    @echo "📋 Showing logs (run example app first)..."
    cd example && flutter logs

# === CI/CD TASKS ===

# Run complete CI pipeline locally
ci: clean install generate check test-coverage
    @echo "✅ CI pipeline completed successfully!"

# Simulate GitHub Actions locally (requires act)
github-actions:
    @echo "🔄 Running GitHub Actions locally..."
    act -P ubuntu-latest=nektos/act-environments-ubuntu:18.04

# === UTILITY TASKS ===

# Upgrade all dependencies
deps-upgrade:
    @echo "⬆️ Upgrading dependencies..."
    flutter pub upgrade
    cd example && flutter pub upgrade

# Check for outdated dependencies
deps-outdated:
    @echo "📊 Checking for outdated packages..."
    flutter pub deps
    flutter pub outdated

# Show all TODOs in the codebase
todo:
    @echo "📝 TODOs in codebase:"
    grep -r "TODO\|FIXME\|HACK" lib/ test/ --include="*.dart" || echo "No TODOs found!"

# Show package statistics
stats:
    @echo "📊 Package statistics:"
    @echo "Lines of code:"
    find lib/ -name "*.dart" -exec wc -l {} + | tail -1
    @echo "Test files:"
    find test/ -name "*_test.dart" | wc -l
    @echo "Total files:"
    find lib/ test/ -name "*.dart" | wc -l

# Run security audit
security:
    @echo "🔒 Running security audit..."
    flutter pub deps
    @echo "Manual: Review dependencies for security issues"

# === DEVELOPMENT WORKFLOW SHORTCUTS ===

# Quick development setup
dev-setup: clean install generate
    @echo "🚀 Development environment ready!"

# Pre-commit checks
pre-commit: format check
    @echo "✅ Pre-commit checks passed!"

# Quick test cycle
quick-test: format test-unit
    @echo "⚡ Quick test cycle completed!"

# Full quality gate
quality-gate: clean install generate format-check analyze test-coverage
    @echo "🏆 Quality gate passed!"

# Setup everything (package and website)
full-setup: dev-setup website-setup
    @echo "🎉 Full development environment ready!"

# Website development workflow
website-workflow: website-clean website-install website-build website-preview
    @echo "🌐 Website workflow completed!"

# === BENCHMARKING TASKS ===

# Run performance benchmarks
benchmark:
    @echo "⚡ Running benchmarks..."
    flutter test test/ --plain-name="Performance Tests" --reporter=json > benchmark_results.json
    @echo "📊 Benchmark results saved to benchmark_results.json"

# Profile memory usage
profile-memory:
    @echo "💾 Profiling memory usage..."
    cd example && flutter run --profile --trace-startup

# === MAINTENANCE TASKS ===

# Update copyright headers
update-copyright:
    @echo "©️ Updating copyright headers..."
    @echo "Manual task: Update copyright headers in source files"

# Clean up old artifacts
cleanup:
    @echo "🧹 Cleaning up old artifacts..."
    find . -name ".DS_Store" -delete
    find . -name "*.log" -delete
    find . -name "pubspec.lock" -path "*/example/*" -delete

# Validate project structure
validate:
    @echo "✅ Validating project structure..."
    @test -f pubspec.yaml || (echo "❌ Missing pubspec.yaml" && exit 1)
    @test -f lib/instantdb_flutter.dart || (echo "❌ Missing main library file" && exit 1)
    @test -d test/ || (echo "❌ Missing test directory" && exit 1)
    @test -f example/pubspec.yaml || (echo "❌ Missing example app" && exit 1)
    @echo "✅ Project structure is valid"

# === INSTANTDB SCHEMA MANAGEMENT ===

# Push schema and permissions to InstantDB server
schema-push:
    @echo "🚀 Pushing schema to InstantDB server..."
    cd example/scripts && npx instant-cli@latest push --app $$(grep INSTANTDB_API_ID ../.env | cut -d= -f2) --yes
    @echo "✅ Schema pushed successfully"

# Pull current schema from InstantDB server
schema-pull:
    @echo "📥 Pulling schema from InstantDB server..."
    cd example/scripts && npx instant-cli@latest pull-schema --app $$(grep INSTANTDB_API_ID ../.env | cut -d= -f2)
    @echo "✅ Schema pulled successfully"

# Validate local schema file without pushing
schema-validate:
    @echo "🔍 Validating schema files..."
    cd example/scripts && npx typescript@latest --noEmit instant.schema.ts
    @echo "✅ Schema validation completed"

# Show schema status
schema-status:
    @echo "📊 Schema status:"
    @echo "Schema file: example/scripts/instant.schema.ts"
    @echo "Permissions file: example/scripts/instant.perms.ts"
    @test -f example/scripts/instant.schema.ts && echo "✅ Schema file exists" || echo "❌ Schema file missing"
    @test -f example/scripts/instant.perms.ts && echo "✅ Permissions file exists" || echo "❌ Permissions file missing"
    @echo "✅ Using npx - no Node.js dependencies required"

# === HELP TASKS ===

# Show available Flutter devices
devices:
    @echo "📱 Available devices:"
    flutter devices

# Show package information
info:
    @echo "📦 Package information:"
    flutter pub deps --style=tree

# Show development tips
tips:
    @echo "💡 Development tips:"
    @echo "• Run 'just watch' for continuous testing"
    @echo "• Use 'just pre-commit' before committing"
    @echo "• Run 'just ci' to simulate CI locally"
    @echo "• Use 'just example-web' for quick browser testing"
    @echo "• Check 'just todo' for outstanding tasks"
    @echo "• Use 'just website-dev' to work on documentation"
    @echo "• Run 'just website-deploy' to publish docs"
    @echo "• Use 'just full-setup' for complete environment setup"