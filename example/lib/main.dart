import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';
import 'package:instantdb_flutter/src/core/logging_config.dart';

// Import all example pages
import 'pages/todos_page.dart';
import 'pages/auth_page.dart';
import 'pages/cursors_page.dart';
import 'pages/custom_cursors_page.dart';
import 'pages/reactions_page.dart';
import 'pages/typing_page.dart';
import 'pages/avatars_page.dart';
import 'pages/tile_game_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: '.env');
  
  runApp(const InstantDBExamplesApp());
}

class InstantDBExamplesApp extends StatelessWidget {
  const InstantDBExamplesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstantDB Examples',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ExamplesRootScreen(),
    );
  }
}

class ExamplesRootScreen extends StatefulWidget {
  const ExamplesRootScreen({super.key});

  @override
  State<ExamplesRootScreen> createState() => _ExamplesRootScreenState();
}

class _ExamplesRootScreenState extends State<ExamplesRootScreen> {
  InstantDB? _db;
  bool _isLoading = true;
  String? _error;
  bool _debugEnabled = true; // Default to debug enabled

  @override
  void initState() {
    super.initState();
    _loadDebugPreferenceAndInitialize();
  }

  Future<void> _loadDebugPreferenceAndInitialize() async {
    try {
      // Load debug preference first
      final prefs = await SharedPreferences.getInstance();
      _debugEnabled = prefs.getBool('debug_enabled') ?? true;
      
      // Then initialize DB with the loaded preference
      await _initializeDB();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeDB() async {
    try {
      final appId = dotenv.env['INSTANTDB_API_ID']!;
      
      _db = await InstantDB.init(
        appId: appId,
        config: InstantConfig(
          syncEnabled: true, // Enable real-time sync
          verboseLogging: _debugEnabled, // Use the debug preference
        ),
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleDebug() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _debugEnabled = !_debugEnabled;
    });
    await prefs.setBool('debug_enabled', _debugEnabled);
    
    // Update logging level dynamically
    InstantDBLogging.updateLogLevel(_debugEnabled ? Level.FINE : Level.WARNING);
    
    // Show feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_debugEnabled ? 'Debug logging enabled' : 'Debug logging disabled'),
          duration: const Duration(seconds: 2),
          backgroundColor: _debugEnabled ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  @override
  void dispose() {
    _db?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to initialize InstantDB',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _isLoading = true;
                  });
                  _initializeDB();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return InstantProvider(
      db: _db!,
      child: ExamplesNavigationScreen(
        debugEnabled: _debugEnabled,
        onToggleDebug: _toggleDebug,
      ),
    );
  }
}

class ExamplesNavigationScreen extends StatefulWidget {
  final bool debugEnabled;
  final VoidCallback onToggleDebug;
  
  const ExamplesNavigationScreen({
    super.key,
    required this.debugEnabled,
    required this.onToggleDebug,
  });

  @override
  State<ExamplesNavigationScreen> createState() => _ExamplesNavigationScreenState();
}

class _ExamplesNavigationScreenState extends State<ExamplesNavigationScreen> {
  int _selectedIndex = 0;
  String? _userIdSuffix;

  static const List<_ExampleConfig> _examples = [
    _ExampleConfig(
      title: 'Todos',
      icon: Icons.checklist,
      color: Colors.blue,
      widget: TodosPage(),
    ),
    _ExampleConfig(
      title: 'Auth',
      icon: Icons.lock_outline,
      color: Colors.indigo,
      widget: AuthPage(),
    ),
    _ExampleConfig(
      title: 'Cursors',
      icon: Icons.mouse_outlined,
      color: Colors.purple,
      widget: CursorsPage(),
    ),
    _ExampleConfig(
      title: 'Custom',
      icon: Icons.edit_location_alt_outlined,
      color: Colors.deepPurple,
      widget: CustomCursorsPage(),
    ),
    _ExampleConfig(
      title: 'Reactions',
      icon: Icons.emoji_emotions_outlined,
      color: Colors.orange,
      widget: ReactionsPage(),
    ),
    _ExampleConfig(
      title: 'Typing',
      icon: Icons.keyboard_outlined,
      color: Colors.teal,
      widget: TypingPage(),
    ),
    _ExampleConfig(
      title: 'Avatars',
      icon: Icons.group_outlined,
      color: Colors.green,
      widget: AvatarsPage(),
    ),
    _ExampleConfig(
      title: 'Tiles',
      icon: Icons.grid_on_outlined,
      color: Colors.red,
      widget: TileGamePage(),
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Initialize user ID suffix once
    if (_userIdSuffix == null) {
      final db = InstantProvider.of(context);
      final currentUser = db.auth.currentUser.value;
      if (currentUser != null) {
        final userId = currentUser.id;
        _userIdSuffix = ' (${userId.substring(userId.length - 4)})';
      } else {
        // For guest users, use consistent anonymous user ID
        final userId = db.getAnonymousUserId();
        _userIdSuffix = ' (${userId.substring(userId.length - 4)})';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentExample = _examples[_selectedIndex];
    
    return Scaffold(
      appBar: AppBar(
        title: Text('InstantDB - ${currentExample.title}${_userIdSuffix ?? ''}'),
        backgroundColor: currentExample.color,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              widget.debugEnabled ? Icons.bug_report : Icons.bug_report_outlined,
              color: Colors.white,
            ),
            tooltip: widget.debugEnabled ? 'Disable Debug Logging' : 'Enable Debug Logging',
            onPressed: widget.onToggleDebug,
          ),
          ConnectionStatusBuilder(
            builder: (context, isOnline) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOnline ? Icons.cloud_done : Icons.cloud_off,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: currentExample.widget,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: _examples.map((example) {
          return BottomNavigationBarItem(
            icon: Icon(example.icon),
            label: example.title,
          );
        }).toList(),
        currentIndex: _selectedIndex,
        selectedItemColor: currentExample.color,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        backgroundColor: Colors.white,
        elevation: 8,
      ),
    );
  }
}

class _ExampleConfig {
  final String title;
  final IconData icon;
  final Color color;
  final Widget widget;

  const _ExampleConfig({
    required this.title,
    required this.icon,
    required this.color,
    required this.widget,
  });
}