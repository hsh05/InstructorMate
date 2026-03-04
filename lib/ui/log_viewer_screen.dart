// lib/ui/log_viewer_screen.dart
//
// Full-screen log viewer — shows everything written via AppLog.d().
// Access: tap the bug icon in the AppBar (only visible on mobile).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_buffer.dart';
import '../config/app_colors.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final _scroll = ScrollController();
  String _logs = '';
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _logs = AppLog.all);
    // Scroll to bottom after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _clear() async {
    await AppLog.clear();
    _refresh();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _logs));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard')));
  }

  List<String> get _filteredLines {
    final lines = _logs.split('\n');
    if (_filter.isEmpty) return lines;
    final q = _filter.toLowerCase();
    return lines.where((l) => l.toLowerCase().contains(q)).toList();
  }

  Color _lineColor(String line) {
    if (line.contains('!!!') ||
        line.contains('CRASH') ||
        line.contains('ERROR')) {
      return Colors.red.shade300;
    }
    if (line.contains('[Toast]')) return Colors.orange.shade300;
    if (line.contains('[NS]')) return Colors.blue.shade300;
    if (line.contains('[Scheduler]')) return Colors.green.shade300;
    if (line.contains('[WebNotif]')) return Colors.purple.shade300;
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final lines = _filteredLines;
    return Scaffold(
      backgroundColor: const Color(0xFF1A1625),
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text(
          'Debug Logs',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white),
            tooltip: 'Copy all',
            onPressed: _copy,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            tooltip: 'Clear logs',
            onPressed: _clear,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Filter (e.g. NS, Toast, CRASH)',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.white54,
                  size: 18,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
      ),
      body: lines.isEmpty
          ? Center(
              child: Text(
                _filter.isEmpty ? 'No logs yet.' : 'No lines match "$_filter".',
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: lines.length,
              itemBuilder: (_, i) {
                final line = lines[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: _lineColor(line),
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: AppColors.primary,
        onPressed: () {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        child: const Icon(Icons.arrow_downward_rounded, color: Colors.white),
      ),
    );
  }
}
