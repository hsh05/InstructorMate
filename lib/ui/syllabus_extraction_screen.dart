// lib/ui/syllabus_extraction_screen.dart
//
// Shown immediately after a NEW syllabus is uploaded (non-duplicate).
// Polls vm.extractionDone every 3 s via vm.startExtractionPolling().
// Navigates to /workspace automatically when done.
// Design: dark gradient, animated floating orbs, step progress, pulsing ring.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';
import '../config/app_colors.dart';

class SyllabusExtractionScreen extends StatefulWidget {
  const SyllabusExtractionScreen({
    super.key,
    required this.vm,
    required this.filename,
  });
  final WorkspacesViewModel vm;
  final String filename;

  @override
  State<SyllabusExtractionScreen> createState() =>
      _SyllabusExtractionScreenState();
}

class _SyllabusExtractionScreenState extends State<SyllabusExtractionScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ─────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final AnimationController _orbCtrl;
  late final AnimationController _stepCtrl;
  late final AnimationController _doneCtrl;

  late final Animation<double> _pulseAnim;
  late final Animation<double> _orbAnim;

  int _stepIndex = 0;
  bool _navigating = false;

  static const _steps = [
    (icon: Icons.upload_rounded, label: 'Uploading syllabus…'),
    (icon: Icons.text_snippet_rounded, label: 'Parsing document text…'),
    (icon: Icons.manage_search_rounded, label: 'Identifying course details…'),
    (icon: Icons.auto_awesome_rounded, label: 'Running AI extraction…'),
    (icon: Icons.check_circle_rounded, label: 'Finalising workspace…'),
  ];

  @override
  void initState() {
    super.initState();

    // Pulsing ring
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Orbiting particle
    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _orbAnim = Tween<double>(begin: 0, end: 1).animate(_orbCtrl);

    // Step progress — advances every ~2.5 s
    _stepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _advanceSteps();

    // Done animation controller (scale up check mark)
    _doneCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Listen for extraction completing
    widget.vm.addListener(_onVmChange);

    // Start polling
    final wsId = widget.vm.current?.id;
    if (wsId != null) widget.vm.startExtractionPolling(wsId);
  }

  void _advanceSteps() async {
    for (int i = 0; i < _steps.length - 1; i++) {
      await Future.delayed(const Duration(milliseconds: 2600));
      if (!mounted) return;
      if (widget.vm.extractionDone)
        return; // stop auto-advancing; done anim takes over
      setState(() => _stepIndex = i + 1);
    }
  }

  void _onVmChange() {
    if (!mounted) return;
    if (widget.vm.extractionDone && !_navigating) {
      _navigating = true;
      setState(() => _stepIndex = _steps.length - 1);
      _doneCtrl.forward().then((_) async {
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/workspace');
        }
      });
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onVmChange);
    _pulseCtrl.dispose();
    _orbCtrl.dispose();
    _stepCtrl.dispose();
    _doneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C1E),
      body: Stack(
        children: [
          // ── Background gradient ──────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 1.1,
                colors: [Color(0xFF2A1B55), Color(0xFF0F0C1E)],
              ),
            ),
          ),

          // ── Subtle grid pattern ──────────────────────────────────────────
          CustomPaint(
            painter: _GridPainter(),
            size: Size.infinite,
          ),

          // ── Orbiting glow particles ──────────────────────────────────────
          AnimatedBuilder(
            animation: _orbAnim,
            builder: (_, __) {
              final size = MediaQuery.of(context).size;
              final cx = size.width / 2;
              final cy = size.height * 0.38;
              return Stack(
                children: [
                  _OrbParticle(
                      angle: _orbAnim.value * 2 * math.pi,
                      cx: cx,
                      cy: cy,
                      radius: 130,
                      color: const Color(0xFF7C5CBF),
                      size: 10),
                  _OrbParticle(
                      angle: _orbAnim.value * 2 * math.pi + math.pi * 0.6,
                      cx: cx,
                      cy: cy,
                      radius: 155,
                      color: const Color(0xFF3B8BD4),
                      size: 7),
                  _OrbParticle(
                      angle: _orbAnim.value * 2 * math.pi + math.pi * 1.2,
                      cx: cx,
                      cy: cy,
                      radius: 110,
                      color: const Color(0xFF9B78E0),
                      size: 6),
                ],
              );
            },
          ),

          // ── Main content ─────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // ── Pulsing ring + icon ────────────────────────────────
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, child) => Transform.scale(
                      scale: widget.vm.extractionDone ? 1.0 : _pulseAnim.value,
                      child: child,
                    ),
                    child: _CenterOrb(
                      doneAnim: _doneCtrl,
                      isDone: widget.vm.extractionDone,
                      hasError: widget.vm.extractionError,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Headline ───────────────────────────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      widget.vm.extractionDone
                          ? (widget.vm.extractionError
                              ? 'Almost There'
                              : 'Ready to Go!')
                          : 'Reading Your Syllabus',
                      key: ValueKey(widget.vm.extractionDone),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ── Subtitle ───────────────────────────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      widget.vm.extractionDone
                          ? (widget.vm.extractionError
                              ? 'Extraction had some issues — you can fill in the details manually.'
                              : 'All fields extracted. Opening your workspace now…')
                          : 'Our AI is extracting your course details.\nThis takes about 10–15 seconds.',
                      key: ValueKey('sub${widget.vm.extractionDone}'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                        height: 1.6,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Step progress ──────────────────────────────────────
                  _StepProgress(
                    steps: _steps,
                    currentIndex: _stepIndex,
                    isDone: widget.vm.extractionDone,
                    hasError: widget.vm.extractionError,
                  ),

                  const SizedBox(height: 40),

                  // ── Filename pill ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _fileIcon(widget.filename),
                          color: Colors.white.withOpacity(0.5),
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width - 130,
                          ),
                          child: Text(
                            widget.filename,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 3),

                  // ── Bottom tip ─────────────────────────────────────────
                  if (!widget.vm.extractionDone)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Text(
                        'You can edit any field after extraction completes.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.28),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.docx')) return Icons.article_rounded;
    return Icons.description_rounded;
  }
}

// ── Center orb ────────────────────────────────────────────────────────────────
class _CenterOrb extends StatelessWidget {
  const _CenterOrb({
    required this.doneAnim,
    required this.isDone,
    required this.hasError,
  });
  final AnimationController doneAnim;
  final bool isDone;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 136,
      height: 136,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Container(
            width: 136,
            height: 136,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF7C5CBF).withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Mid ring
          Container(
            width: 106,
            height: 106,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF7C5CBF).withOpacity(0.4),
                width: 1.5,
              ),
            ),
          ),
          // Inner filled circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF6747B0), Color(0xFF9B78E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C5CBF).withOpacity(0.5),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: doneAnim,
              builder: (_, __) {
                final t = doneAnim.value;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isDone
                      ? Transform.scale(
                          scale: 0.6 + 0.4 * t,
                          child: Icon(
                            hasError
                                ? Icons.warning_amber_rounded
                                : Icons.check_rounded,
                            color: Colors.white,
                            size: 36,
                            key: const ValueKey('done'),
                          ),
                        )
                      : const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 32,
                          key: ValueKey('loading'),
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

// ── Step progress list ─────────────────────────────────────────────────────────
class _StepProgress extends StatelessWidget {
  const _StepProgress({
    required this.steps,
    required this.currentIndex,
    required this.isDone,
    required this.hasError,
  });

  final List<({IconData icon, String label})> steps;
  final int currentIndex;
  final bool isDone;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: steps.asMap().entries.map((e) {
        final i = e.key;
        final step = e.value;
        final isActive = i == currentIndex && !isDone;
        final isComplete = isDone || i < currentIndex;
        final isPending = !isComplete && !isActive;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withOpacity(0.09)
                : isComplete
                    ? Colors.white.withOpacity(0.04)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF7C5CBF).withOpacity(0.6)
                  : Colors.white.withOpacity(0.06),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Step indicator
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isComplete
                      ? (hasError && i == steps.length - 1
                          ? Colors.orange.withOpacity(0.2)
                          : const Color(0xFF22C55E).withOpacity(0.15))
                      : isActive
                          ? const Color(0xFF7C5CBF).withOpacity(0.3)
                          : Colors.white.withOpacity(0.05),
                  border: Border.all(
                    color: isComplete
                        ? (hasError && i == steps.length - 1
                            ? Colors.orange.withOpacity(0.5)
                            : const Color(0xFF22C55E).withOpacity(0.5))
                        : isActive
                            ? const Color(0xFF9B78E0).withOpacity(0.7)
                            : Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Icon(
                  isComplete
                      ? (hasError && i == steps.length - 1
                          ? Icons.warning_amber_rounded
                          : Icons.check_rounded)
                      : step.icon,
                  size: 14,
                  color: isComplete
                      ? (hasError && i == steps.length - 1
                          ? Colors.orange
                          : const Color(0xFF22C55E))
                      : isActive
                          ? const Color(0xFF9B78E0)
                          : Colors.white.withOpacity(0.2),
                ),
              ),
              const SizedBox(width: 12),
              // Label
              Expanded(
                child: Text(
                  step.label,
                  style: TextStyle(
                    color: isComplete
                        ? Colors.white.withOpacity(0.7)
                        : isActive
                            ? Colors.white.withOpacity(0.95)
                            : Colors.white.withOpacity(0.22),
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              // Active spinner
              if (isActive)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: const Color(0xFF9B78E0).withOpacity(0.8),
                  ),
                ),
              if (isComplete)
                Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: const Color(0xFF22C55E).withOpacity(0.7),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Orbiting particle ──────────────────────────────────────────────────────────
class _OrbParticle extends StatelessWidget {
  const _OrbParticle({
    required this.angle,
    required this.cx,
    required this.cy,
    required this.radius,
    required this.color,
    required this.size,
  });
  final double angle, cx, cy, radius, size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final x = cx + radius * math.cos(angle) - size / 2;
    final y = cy + radius * math.sin(angle) - size / 2;
    return Positioned(
      left: x,
      top: y,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.7),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.5), blurRadius: size * 2),
          ],
        ),
      ),
    );
  }
}

// ── Subtle grid background painter ────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;
    const spacing = 48.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
