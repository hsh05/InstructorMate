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
  final int _itemsPerPage = 5;

  // Demo data - Replace with backend call
  final List<Workspace> _workspaces = [
    Workspace(
      id: '1',
      title: 'OOP',
      semester: 'Fall 2025',
      studentCount: 45,
      taskCount: 3,
    ),
    Workspace(
      id: '2',
      title: 'Data Structures & Algorithms',
      semester: 'Fall 2025',
      studentCount: 38,
      taskCount: 5,
    ),
    Workspace(
      id: '3',
      title: 'Database Systems',
      semester: 'Fall 2025',
      studentCount: 42,
      taskCount: 2,
    ),
    Workspace(
      id: '4',
      title: 'Software Engineering',
      semester: 'Spring 2025',
      studentCount: 35,
      taskCount: 4,
    ),
    Workspace(
      id: '5',
      title: 'Web Development',
      semester: 'Spring 2025',
      studentCount: 50,
      taskCount: 6,
    ),
  ];

  List<Workspace> get _activeWorkspaces => 
    _workspaces.where((w) => !w.isArchived).toList();

  List<Workspace> get _currentPageWorkspaces {
    final start = _currentPage * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, _activeWorkspaces.length);
    return _activeWorkspaces.sublist(start, end);
  }

  int get _totalPages => (_activeWorkspaces.length / _itemsPerPage).ceil();
  bool get _canGoPrevious => _currentPage > 0;
  bool get _canGoNext => _currentPage < _totalPages - 1;

  void _previousPage() {
    if (_canGoPrevious) setState(() => _currentPage--);
  }

  void _nextPage() {
    if (_canGoNext) setState(() => _currentPage++);
  }

  void _onWorkspaceTap(Workspace workspace) {
    // TODO: Navigate to workspace details
    debugPrint('Tapped workspace: ${workspace.title}');
  }

  void _onWorkspaceMore(Workspace workspace) {
    _showWorkspaceOptions(workspace);
  }

  void _showWorkspaceOptions(Workspace workspace) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppStyles.radiusXL)),
      ),
      builder: (context) => Container(
        padding: AppStyles.paddingLarge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_rounded, color: AppStyles.primaryPurple),
              title: Text('Edit Workspace', style: AppStyles.bodyLarge),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to edit screen
              },
            ),
            ListTile(
              leading: Icon(Icons.archive_rounded, color: AppStyles.warning),
              title: Text('Archive', style: AppStyles.bodyLarge),
              onTap: () {
                Navigator.pop(context);
                // TODO: Archive workspace
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: AppStyles.error),
              title: Text('Delete', style: AppStyles.bodyLarge),
              onTap: () {
                Navigator.pop(context);
                // TODO: Delete workspace
              },
            ),
          ],
        ),
      ),
    );
  }

  void _viewArchive() {
    // TODO: Navigate to archived workspaces
    debugPrint('View archive');
  }

  void _addWorkspace() {
    // TODO: Navigate to create workspace screen
    debugPrint('Add workspace');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppStyles.lightGray,
    body: SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
          _buildFooter(),
        ],
      ),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: AppStyles.paddingLarge,
    child: Row(
      children: [
        Text('Your Workspaces', style: AppStyles.headingMedium),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.chevron_left_rounded, color: _canGoPrevious ? AppStyles.primaryPurple : AppStyles.mediumGray),
          onPressed: _canGoPrevious ? _previousPage : null,
        ),
        Text(
          '${_currentPage + 1}/$_totalPages',
          style: AppStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right_rounded, color: _canGoNext ? AppStyles.primaryPurple : AppStyles.mediumGray),
          onPressed: _canGoNext ? _nextPage : null,
        ),
      ],
    ),
  );

  Widget _buildContent() => SingleChildScrollView(
    padding: EdgeInsets.symmetric(horizontal: AppStyles.paddingL),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a workspace to view details and manage content',
          style: AppStyles.bodyMedium,
        ),
        SizedBox(height: AppStyles.spacingL),
        ..._currentPageWorkspaces.map((workspace) => WorkspaceCard(
          workspace: workspace,
          onTap: () => _onWorkspaceTap(workspace),
          onMorePressed: () => _onWorkspaceMore(workspace),
        )),
      ],
    ),
  );

  Widget _buildFooter() => Container(
    padding: AppStyles.paddingLarge,
    decoration: BoxDecoration(
      color: AppStyles.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: Row(
      children: [
        OutlinedButton.icon(
          onPressed: _viewArchive,
          icon: Icon(Icons.archive_rounded, size: AppStyles.iconM),
          label: const Text('View Archive'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppStyles.primaryPurple,
            side: BorderSide(color: AppStyles.primaryPurple),
            shape: RoundedRectangleBorder(
              borderRadius: AppStyles.borderRadiusM,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: AppStyles.paddingL,
              vertical: AppStyles.paddingM,
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _addWorkspace,
          icon: Icon(Icons.add_rounded, size: AppStyles.iconM),
          label: const Text('Add Workspace'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppStyles.primaryPurple,
            foregroundColor: AppStyles.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: AppStyles.borderRadiusM,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: AppStyles.paddingL,
              vertical: AppStyles.paddingM,
            ),
          ),
        ),
      ],
    ),
  );
}