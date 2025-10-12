import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class BookmarkScreen extends StatefulWidget {
  final Function(LatLng) onNavigateToMap;
  const BookmarkScreen({Key? key, required this.onNavigateToMap})
      : super(key: key);

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  List<Map<String, dynamic>> _bookmarks = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  Map<String, List<Map<String, dynamic>>> _groupByCategory() {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    final filteredBookmarks = _searchQuery.isEmpty
        ? _bookmarks
        : _bookmarks.where((bookmark) {
            final name = bookmark['name']?.toString().toLowerCase() ?? '';
            final notes = bookmark['notes']?.toString().toLowerCase() ?? '';
            final query = _searchQuery.toLowerCase();
            return name.contains(query) || notes.contains(query);
          }).toList();
    for (var bookmark in filteredBookmarks) {
      String category = bookmark['category'] ?? 'Uncategorized';
      grouped.putIfAbsent(category, () => []).add(bookmark);
    }
    return grouped;
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBookmarks = prefs.getStringList('saved_locations');
    if (savedBookmarks != null) {
      setState(() {
        _bookmarks = savedBookmarks
            .map((bookmark) => jsonDecode(bookmark) as Map<String, dynamic>)
            .toList();
      });
    }
  }

  Future<String> _fetchAddressFromCoordinates(double lat, double lon) async {
    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json');
    final response = await http.get(
      url,
      headers: {'User-Agent': 'SmartMapNavigator/1.0 (contact@example.com)'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['display_name'] ?? 'Unknown Address';
    }
    return 'Address not found';
  }

  Future<void> _deleteBookmark(int index) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bookmarks.removeAt(index);
    });
    await prefs.setStringList(
      'saved_locations',
      _bookmarks.map((e) => jsonEncode(e)).toList(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmark deleted')),
      );
    }
  }

  Future<void> _clearAllBookmarks() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Bookmarks'),
        content: const Text('Are you sure you want to delete all bookmarks?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (shouldClear == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_locations');
      setState(() {
        _bookmarks.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All bookmarks deleted')),
      );
    }
  }

  void _editBookmarkNotes(int index) {
    final notesController =
        TextEditingController(text: _bookmarks[index]['notes'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Notes'),
        content: TextField(
          controller: notesController,
          decoration: const InputDecoration(hintText: 'Enter your notes here'),
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newNotes = notesController.text.trim();
              setState(() {
                _bookmarks[index]['notes'] = newNotes;
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setStringList(
                'saved_locations',
                _bookmarks.map((b) => jsonEncode(b)).toList(),
              );
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notes updated')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _changeBookmarkCategory(int index, String currentCategory) {
    String newCategory = currentCategory;
    const categories = [
      'General',
      'Work',
      'Travel',
      'Home',
      'Favorites',
      'Uncategorized'
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Category'),
        content: DropdownButton<String>(
          value:
              categories.contains(newCategory) ? newCategory : categories.first,
          isExpanded: true,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                newCategory = value;
              });
            }
          },
          items: categories
              .map((cat) => DropdownMenuItem(
                    value: cat,
                    child: Text(cat),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              setState(() {
                _bookmarks[index]['category'] = newCategory;
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setStringList(
                'saved_locations',
                _bookmarks.map((b) => jsonEncode(b)).toList(),
              );
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Category changed to $newCategory')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBookmarkOptions(BuildContext context, int index) async {
    final data = _bookmarks[index];
    final location = LatLng(data['lat'], data['lng']);
    final currentName = data['name'];
    final address = await _fetchAddressFromCoordinates(
        location.latitude, location.longitude);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.info, color: Colors.blue),
            title: Text(currentName),
            subtitle: Text(address),
          ),
          ListTile(
            leading: const Icon(Icons.map, color: Colors.blue),
            title: const Text('Navigate to Location'),
            onTap: () {
              Navigator.pop(context);
              widget.onNavigateToMap(location);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.orange),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(context);
              _renameBookmark(index, currentName);
            },
          ),
          ListTile(
            leading: const Icon(Icons.category, color: Colors.green),
            title: const Text('Change Category'),
            onTap: () {
              Navigator.pop(context);
              _changeBookmarkCategory(
                  index, data['category'] ?? 'Uncategorized');
            },
          ),
          ListTile(
            leading: const Icon(Icons.notes, color: Colors.blue),
            title: const Text('Edit Notes'),
            onTap: () {
              Navigator.pop(context);
              _editBookmarkNotes(index);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(context);
              _deleteBookmark(index);
            },
          ),
        ],
      ),
    );
  }

  void _renameBookmark(int index, String currentName) {
    final renameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Bookmark'),
        content: TextField(
          controller: renameController,
          decoration: const InputDecoration(hintText: 'Enter new name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = renameController.text.trim();
              if (newName.isNotEmpty) {
                setState(() {
                  _bookmarks[index]['name'] = newName;
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setStringList(
                  'saved_locations',
                  _bookmarks.map((e) => jsonEncode(e)).toList(),
                );
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Bookmark renamed to $newName')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupedBookmarks = _groupByCategory();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text('Bookmarks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _clearAllBookmarks,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Search bookmarks...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
          ),
          Expanded(
            child: _bookmarks.isEmpty
                ? const Center(child: Text('No saved locations yet.'))
                : groupedBookmarks.isEmpty
                    ? const Center(child: Text('No results found.'))
                    : ListView(
                        children: groupedBookmarks.entries.map((entry) {
                          final category = entry.key;
                          final bookmarks = entry.value;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                              ...bookmarks.map((data) {
                                final index = _bookmarks.indexOf(data);
                                return Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 4,
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 6, horizontal: 10),
                                  child: ListTile(
                                    leading: const Icon(Icons.label,
                                        color: Colors.blue),
                                    title: Text(
                                      data['name'],
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            'Lat: ${data['lat']}, Lng: ${data['lng']}'),
                                        if ((data['notes'] ?? '').isNotEmpty)
                                          Text('📝 ${data['notes']}'),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.more_vert,
                                          color: Colors.blue),
                                      onPressed: () =>
                                          _showBookmarkOptions(context, index),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          );
                        }).toList(),
                      ),
          ),
        ],
      ),
    );
  }
}
