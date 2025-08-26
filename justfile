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

# === PUBLISHING & RELEASE TASKS ===

# Dry run for package publishing
publish-dry:
    @echo "🚀 Running publish dry run..."
    flutter pub publish --dry-run

# Publish package to pub.dev
publish:
    @echo "🚀 Publishing to pub.dev..."
    flutter pub publish

# Bump version number
version-bump type="patch":
    @echo "📈 Bumping {{type}} version..."
    @echo "Manual task: Update version in pubspec.yaml"

# Update changelog
changelog:
    @echo "📝 Updating changelog..."
    @echo "Manual task: Update CHANGELOG.md with recent changes"

# Full release process
release: check test-coverage docs publish-dry
    @echo "🎉 Ready for release! Run 'just publish' to complete."

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
    cd example && bunx instant-cli push --app $$(grep INSTANTDB_API_ID .env | cut -d= -f2) --yes
    @echo "✅ Schema pushed successfully"

# Pull current schema from InstantDB server
schema-pull:
    @echo "📥 Pulling schema from InstantDB server..."
    cd example && bunx instant-cli pull-schema --app $$(grep INSTANTDB_API_ID .env | cut -d= -f2)
    @echo "✅ Schema pulled successfully"

# Validate local schema file without pushing
schema-validate:
    @echo "🔍 Validating schema files..."
    cd example && bun run schema:validate
    @echo "✅ Schema validation completed"

# Install schema dependencies
schema-deps:
    @echo "📦 Installing schema dependencies..."
    cd example && bun install
    @echo "✅ Schema dependencies installed"

# Show schema status
schema-status:
    @echo "📊 Schema status:"
    @echo "Schema file: example/instant.schema.ts"
    @echo "Permissions file: example/instant.perms.ts"
    @test -f example/instant.schema.ts && echo "✅ Schema file exists" || echo "❌ Schema file missing"
    @test -f example/instant.perms.ts && echo "✅ Permissions file exists" || echo "❌ Permissions file missing"
    @test -f example/package.json && echo "✅ Package.json exists" || echo "❌ Package.json missing"

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