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
  
  // 👉 THE FIX: Replaced SignupController with AuthViewModel
  final _authVM = AuthViewModel();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

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
    
    // 👉 THE FIX: Capital 'U', removed labels, correct order!
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
                size: AppStyles.iconSizeLarge, color: AppStyles.primaryPurple),
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
              _field(_name, 'Full Name', Icons.person_rounded, AppStyles.primaryPurple,
                  validator: (v) => v!.isEmpty ? 'Enter name' : v.length < 2 ? 'Min 2 chars' : null),
              const SizedBox(height: AppStyles.spacingL),
              _field(_email, 'Email', Icons.email_rounded, AppStyles.primaryPurple,
                  type: TextInputType.emailAddress,
                  validator: (v) =>
                      v!.isEmpty ? 'Enter email' : !v.contains('@') ? 'Invalid email' : null),
              const SizedBox(height: AppStyles.spacingL),
              _field(_password, 'Password', Icons.lock_rounded, AppStyles.primaryDeepPurple,
                  obscure: _obscurePassword,
                  suffix: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                        color: AppStyles.darkGray),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) => v!.isEmpty ? 'Enter password' : v.length < 6 ? 'Min 6 chars' : null),
              const SizedBox(height: AppStyles.spacingL),
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