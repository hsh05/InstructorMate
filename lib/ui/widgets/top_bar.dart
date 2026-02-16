// lib/ui/widgets/top_bar.dart
import 'package:flutter/material.dart';
import '../../app/state/syllabus_vm.dart';
import '../ui_scale.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.ui,
    required this.title,
    required this.subtitle,
    required this.fileChipText,
    required this.stage,
    required this.stageProgress,
    required this.busy,
    required this.onUpload,
    required this.onConvert,
    required this.onPreview,
    required this.onDownload,
    required this.onClear,
  });

  final UiScale ui;
  final String title;
  final String subtitle;
  final String? fileChipText;
  final FlowStage stage;
  final double stageProgress;
  final bool busy;

  final VoidCallback? onUpload;
  final VoidCallback? onConvert;
  final VoidCallback? onPreview;
  final VoidCallback? onDownload;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ui.px(16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ui.cardRadius),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            color: Colors.black.withOpacity(0.05),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [
              const Icon(Icons.school_rounded, size: 26),
              SizedBox(width: ui.px(10)),
              Text(
                title,
                style: TextStyle(
                  fontSize: ui.px(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),

              IconButton(
                icon: const Icon(Icons.upload_file_rounded),
                onPressed: onUpload,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onClear,
              ),
            ],
          ),

          if (fileChipText != null)
            Padding(
              padding: EdgeInsets.only(top: ui.px(8)),
              child: Chip(
                label: Text(fileChipText!),
              ),
            ),

          SizedBox(height: ui.px(12)),

          LinearProgressIndicator(
            value: stageProgress,
            minHeight: 6,
          ),
        ],
      ),
    );
  }
}
