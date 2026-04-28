import 'package:flutter/material.dart';
import 'package:instructor_mate/controllers/signup_controller.dart';
import 'package:instructor_mate/app_styles.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  late final _controller = SignupController(_name, _email, _password, _confirmPassword);

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  final String _role = 'Instructor';

  // Live password criteria state
  bool _hasMinLength = false;
  bool _isAlphanumeric = false;

  // --- Validators (aligned with Chapter 7 ECP rules) ---

  /// TCN1–TCN7: not empty, ≥2 chars, alphabetic only (no digits, no special chars)
  String? _validateName(String? v) {
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter name';
    if (trimmed.length < 2) return 'Min 2 chars';
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmed)) {
      return 'Only alphabetic characters allowed';
    }
    return null;
  }

  /// TCE1–TCE7: not empty, exactly one @, non-empty local & domain parts
  String? _validateEmail(String? v) {
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter email';
    final atCount = trimmed.split('@').length - 1;
    if (atCount == 0) return 'Invalid email';
    if (atCount > 1) return 'Invalid email';
    final parts = trimmed.split('@');
    if (parts[0].isEmpty) return 'Invalid email';
    if (parts[1].isEmpty) return 'Invalid email';
    return null;
  }

  /// TCP1–TCP5: not empty, ≥6 chars, alphanumeric only
  String? _validatePassword(String? v) {
    final val = v ?? '';
    if (val.isEmpty) return 'Enter password';
    if (val.length < 6) return 'Min 6 chars';
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(val)) {
      return 'Only letters & numbers allowed';
    }
    return null;
  }

  /// TCC1–TCC4: not empty, must match password exactly (case-sensitive)
  String? _validateConfirmPassword(String? v) {
    if (v == null || v.isEmpty) return 'Confirm password';
    if (v != _password.text) return "Passwords don't match";
    return null;
  }

  void _onPasswordChanged(String value) {
    setState(() {
      _hasMinLength = value.length >= 6;
      _isAlphanumeric = RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value) && value.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final success = await _controller.signup(_role);
    if (!mounted) return;

    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        success ? 'Account Created!' : 'Signup Failed!',
        style: AppStyles.bodyMedium.copyWith(color: AppStyles.white),
      ),
      backgroundColor: success ? AppStyles.success : AppStyles.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppStyles.radiusL)),
    ));

    if (success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: AppStyles.backgroundGradientDecoration,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: AppStyles.paddingLarge,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildHeader(),
                    SizedBox(height: AppStyles.spacingXL),
                    _buildForm(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildHeader() => Column(
        children: [
          Container(
            padding: AppStyles.paddingMedium,
            decoration: AppStyles.logoDecoration,
            child: Icon(Icons.person_add_rounded,
                size: AppStyles.iconSizeLarge, color: AppStyles.primaryPurple),
          ),
          SizedBox(height: AppStyles.spacingL),
          Text('Create Account', style: AppStyles.headingLarge),
          SizedBox(height: AppStyles.spacingS),
          Text('Join InstructorMate today', style: AppStyles.subtitleWhite),
        ],
      );

  Widget _buildForm() => Container(
        padding: AppStyles.paddingLarge,
        decoration: AppStyles.cardDecoration,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_name, 'Full Name', Icons.person_rounded, AppStyles.primaryPurple,
                  validator: _validateName),
              SizedBox(height: AppStyles.spacingL),
              _field(_email, 'Email', Icons.email_rounded, AppStyles.primaryPurple,
                  type: TextInputType.emailAddress,
                  validator: _validateEmail),
              SizedBox(height: AppStyles.spacingL),
              _field(_password, 'Password', Icons.lock_rounded, AppStyles.primaryDeepPurple,
                  obscure: _obscurePassword,
                  onChanged: _onPasswordChanged,
                  suffix: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                        color: AppStyles.darkGray),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: _validatePassword),
              // Live password criteria indicators
              _buildPasswordCriteria(),
              SizedBox(height: AppStyles.spacingL),
              _field(_confirmPassword, 'Confirm Password', Icons.lock_outline_rounded,
                  AppStyles.primaryDeepPurple,
                  obscure: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                        color: AppStyles.darkGray),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: _validateConfirmPassword),
              SizedBox(height: AppStyles.spacingXL),
              _buildButton(),
              SizedBox(height: AppStyles.spacingL),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account? ', style: AppStyles.bodyMedium),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text('Login', style: AppStyles.linkText),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  /// Shows live password requirement checklist beneath the password field.
  Widget _buildPasswordCriteria() => Padding(
        padding: const EdgeInsets.only(top: 8.0, left: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _criteriaRow(_hasMinLength, 'At least 6 characters'),
            const SizedBox(height: 4),
            _criteriaRow(_isAlphanumeric, 'Letters and numbers only (no special characters)'),
          ],
        ),
      );

  Widget _criteriaRow(bool met, String label) => Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 16,
            color: met ? AppStyles.success : AppStyles.error,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppStyles.bodyMedium.copyWith(
              fontSize: 12,
              color: met ? AppStyles.success : AppStyles.error,
            ),
          ),
        ],
      );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon,
    Color iconColor, {
    TextInputType type = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: type,
        obscureText: obscure,
        style: AppStyles.bodyMedium,
        textCapitalization:
            type == TextInputType.name ? TextCapitalization.words : TextCapitalization.none,
        decoration: AppStyles.inputDecoration(
            labelText: label, icon: icon, iconColor: iconColor, suffixIcon: suffix),
        validator: validator,
        onChanged: onChanged,
      );

  Widget _buildButton() => Container(
        height: AppStyles.buttonHeight,
        decoration: AppStyles.buttonDecoration,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: AppStyles.elevatedButtonStyle,
          child: _isLoading
              ? SizedBox(
                  height: AppStyles.loadingIndicatorSize,
                  width: AppStyles.loadingIndicatorSize,
                  child: CircularProgressIndicator(
                    strokeWidth: AppStyles.loadingIndicatorStrokeWidth,
                    valueColor: AlwaysStoppedAnimation(AppStyles.white),
                  ),
                )
              : Text('Create Account', style: AppStyles.buttonText),
        ),
      );
}