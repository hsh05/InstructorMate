import 'package:flutter/material.dart';
import '../../state/auth_vm.dart';
import 'signup_screen.dart';
import '../../app_styles.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  
  // 👉 THE FIX: Using the unified AuthViewModel
  final _authVM = AuthViewModel();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    // 👉 THE FIX: Removed labels, passed directly, and returns a bool!
    final success = await _authVM.login(
      _email.text,
      _password.text,
    );
    
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      // Grab the user_id (if you need it globally later, it's safe in storage)
      const storage = FlutterSecureStorage();
      await storage.read(key: 'user_id');

      // 👉 THE FIX: Use your named route to go home so main.dart handles the ViewModel!
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/home'); // Or whatever your home route is named!
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _authVM.error ?? 'Login Failed! Please check your credentials.',
          style: AppStyles.bodyMedium.copyWith(color: AppStyles.white),
        ),
        backgroundColor: AppStyles.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusL)),
      ));
    }
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
            child: const Icon(Icons.school_rounded,
                size: AppStyles.iconSizeLarge, color: AppStyles.primary),
          ),
          const SizedBox(height: AppStyles.spacingL),
          const Text('InstructorMate', style: AppStyles.headingLarge),
          const SizedBox(height: AppStyles.spacingS),
          const Text('Welcome back! Please login to continue',
              style: AppStyles.subtitleWhite),
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
              _field(_email, 'Email Address', Icons.email_rounded,
                  AppStyles.primary,
                  type: TextInputType.emailAddress,
                  validator: (v) => v!.isEmpty
                      ? 'Enter email'
                      : !v.contains('@')
                          ? 'Invalid email'
                          : null),
              const SizedBox(height: AppStyles.spacingL),
              _field(_password, 'Password', Icons.lock_rounded,
                  AppStyles.primaryDark,
                  obscure: _obscurePassword,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: AppStyles.darkGray,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) => v!.isEmpty
                      ? 'Enter password'
                      : v.length < 6
                          ? '6 Characters Minimum'
                          : null),
              const SizedBox(height: AppStyles.spacingM),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Forgot Password?', style: AppStyles.linkText),
                ),
              ),
              const SizedBox(height: AppStyles.spacingL),
              _buildButton(),
              const SizedBox(height: AppStyles.spacingL),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ", style: AppStyles.bodyMedium),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SignupScreen())),
                    child: const Text('Sign Up', style: AppStyles.linkText),
                  ),
                ],
              ),
            ],
          ),
        ),
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
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: type,
        obscureText: obscure,
        style: AppStyles.bodyMedium,
        decoration: AppStyles.inputDecoration(
            labelText: label, icon: icon, iconColor: iconColor, suffixIcon: suffix),
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
              : const Text('Login', style: AppStyles.buttonText),
        ),
      );
}