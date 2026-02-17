import 'package:flutter/material.dart';
import 'package:instructor_mate/models/workspace_model.dart';
import 'package:instructor_mate/widgets/workspace_card.dart';
import 'package:instructor_mate/app_styles.dart';

class WorkspacesScreen extends StatefulWidget {
  const WorkspacesScreen({super.key});

  @override
  State<WorkspacesScreen> createState() => _WorkspacesScreenState();
}

class _WorkspacesScreenState extends State<WorkspacesScreen> {
  int _currentPage = 0;
  static const int _itemsPerPage = 5;

  final List<Workspace> _workspaces = [
    Workspace(
      title: 'Object Oriented Programming',
      semester: 'Fall 2025',
      enrolledStudents: List.generate(10, (i) => 's$i'),
      tasks: List.generate(3, (i) => 't$i'),
    ),
    Workspace(
      title: 'Data Structures & Algorithms',
      semester: 'Fall 2025',
      enrolledStudents: List.generate(38, (i) => 's$i'),
      tasks: List.generate(5, (i) => 't$i'),
    ),
    Workspace(
      title: 'Database Systems',
      semester: 'Fall 2025',
      enrolledStudents: List.generate(42, (i) => 's$i'),
      tasks: List.generate(2, (i) => 't$i'),
    ),
    Workspace(
      title: 'Foundations Of Software Engineering',
      semester: 'Spring 2025',
      enrolledStudents: List.generate(35, (i) => 's$i'),
      tasks: List.generate(4, (i) => 't$i'),
    ),
    Workspace(
      title: 'Web Development',
      semester: 'Spring 2025',
      enrolledStudents: List.generate(50, (i) => 's$i'),
      tasks: List.generate(6, (i) => 't$i'),
    ),
  ];

  List<Workspace> get _active =>
      _workspaces.where((w) => !w.isArchived).toList();

  int get _totalPages =>
      (_active.length / _itemsPerPage).ceil().clamp(1, 9999);

  List<Workspace> get _currentItems {
    final start = _currentPage * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, _active.length);
    return _active.sublist(start, end);
  }

  void _previousPage() {
    if (_currentPage > 0) setState(() => _currentPage--);
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) setState(() => _currentPage++);
  }

  void _archiveWorkspace(Workspace workspace) {
    setState(() {
      final index = _workspaces.indexWhere((w) => w.id == workspace.id);
      _workspaces[index] = workspace.copyWith(isArchived: true);
      if (_currentPage >= _totalPages) _currentPage = _totalPages - 1;
    });
  }

  void _deleteWorkspace(Workspace workspace) {
    setState(() {
      _workspaces.removeWhere((w) => w.id == workspace.id);
      if (_currentPage >= _totalPages) _currentPage = _totalPages - 1;
    });
  }

  void _showOptions(Workspace workspace) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppStyles.white,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppStyles.radiusXL)),
      ),
      builder: (_) => Padding(
        padding: AppStyles.paddingLarge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _optionTile(Icons.edit_rounded, 'Edit Workspace',
                AppStyles.primaryPurple, () {
              Navigator.pop(context);
            }),
            _optionTile(Icons.archive_rounded, 'Archive',
                AppStyles.warning, () {
              Navigator.pop(context);
              _archiveWorkspace(workspace);
            }),
            _optionTile(Icons.delete_rounded, 'Delete',
                AppStyles.error, () {
              Navigator.pop(context);
              _deleteWorkspace(workspace);
            }),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(
      IconData icon, String title, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: AppStyles.bodyLarge),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppStyles.backgroundGradientDecoration,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildContent()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }


Widget _buildHeader() {
  return Padding(
    padding: AppStyles.paddingLarge,
    child: Row(
      children: [
        // Title with flexible width
        Expanded(
          child: Text(
            'Your Workspaces',
            style: AppStyles.headingLarge.copyWith(
              fontSize: 22,
              letterSpacing: 0,  // Remove letter spacing completely
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        
        // Ultra-compact pagination
        Container(
          margin: const EdgeInsets.only(left: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left arrow - minimal size
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 20,
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: _currentPage > 0
                        ? AppStyles.white
                        : AppStyles.white.withOpacity(0.4),
                  ),
                  onPressed: _currentPage > 0 ? _previousPage : null,
                ),
              ),
              
              // Page indicator - compact
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '${_currentPage + 1}/$_totalPages',
                  style: AppStyles.subtitleWhite.copyWith(
                    fontSize: 13,
                  ),
                ),
              ),
              
              // Right arrow - minimal size
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 20,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: _currentPage < _totalPages - 1
                        ? AppStyles.white
                        : AppStyles.white.withOpacity(0.4),
                  ),
                  onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
  Widget _buildContent() {
    if (_active.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_rounded,
                size: AppStyles.iconXL,
                color: AppStyles.white.withOpacity(0.7)),
            SizedBox(height: AppStyles.spacingL),
            Text('No workspaces yet',
                style: AppStyles.headingSmall
                    .copyWith(color: AppStyles.white)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: AppStyles.paddingL),
      child: Column(
        children: _currentItems
            .map((w) => Padding(
                  padding:
                      EdgeInsets.only(bottom: AppStyles.spacingL),
                  child: WorkspaceCard(
                    workspace: w,
                    onTap: () {},
                    onMorePressed: () => _showOptions(w),
                  ),
                ))
            .toList(),
      ),
    );
  }

Widget _buildFooter() {
  return Container(
    padding: AppStyles.paddingLarge,
    decoration: BoxDecoration(
      color: AppStyles.white,
      borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppStyles.radiusXL)),
      boxShadow: AppStyles.shadowMedium,
    ),
    child: Row(
      children: [
        // Use Expanded so buttons shrink on smaller screens
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.archive_rounded),
            label: const Text('View Archive', maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8), // Tighter padding
              foregroundColor: AppStyles.primaryPurple,
              side: BorderSide(color: AppStyles.primaryPurple),
              shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
            ),
          ),
        ),
        const SizedBox(width: 12), // Fixed gap instead of Spacer
        Expanded(
          child: Container(
            decoration: AppStyles.buttonDecoration,
            child: ElevatedButton.icon(
              style: AppStyles.elevatedButtonStyle.copyWith(
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8)),
              ),
              onPressed: () {},
              icon: const Icon(Icons.add_rounded),
              label: Text('Add Workspace', 
                style: AppStyles.buttonText, 
                maxLines: 1, 
                overflow: TextOverflow.ellipsis
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
}