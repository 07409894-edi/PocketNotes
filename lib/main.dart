import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// ---------------------------------------------------------------
// BOOK MODEL: one row of the "books" table
// ---------------------------------------------------------------
class Book {
  final int? id; // null until the database gives it an id
  final String title;
  final String author;

  Book({this.id, required this.title, required this.author});

  // Turn a database row (Map) into a Book object
  factory Book.fromMap(Map<String, Object?> map) => Book(
        id: map['id'] as int,
        title: map['title'] as String,
        author: map['author'] as String,
      );
}

// ---------------------------------------------------------------
// DATABASE HELPER: opens the database ONE time only
// ---------------------------------------------------------------
class AppDatabase {
  // "static final" fields are created lazily on first use and only once.
  // So _open() runs one time, and everyone shares this same Future<Database>.
  static final Future<Database> instance = _open();

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'pocket_notes.db');
    debugPrint(path); 
    return openDatabase(
      path,
      version: 1,
      // onCreate runs only the first time, when the file doesn't exist yet
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE books('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'title TEXT NOT NULL, '
          'author TEXT NOT NULL)',
        );
      },
    );
  }
}

// ---------------------------------------------------------------
// MAIN: load the saved theme BEFORE runApp (no wrong-theme flash)
// ---------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // needed before using plugins
  final prefs = SharedPreferencesAsync();
  final isDark = await prefs.getBool('isDark') ?? false; // default: light
  runApp(PocketNotesApp(startDark: isDark));
}

// ---------------------------------------------------------------
// APP ROOT: holds the current theme
// ---------------------------------------------------------------
class PocketNotesApp extends StatefulWidget {
  final bool startDark; // theme that was loaded in main()
  const PocketNotesApp({super.key, required this.startDark});

  @override
  State<PocketNotesApp> createState() => _PocketNotesAppState();
}

class _PocketNotesAppState extends State<PocketNotesApp> {
  late bool _isDark = widget.startDark;

  // Called by the switch: update the screen, then save the choice
  Future<void> _setDark(bool value) async {
    setState(() => _isDark = value);
    await SharedPreferencesAsync().setBool('isDark', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: HomePage(isDark: _isDark, onThemeChanged: _setDark),
    );
  }
}

// ---------------------------------------------------------------
// THE ONLY SCREEN
// ---------------------------------------------------------------
class HomePage extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  const HomePage({super.key, required this.isDark, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Book> _books = [];

  // NOT SAVED anywhere: normal State variables, lost when the app is killed
  bool _favoritesOnly = false;
  final Set<int> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _loadBooks(); // load from sqflite when the app opens
  }

  // READ: get all rows and show them
  Future<void> _loadBooks() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('books', orderBy: 'id');
    setState(() => _books = rows.map(Book.fromMap).toList());
  }

  // CREATE
  Future<void> _addBook(String title, String author) async {
    final db = await AppDatabase.instance;
    await db.insert('books', {'title': title, 'author': author});
    await _loadBooks();
  }

  // UPDATE: where + whereArgs only, no variables inside the SQL string
  Future<void> _updateBook(int id, String title, String author) async {
    final db = await AppDatabase.instance;
    await db.update(
      'books',
      {'title': title, 'author': author},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadBooks();
  }

  // DELETE: where + whereArgs only
  Future<void> _deleteBook(int id) async {
    final db = await AppDatabase.instance;
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
    _favoriteIds.remove(id);
    await _loadBooks();
  }

  // One dialog for both add (book == null) and edit (book != null)
  Future<void> _showBookDialog({Book? book}) async {
    final titleCtrl = TextEditingController(text: book?.title ?? '');
    // If this is the very first book, prefill the author with my name
    final authorCtrl = TextEditingController(
      text: book?.author ?? (_books.isEmpty ? 'Ronnliegh' : ''),
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(book == null ? 'Add Book' : 'Edit Book'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: authorCtrl,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              final author = authorCtrl.text.trim();
              if (title.isEmpty || author.isEmpty) return; // simple check
              if (book == null) {
                _addBook(title, author);
              } else {
                _updateBook(book.id!, title, author);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Apply the favorites filter (display only, the table is untouched)
    final shown = _favoritesOnly
        ? _books.where((b) => _favoriteIds.contains(b.id)).toList()
        : _books;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pocket Notes'),
        actions: [
          const Icon(Icons.light_mode),
          Switch(value: widget.isDark, onChanged: widget.onThemeChanged),
          const Icon(Icons.dark_mode),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBookDialog(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // "Favorites only" chip (not saved)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Favorites only'),
                selected: _favoritesOnly,
                onSelected: (v) => setState(() => _favoritesOnly = v),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No books to show'))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final book = shown[i];
                      final isFav = _favoriteIds.contains(book.id);
                      return ListTile(
                        title: Text(book.title),
                        subtitle: Text(book.author),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(isFav ? Icons.star : Icons.star_border),
                              onPressed: () => setState(() {
                                isFav
                                    ? _favoriteIds.remove(book.id)
                                    : _favoriteIds.add(book.id!);
                              }),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showBookDialog(book: book),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteBook(book.id!),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}