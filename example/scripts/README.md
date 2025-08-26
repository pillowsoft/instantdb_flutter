# InstantDB Schema Scripts

This directory contains InstantDB schema and permissions files for server-side configuration.

## Files

- `instant.schema.ts` - TypeScript schema definition for all entity types (todos, tiles, messages, etc.)
- `instant.perms.ts` - Permissions configuration for InstantDB server

## Usage

These files are managed via the justfile commands from the project root:

```bash
# Push schema to InstantDB server
just schema-push

# Pull current schema from server
just schema-pull  

# Validate schema files locally
just schema-validate

# Check schema status
just schema-status
```

## No Dependencies Required

These scripts use `npx` to run the InstantDB CLI directly without requiring local Node.js dependencies or a `package.json` file. This keeps the Flutter project clean and eliminates the need for `node_modules`.