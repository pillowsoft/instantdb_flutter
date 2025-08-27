# InstantDB Flutter Documentation

[![Built with Starlight](https://astro.badg.es/v2/built-with-starlight/tiny.svg)](https://starlight.astro.build)

This is the documentation website for InstantDB Flutter - a real-time, offline-first database client for Flutter applications.

## 🚀 Project Structure

```
.
├── public/               # Static assets
│   ├── favicon.svg
│   └── .assetsignore    # Cloudflare Pages config
├── src/
│   ├── assets/
│   │   ├── logo.svg     # InstantDB logo
│   │   └── examples.json # Example links
│   ├── content/
│   │   ├── docs/        # Documentation pages
│   │   └── config.ts    # Content config
│   ├── styles/
│   │   └── custom.css   # InstantDB theme
│   └── env.d.ts
├── astro.config.mjs     # Astro + Starlight config
├── wrangler.toml        # Cloudflare deployment config
└── package.json
```

## 📚 Documentation Structure

The documentation is organized into the following sections:

- **Getting Started**: Installation and quick start guide
- **Core Concepts**: Database initialization, schema, transactions
- **Queries**: InstaQL query language and reactive queries
- **Real-time**: WebSocket sync and presence system
- **Flutter Widgets**: InstantBuilder, Watch, and other reactive widgets
- **Authentication**: User management and session handling
- **Advanced**: Performance, offline handling, troubleshooting
- **API Reference**: Complete API documentation

## 🧞 Development Commands

All commands use Bun as the package manager:

| Command         | Action                                           |
| :-------------- | :----------------------------------------------- |
| `bun install`   | Installs dependencies                            |
| `bun run dev`   | Starts local dev server at `localhost:4321`     |
| `bun run build` | Build production site to `./dist/`              |
| `bun run preview` | Preview build locally before deploying        |
| `bun run deploy` | Deploy to Cloudflare Pages                     |

## 🚀 Deployment

### Cloudflare Pages (Recommended)

This site is configured to deploy to Cloudflare Pages:

1. **Automatic Deployment**: 
   - Connect your GitHub repository to Cloudflare Pages
   - Set build command: `bun run build`
   - Set build output directory: `dist`

2. **Manual Deployment**:
   ```bash
   bun run build
   bun run deploy
   ```

### GitHub Pages

To deploy to GitHub Pages:

1. Update `astro.config.mjs` to set the correct `site` URL
2. Use the GitHub Pages deployment action
3. Set output directory to `dist`

## 🎨 Customization

### Branding

- Update colors in `src/styles/custom.css`
- Replace logo in `src/assets/logo.svg`
- Update favicon in `public/favicon.svg`

### Content

- Add new documentation pages to `src/content/docs/`
- Update navigation in `astro.config.mjs` sidebar configuration
- Modify examples in `src/assets/examples.json`

## 📝 Writing Documentation

### File Naming

- Use kebab-case for file names: `getting-started.md`
- Use folders to organize sections: `getting-started/installation.mdx`

### Frontmatter

Each documentation page should include frontmatter:

```yaml
---
title: Page Title
description: Brief description for SEO
sidebar:
  order: 1
---
```

### Components

Use Starlight components for enhanced content:

```mdx
import { Card, CardGrid, Code, Tabs, TabItem } from '@astrojs/starlight/components';

<CardGrid>
  <Card title="Feature" icon="rocket">
    Description
  </Card>
</CardGrid>
```

## 🔗 Links

- [InstantDB Flutter Repository](https://github.com/pillowsoft/instantdb_flutter)
- [InstantDB Website](https://instantdb.com)
- [Astro Documentation](https://docs.astro.build)
- [Starlight Documentation](https://starlight.astro.build)
