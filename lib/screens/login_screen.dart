import 'package:flutter/material.dart';
import 'package:instructor_mate/controllers/login_controller.dart';
import 'package:instructor_mate/app_styles.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late LoginController _loginController;

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loginController = LoginController(
      emailController: _emailController,
      passwordController: _passwordController,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

Future<void> _handleLogin() async {
  if (!_loginController.validateInput()) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Please enter valid email and password',
          style: AppStyles.bodyMedium.copyWith(color: AppStyles.white),        
        ),
        backgroundColor: AppStyles.error,
      ),
    );
    return;
  }

    setState(() {
      _isLoading = true;
    });

    final success = await _loginController.login();

    setState(() {
      _isLoading = false;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Login Successful!' : 'Login Failed!',
          style: AppStyles.bodyMedium.copyWith(color: AppStyles.white),
        ),
        backgroundColor: success ? AppStyles.success : AppStyles.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusL),
        ),
      ),
    );
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppStyles.backgroundGradientDecoration,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: AppStyles.paddingLarge,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogo(),
                    SizedBox(height: AppStyles.spacingXL),
                    _buildLoginCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          padding: AppStyles.paddingMedium,
          decoration: AppStyles.logoDecoration,
          child: Icon(
            Icons.school_rounded,
            size: AppStyles.iconSizeLarge,
            color: AppStyles.primaryPurple,
          ),
        ),
        SizedBox(height: AppStyles.spacingL),
        Text(
          'InstructorMate',
          style: AppStyles.headingLarge,
        ),
        SizedBox(height: AppStyles.spacingS),
        Text(
          'Welcome back! Please login to continue',
          style: AppStyles.subtitleWhite,
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: AppStyles.paddingLarge,
      decoration: AppStyles.cardDecoration,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEmailField(),
            SizedBox(height: AppStyles.spacingL),
            _buildPasswordField(),
            SizedBox(height: AppStyles.spacingM),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                child: Text(
                  'Forgot Password?',
                  style: AppStyles.linkText,
                ),
              ),
            ),
            SizedBox(height: AppStyles.spacingL),
            _buildLoginButton(),
            SizedBox(height: AppStyles.spacingL),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: AppStyles.bodyMedium,
                ),
                GestureDetector(
                  onTap: () {},
                  child: Text(
                    'Sign Up',
                    style: AppStyles.linkText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      style: AppStyles.bodyMedium,
      decoration: AppStyles.inputDecoration(
        labelText: 'Email Address',
        icon: Icons.email_rounded,
        iconColor: AppStyles.primaryPurple,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter your email';
        if (!value.contains('@')) return 'Please enter a valid email';
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: AppStyles.bodyMedium,
      decoration: AppStyles.inputDecoration(
        labelText: 'Password',
        icon: Icons.lock_rounded,
        iconColor: AppStyles.primaryDeepPurple,
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: AppStyles.darkGray,
          ),
          onPressed: _togglePasswordVisibility,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter your password';
        if (value.length < 6) return 'Password must be at least 6 characters';
        return null;
      },
    );
  }

  Widget _buildLoginButton() {
  return Container(
    height: AppStyles.buttonHeight,
    decoration: AppStyles.buttonDecoration, // 👈 THIS is the missing color
    child: ElevatedButton(
      onPressed: _isLoading ? null : _handleLogin,
      style: AppStyles.elevatedButtonStyle, // stays transparent on purpose
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
}