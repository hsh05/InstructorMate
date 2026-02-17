import 'package:flutter/material.dart';
import 'package:instructor_mate/models/workspace_model.dart';
import 'package:instructor_mate/widgets/stat_chip.dart';
import 'package:instructor_mate/app_styles.dart';

class WorkspaceCard extends StatelessWidget {
  final Workspace workspace;
  final VoidCallback onTap;
  final VoidCallback onMorePressed;

  const WorkspaceCard({
    super.key,
    required this.workspace,
    required this.onTap,
    required this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.only(bottom: AppStyles.paddingM),
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: AppStyles.borderRadiusM,
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: AppStyles.borderRadiusM,
      child: Padding(
        padding: AppStyles.paddingMedium,
        child: Row(
          children: [
            _buildLeadingIcon(),
            SizedBox(width: AppStyles.gapL),
            Expanded(child: _buildContent()),
            _buildMoreButton(),
          ],
        ),
      ),
    ),
  );

  Widget _buildLeadingIcon() => Container(
    padding: EdgeInsets.all(AppStyles.paddingM),
    decoration: BoxDecoration(
      color: AppStyles.primaryPurple.withOpacity(0.1),
      borderRadius: AppStyles.borderRadiusM,
    ),
    child: Icon(
      Icons.folder_rounded,
      size: AppStyles.iconL,
      color: AppStyles.primaryPurple,
    ),
  );

  Widget _buildContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        workspace.title,
        style: AppStyles.headingSmall,
        // Added these to handle long titles safely
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      SizedBox(height: AppStyles.gapXS),
      Text(
        'Course workspace • ${workspace.semester}',
        style: AppStyles.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      SizedBox(height: AppStyles.gapM),
      Row(
        children: [
          // Wrap the first chip in Expanded
          Expanded(
            child: StatChip(
              icon: Icons.people_rounded,
              label: '${workspace.studentCount} students',
              iconColor: AppStyles.primaryPurple,
            ),
          ),
          SizedBox(width: AppStyles.gapS),
          // Wrap the second chip in Expanded
          Expanded(
            child: StatChip(
              icon: Icons.task_alt_rounded,
              label: '${workspace.taskCount} tasks today',
              iconColor: AppStyles.primaryDeepPurple,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildMoreButton() => IconButton(
    icon: Icon(Icons.more_vert_rounded, color: AppStyles.darkGray),
    onPressed: onMorePressed,
  );
}