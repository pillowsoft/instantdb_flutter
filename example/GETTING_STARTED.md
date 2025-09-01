# Getting Started with InstantDB Flutter Example

This guide will walk you through setting up the InstantDB Flutter example app with your own InstantDB cloud backend.

## Prerequisites

- Flutter SDK installed (3.8.0 or higher)
- Node.js installed (for running InstantDB CLI tools)
- An InstantDB account

## Setup Instructions

### 1. Create an InstantDB Account

1. Go to [InstantDB](https://instantdb.com) and sign up for a free account
2. Once logged in, you'll be directed to the dashboard

### 2. Create a New App

1. In the InstantDB dashboard, click **"Create App"**
2. Give your app a name (e.g., "Flutter Todo Example")
3. Once created, you'll see your app in the dashboard

### 3. Get Your App ID

1. Click on your app in the dashboard
2. Navigate to the **"App Details"** or **"Settings"** section
3. Copy your **App ID** (it looks like: `82100963-e4c0-4f02-b49b-b6fa92d64a17`)

### 4. Configure the Flutter App

1. Navigate to the example directory:
   ```bash
   cd example
   ```

2. Create a `.env` file in the `example` directory:
   ```bash
   touch .env
   ```

3. Add your App ID to the `.env` file:
   ```
   INSTANTDB_API_ID=your-app-id-here
   ```
   Replace `your-app-id-here` with the App ID you copied from the dashboard.

### 5. Set Up the Schema

The example app comes with a predefined schema that needs to be pushed to your InstantDB instance.

#### Install Dependencies

First, set up the schema management tools:

```bash
cd example/scripts
npm install
```

This will install the InstantDB CLI and SDK needed for schema management.

#### Configure Schema Environment

Create a `.env` file in the `scripts` directory:

```bash
echo "INSTANT_APP_ID=your-app-id-here" > .env
```

Replace `your-app-id-here` with your App ID.

#### Push the Schema

Now push the schema to InstantDB:

```bash
npx instant-cli push
```

You should see output like:
```
Checking for an Instant SDK...
Found @instantdb/react in your package.json.
Planning schema...
Uploading schema...
Schema uploaded successfully!
Planning perms...
Uploading perms...
Perms uploaded successfully!
```

If you see "No schema changes detected. Skipping." - your schema is already up to date!

### 6. Verify Your Setup

#### Check Schema in Dashboard

1. Go to your InstantDB dashboard
2. Click on your app
3. Navigate to the **"Explorer"** or **"Schema"** tab
4. You should see the following entities:
   - `todos` - For the todo list feature
   - `tiles` - For the collaborative tile game
   - `messages` - For the chat feature

#### Run the Example App

1. Navigate back to the example directory:
   ```bash
   cd ../
   ```

2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   # For iOS
   flutter run -d ios

   # For Android
   flutter run -d android

   # For Web
   flutter run -d chrome

   # For macOS
   flutter run -d macos
   ```

4. The app should launch and connect to your InstantDB instance

#### Verify Data Persistence

1. Add a few todos in the app
2. Go to your InstantDB dashboard
3. Click on your app and navigate to **"Explorer"**
4. Select the `todos` entity
5. You should see your todos appear in real-time!

## Using the Justfile (Alternative)

If you prefer using the provided automation, you can use the `just` commands from the project root:

```bash
# View available schema commands
just --list | grep schema

# Push schema (from project root)
just schema-push

# Check schema status
just schema-status
```

## Troubleshooting

### "Couldn't find your root directory" Error

Make sure you have a `package.json` file in the `scripts` directory. If not, create one:

```bash
cd example/scripts
npm init -y
npm install @instantdb/react
```

### Schema Not Appearing in Dashboard

1. Double-check your App ID is correct in both `.env` files
2. Ensure you're in the `example/scripts` directory when running `npx instant-cli push`
3. Try pulling the current schema to verify connection:
   ```bash
   npx instant-cli pull schema
   ```

### Data Not Persisting

1. Check the console logs in your Flutter app for connection status
2. Verify you see "WebSocket connected" and "authenticated successfully"
3. Ensure your `.env` file in the `example` directory has the correct App ID
4. Check the InstantDB dashboard Explorer to see if data is reaching the cloud

### Permission Denied Errors

The example app has open permissions for demonstration purposes. If you modify the permissions file (`instant.perms.ts`), make sure to push the changes:

```bash
cd example/scripts
npx instant-cli push
```

## What's Included in the Schema

The example app schema includes:

- **System Entities** (managed by InstantDB):
  - `$users` - User authentication records
  - `$files` - File storage metadata

- **Application Entities**:
  - `todos` - Todo items with text, completed status, and timestamps
  - `tiles` - Collaborative tile game data with colors and positions
  - `messages` - Chat messages with user info and timestamps

## Next Steps

- Explore the example app features:
  - **Todos Page**: Create, update, and delete todos with real-time sync
  - **Tile Game**: Collaborative painting with multiple users
  - **Chat**: Real-time messaging with typing indicators
  - **Presence**: See who's online and their cursor positions

- Try opening the app on multiple devices to see real-time synchronization
- Experiment with going offline and seeing how changes sync when reconnected
- Check out the [InstantDB documentation](https://instantdb.com/docs) for more advanced features

## Support

- [InstantDB Documentation](https://instantdb.com/docs)
- [Flutter Package Documentation](https://pub.dev/packages/instantdb_flutter)
- [GitHub Issues](https://github.com/your-repo/instantdb_flutter/issues)