// lib/screens/auth/signup_screen.dart

import 'package:flutter/material.dart';
import '../../state/auth_vm.dart';
import '../../app_styles.dart';

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
  final _authVM = AuthViewModel();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  static String? validateEmail(String? v) {
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

  static String? validatePassword(String? v) {
    final val = v ?? '';
    if (val.isEmpty) return 'Enter password';
    if (val.length < 6) return 'Min 6 chars';
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(val)) {
      return 'Only letters & numbers allowed';
    }
    return null;
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
    
    final success = await _authVM.signUp(
      _email.text,
      _password.text,
      _name.text,
    );
    
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        success ? 'Account Created!' : (_authVM.error ?? 'Signup Failed!'),
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
                    const SizedBox(height: AppStyles.spacingXL),
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
            child: const Icon(Icons.person_add_rounded,
                size: AppStyles.iconSizeLarge, color: AppStyles.primary),
          ),
          const SizedBox(height: AppStyles.spacingL),
          const Text('Create Account', style: AppStyles.headingLarge),
          const SizedBox(height: AppStyles.spacingS),
          const Text('Join InstructorMate today', style: AppStyles.subtitleWhite),
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
              _field(_name, 'Full Name', Icons.person_rounded, AppStyles.primary,
                  validator: (v) => v!.isEmpty ? 'Enter name' : v.length < 2 ? 'Min 2 chars' : null),
              const SizedBox(height: AppStyles.spacingL),
              _field(_email, 'Email', Icons.email_rounded, AppStyles.primary,
                  type: TextInputType.emailAddress,
                  validator: validateEmail),
              const SizedBox(height: AppStyles.spacingL),
              _field(_password, 'Password', Icons.lock_rounded, AppStyles.primaryDark,
                  obscure: _obscurePassword,
                  suffix: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                        color: AppStyles.darkGray),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: validatePassword),
              const SizedBox(height: AppStyles.spacingL),
              _field(_confirmPassword, 'Confirm Password', Icons.lock_outline_rounded,
                  AppStyles.primaryDark,
                  obscure: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                        color: AppStyles.darkGray),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) => v!.isEmpty
                      ? 'Confirm password'
                      : v != _password.text
                          ? 'Passwords don\'t match'
                          : null),
              const SizedBox(height: AppStyles.spacingXL),
              _buildButton(),
              const SizedBox(height: AppStyles.spacingL),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? ', style: AppStyles.bodyMedium),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Login', style: AppStyles.linkText),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _field(TextEditingController controller, String label, IconData icon, Color iconColor,
          {TextInputType type = TextInputType.text,
          bool obscure = false,
          Widget? suffix,
          String? Function(String?)? validator}) =>
      TextFormField(
        controller: controller,
        keyboardType: type,
        obscureText: obscure,
        style: AppStyles.bodyMedium,
        textCapitalization: type == TextInputType.name ? TextCapitalization.words : TextCapitalization.none,
        decoration: AppStyles.inputDecoration(labelText: label, icon: icon, iconColor: iconColor, suffixIcon: suffix),
        validator: validator,
      );

  Widget _buildButton() => Container(
        height: AppStyles.buttonHeight,
        decoration: AppStyles.buttonDecoration,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: AppStyles.elevatedButtonStyle,
          child: _isLoading
              ? const SizedBox(
                  height: AppStyles.loadingIndicatorSize,
                  width: AppStyles.loadingIndicatorSize,
                  child: CircularProgressIndicator(
                    strokeWidth: AppStyles.loadingIndicatorStrokeWidth,
                    valueColor: AlwaysStoppedAnimation(AppStyles.white),
                  ),
                )
              : const Text('Create Account', style: AppStyles.buttonText),
        ),
      );
}
