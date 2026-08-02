import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/widgets/custom_button.dart';
import 'package:agni_college_bus_tracker/widgets/pop_scope.dart';

class LoginPage extends StatefulWidget {
  final UserRole role;

  const LoginPage({super.key, required this.role});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Color get roleColor {
    switch (widget.role) {
      case UserRole.admin:
        return AppColors.adminBlue;
      case UserRole.student:
        return AppColors.studentGreen;
      case UserRole.staff:
        return AppColors.staffOrange;
      case UserRole.driver:
        return AppColors.driverRed;
    }
  }

  IconData get roleIcon {
    switch (widget.role) {
      case UserRole.admin:
        return Icons.admin_panel_settings;
      case UserRole.student:
        return Icons.school;
      case UserRole.staff:
        return Icons.badge;
      case UserRole.driver:
        return Icons.local_shipping;
    }
  }

  String get roleName {
    switch (widget.role) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.student:
        return 'Student';
      case UserRole.staff:
        return 'Staff';
      case UserRole.driver:
        return 'Driver';
    }
  }

  Future<void> _login() async {
    if (_idController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter ID and password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final authService = context.read<AuthService>();
    final result = await authService.login(
      _idController.text,
      _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (result['success'] == true && mounted) {
      // The redirect logic in main.dart will handle the navigation
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login successful!')),
      );
    } else if (mounted) {
      final errorMessage = result['message'] ?? 'Login failed';
      debugPrint('🔐 LOGIN PAGE: Error - $errorMessage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          context.go('/');
        }
        return;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: roleColor),
            onPressed: () => context.go('/'),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(roleIcon, size: 60, color: roleColor),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '$roleName Login',
                  style: context.textStyles.headlineMedium?.copyWith(
                    color: AppColors.grey900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  controller: _idController,
                  decoration: InputDecoration(
                    labelText: 'User ID',
                    prefixIcon: Icon(Icons.person, color: roleColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: roleColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // For drivers, offer a dropdown to pick driver IDs (driver001..driver032)
                if (widget.role == UserRole.driver) ...[
                  Builder(builder: (context) {
                    final auth = context.watch<AuthService>();
                    final driverIds = auth.users
                        .where((u) => u.role == UserRole.driver)
                        .map((u) => u.id)
                        .toList();

                    // if controller empty, prefill with first available driver id
                    if (_idController.text.isEmpty && driverIds.isNotEmpty) {
                      _idController.text = driverIds.first;
                    }

                    return DropdownButtonFormField<String>(
                      initialValue: driverIds.contains(_idController.text)
                          ? _idController.text
                          : (driverIds.isNotEmpty ? driverIds.first : null),
                      items: driverIds
                          .map((id) =>
                              DropdownMenuItem(value: id, child: Text(id)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _idController.text = v;
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: 'Select Driver ID',
                        prefixIcon:
                            Icon(Icons.local_shipping, color: roleColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock, color: roleColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.grey600,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: roleColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(color: roleColor))
                      : CustomButton(
                          text: 'Login',
                          onPressed: _login,
                          backgroundColor: roleColor,
                          icon: Icons.login,
                          isLarge: true,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
