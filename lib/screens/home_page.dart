import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/widgets/login_button.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    _checkLastRole();
  }

  Future<void> _checkLastRole() async {
    try {
      final auth = context.read<AuthService>();
      // If user is already logged in, GoRouter redirect in main.dart handles it.
      // We only proceed here if there's no active session.
      if (auth.currentUser != null) return;

      final prefs = await SharedPreferences.getInstance();
      final lastRoleName = prefs.getString(AuthService.lastRoleKey);
      if (lastRoleName != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          try {
            final role =
                UserRole.values.firstWhere((e) => e.name == lastRoleName);
            if (mounted) {
              context.go('/login', extra: role);
            }
          } catch (e) {
            debugPrint('Error parsing role: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking last role: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Icon(Icons.directions_bus, size: 80, color: AppColors.adminBlue),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Agni College',
                style: context.textStyles.headlineLarge?.copyWith(
                  color: AppColors.grey900,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Bus Tracker',
                style: context.textStyles.headlineMedium?.copyWith(
                  color: AppColors.adminBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Track your bus in real-time',
                style: context.textStyles.bodyLarge?.copyWith(
                  color: AppColors.grey600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Expanded(
                child: ListView(
                  children: [
                    LoginButton(
                      title: 'Admin Login',
                      icon: Icons.admin_panel_settings,
                      color: AppColors.adminBlue,
                      onTap: () =>
                          context.push('/login', extra: UserRole.admin),
                    ),
                    LoginButton(
                      title: 'Student Login',
                      icon: Icons.school,
                      color: AppColors.studentGreen,
                      onTap: () =>
                          context.push('/login', extra: UserRole.student),
                    ),
                    LoginButton(
                      title: 'Staff Login',
                      icon: Icons.badge,
                      color: AppColors.staffOrange,
                      onTap: () =>
                          context.push('/login', extra: UserRole.staff),
                    ),
                    LoginButton(
                      title: 'Driver Login',
                      icon: Icons.local_shipping,
                      color: AppColors.driverRed,
                      onTap: () =>
                          context.push('/login', extra: UserRole.driver),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
