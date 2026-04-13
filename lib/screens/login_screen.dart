import 'package:flutter/material.dart';
import 'package:instructor_mate/controllers/login_controller.dart';
import 'package:instructor_mate/screens/signup_screen.dart';
import 'package:instructor_mate/screens/profile_screen.dart';
import 'package:instructor_mate/app_styles.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final _controller = LoginController(_email, _password);

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
    final userId = await _controller.login(); // now a String? (UUID)
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (userId != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(userId: userId),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Login Failed! Please check your credentials.',
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
            child: Icon(Icons.school_rounded,
                size: AppStyles.iconSizeLarge, color: AppStyles.primaryPurple),
          ),
          SizedBox(height: AppStyles.spacingL),
          Text('InstructorMate', style: AppStyles.headingLarge),
          SizedBox(height: AppStyles.spacingS),
          Text('Welcome back! Please login to continue',
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
                  AppStyles.primaryPurple,
                  type: TextInputType.emailAddress,
                  validator: (v) => v!.isEmpty
                      ? 'Enter email'
                      : !v.contains('@')
                          ? 'Invalid email'
                          : null),
              SizedBox(height: AppStyles.spacingL),
              _field(_password, 'Password', Icons.lock_rounded,
                  AppStyles.primaryDeepPurple,
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
                          ? 'Min 6 chars'
                          : null),
              SizedBox(height: AppStyles.spacingM),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: Text('Forgot Password?', style: AppStyles.linkText),
                ),
              ),
              SizedBox(height: AppStyles.spacingL),
              _buildButton(),
              SizedBox(height: AppStyles.spacingL),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Don't have an account? ", style: AppStyles.bodyMedium),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SignupScreen())),
                    child: Text('Sign Up', style: AppStyles.linkText),
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
              ? SizedBox(
                  height: AppStyles.loadingIndicatorSize,
                  width: AppStyles.loadingIndicatorSize,
                  child: CircularProgressIndicator(
                    strokeWidth: AppStyles.loadingIndicatorStrokeWidth,
                    valueColor: AlwaysStoppedAnimation(AppStyles.white),
                  ),
                )
              : Text('Login', style: AppStyles.buttonText),
        ),
      );
}