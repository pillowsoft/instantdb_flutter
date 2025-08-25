import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

class TodosPage extends StatefulWidget {
  const TodosPage({super.key});

  @override
  State<TodosPage> createState() => _TodosPageState();
}

class _TodosPageState extends State<TodosPage> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _addTodo() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final db = InstantProvider.of(context);
    
    try {
      // Using the new tx namespace API for a cleaner transaction
      final todoId = db.id();
      await db.transactChunk(
        db.tx['todos'][todoId].update({
          'text': text,
          'completed': false,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        })
      );

      _textController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add todo: $e')),
        );
      }
    }
  }

  Future<void> _toggleTodo(Map<String, dynamic> todo) async {
    final db = InstantProvider.of(context);
    
    try {
      // Using the new tx namespace API for updating
      await db.transactChunk(
        db.tx['todos'][todo['id']].update({
          'completed': !todo['completed'],
        })
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update todo: $e')),
        );
      }
    }
  }

  Future<void> _deleteTodo(String todoId) async {
    final db = InstantProvider.of(context);
    
    try {
      // Using the old API for deletion as it's simpler
      await db.transact([
        db.delete(todoId),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete todo: $e')),
        );
      }
    }
  }
  
  Future<void> _clearAllTodos() async {
    final db = InstantProvider.of(context);
    
    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('Clearing todos...'),
              ],
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }
      
      // Get a fresh query result
      final queryResult = await db.queryOnce({'todos': {}});
      
      if (queryResult.data != null && queryResult.data!['todos'] is List) {
        final todos = (queryResult.data!['todos'] as List)
            .cast<Map<String, dynamic>>();
        
        if (todos.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No todos to delete')),
            );
          }
          return;
        }
        
        // Create delete operations for all todos
        final deleteOps = <Operation>[];
        for (final todo in todos) {
          if (todo['id'] != null) {
            deleteOps.add(db.delete(todo['id']));
          }
        }
        
        // Execute transaction
        if (deleteOps.isNotEmpty) {
          await db.transact(deleteOps);
          
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Deleted ${todos.length} todo${todos.length > 1 ? 's' : ''}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear todos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[100],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep, size: 20),
                label: const Text('Clear All'),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Clear All Todos'),
                      content: const Text(
                        'This will delete all todos. This action cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirmed == true) {
                    await _clearAllTodos();
                  }
                },
              ),
            ],
          ),
        ),
        // Add todo input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    hintText: 'Add a new todo...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _addTodo(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addTodo,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
        
        // Todo list
        Expanded(
          child: InstantBuilderTyped<List<Map<String, dynamic>>>(
            query: {
              'todos': {},
            },
            transformer: (data) => (data['todos'] as List).cast<Map<String, dynamic>>(),
            loadingBuilder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
            errorBuilder: (context, error) => Center(
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
                    'Error loading todos',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(error),
                ],
              ),
            ),
            builder: (context, todos) {
              if (todos.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No todos yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Add your first todo above!',
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: todos.length,
                itemBuilder: (context, index) {
                  final todo = todos[index];
                  return TodoTile(
                    todo: todo,
                    onToggle: () => _toggleTodo(todo),
                    onDelete: () => _deleteTodo(todo['id']),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class TodoTile extends StatelessWidget {
  final Map<String, dynamic> todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const TodoTile({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = todo['completed'] == true;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Checkbox(
          value: isCompleted,
          onChanged: (_) => onToggle(),
          activeColor: Colors.green,
        ),
        title: Text(
          todo['text'] ?? '',
          style: TextStyle(
            decoration: isCompleted ? TextDecoration.lineThrough : null,
            color: isCompleted ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          _formatDate(todo['createdAt']),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          color: Colors.red[400],
          onPressed: onDelete,
        ),
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp as int);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }
}