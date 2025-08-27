# InstantDB Flutter Example - Deployment Guide

This guide walks you through deploying the InstantDB Flutter example app to Cloudflare Pages.

## 🚀 Quick Start

If you have everything set up already:

```bash
# Build and deploy to production
just web-deploy

# Or step by step:
just web-build
just cf-deploy
```

## 📋 Prerequisites

### 1. Cloudflare Account
- Sign up at [cloudflare.com](https://cloudflare.com)
- Navigate to the Pages section in your dashboard

### 2. Wrangler CLI
Install the Cloudflare Wrangler CLI:

```bash
# Using npm/bun
npm install -g wrangler
# or
bun install -g wrangler

# Authenticate with Cloudflare
wrangler login
```

### 3. Flutter Web Setup
Ensure Flutter web is enabled:

```bash
flutter config --enable-web
flutter doctor  # Verify web support is enabled
```

## 🏗️ Initial Setup

### 1. Create Cloudflare Pages Project

#### Option A: Via Cloudflare Dashboard
1. Go to [Cloudflare Pages](https://dash.cloudflare.com/pages)
2. Click "Create a project"
3. Choose "Direct Upload" (we'll deploy via CLI)
4. Set project name: `instantdb-flutter-demo`

#### Option B: Via Wrangler CLI
```bash
cd example
wrangler pages project create instantdb-flutter-demo
```

### 2. Configure Environment Variables

The app needs your InstantDB API ID to function. Set this up in Cloudflare Pages:

#### Via Dashboard:
1. Go to your Pages project settings
2. Navigate to "Environment variables"
3. Add: `INSTANTDB_API_ID` = `your-actual-api-id`

#### Via CLI:
```bash
# Set for production
wrangler pages secret put INSTANTDB_API_ID --project-name instantdb-flutter-demo

# Set for preview environment
wrangler pages secret put INSTANTDB_API_ID --project-name instantdb-flutter-demo --env preview
```

### 3. Update Configuration (Optional)

Edit `wrangler.toml` if you want to customize:
- Project name
- Domain settings
- Environment variables
- Security headers

## 📦 Building the App

### Development Build
```bash
just web-build-dev
```

### Production Build
```bash
just web-build
```

This creates an optimized build in `example/build/web/` with:
- Minified code
- Source maps for debugging
- Optimized assets
- Service worker for offline capability

### Local Testing
Test your build locally before deployment:

```bash
just web-serve
# Opens at http://localhost:8000
```

## 🌐 Deployment

### Production Deployment
```bash
# Full workflow (clean, build, deploy)
just web-deploy

# Or manual steps:
just web-clean
just web-build  
just cf-deploy
```

### Preview Deployment
Deploy to a preview environment:

```bash
just cf-preview
```

This creates a preview deployment that you can test before promoting to production.

## 📊 Available Commands

| Command | Description |
|---------|-------------|
| `just web-build` | Build for production with optimizations |
| `just web-build-dev` | Build for development with debugging |
| `just web-serve` | Serve built app locally on port 8000 |
| `just web-clean` | Clean build artifacts |
| `just cf-deploy` | Deploy to production |
| `just cf-preview` | Deploy to preview environment |
| `just cf-logs` | View deployment logs |
| `just cf-open` | Open deployed site in browser |
| `just web-deploy` | Complete build and deploy workflow |

## 🔧 Troubleshooting

### Build Issues

**Flutter web not enabled:**
```bash
flutter config --enable-web
flutter create --platforms web .
```

**Build fails with memory issues:**
```bash
# Increase memory for build
flutter build web --release --dart-define=--disable-dart-dev
```

### Deployment Issues

**Authentication errors:**
```bash
wrangler login
# Follow the browser authentication flow
```

**Project not found:**
```bash
# List your projects
wrangler pages project list

# Create project if it doesn't exist
wrangler pages project create instantdb-flutter-demo
```

**Environment variables not working:**
```bash
# Verify secrets are set
wrangler pages secret list --project-name instantdb-flutter-demo

# Re-add if missing
wrangler pages secret put INSTANTDB_API_ID --project-name instantdb-flutter-demo
```

### Runtime Issues

**InstantDB connection fails:**
1. Check that `INSTANTDB_API_ID` environment variable is set in Cloudflare Pages
2. Verify the API ID is correct (should be a UUID format)
3. Check the browser developer tools for CORS or network errors

**App doesn't load:**
1. Check that all Flutter web assets are included in the build
2. Verify the `base href` is set correctly
3. Check browser console for JavaScript errors

## 🚀 Advanced Configuration

### Custom Domain

1. In Cloudflare Pages, go to your project
2. Navigate to "Custom domains"
3. Add your domain (e.g., `demo.yoursite.com`)
4. Update DNS settings as instructed
5. Update URLs in `index.html` and `wrangler.toml`

### CI/CD Pipeline

For automated deployments, you can:

1. **GitHub Actions**: Cloudflare provides official GitHub Actions
2. **GitLab CI**: Use Wrangler in GitLab pipelines  
3. **Other CI**: Any CI that can run Node.js can use Wrangler

Example GitHub Action:
```yaml
name: Deploy to Cloudflare Pages
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter build web --release
      - uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          workingDirectory: example
          command: pages deploy build/web --project-name instantdb-flutter-demo
```

### Environment-Specific Builds

You can customize builds for different environments:

```bash
# Build with environment-specific config
flutter build web --release --dart-define=ENVIRONMENT=production
flutter build web --dart-define=ENVIRONMENT=staging
```

### Analytics and Monitoring

Cloudflare Pages provides built-in analytics. You can also add:
- Cloudflare Web Analytics
- Custom monitoring scripts
- Error tracking (Sentry, etc.)

## 📈 Performance Optimization

The build includes several optimizations:

1. **Code splitting**: Automatic with Flutter web
2. **Asset optimization**: Images and fonts are optimized
3. **Caching**: Proper cache headers are set in `wrangler.toml`
4. **Compression**: Cloudflare automatically compresses responses
5. **CDN**: Global distribution via Cloudflare's network

### Additional Optimizations:

```bash
# Enable web renderer optimization
flutter build web --web-renderer canvaskit --release

# Or for broader compatibility
flutter build web --web-renderer html --release
```

## 🔗 Useful Links

- [Cloudflare Pages Documentation](https://developers.cloudflare.com/pages/)
- [Wrangler CLI Documentation](https://developers.cloudflare.com/workers/wrangler/)
- [Flutter Web Deployment](https://flutter.dev/docs/deployment/web)
- [InstantDB Documentation](https://docs.instantdb.com/)

## 📝 Notes

- The app uses WebSocket connections to InstantDB, which work seamlessly through Cloudflare
- Environment variables are available at build time and runtime
- Source maps are included in production builds for debugging
- The app works offline thanks to Flutter's service worker
- All InstantDB collaborative features (cursors, presence, etc.) work in the deployed version

## 🆘 Support

If you encounter issues:

1. Check the [troubleshooting section](#🔧-troubleshooting) above
2. Review Cloudflare Pages logs: `just cf-logs`
3. Test locally first: `just web-serve`
4. Open an issue in the InstantDB Flutter repository