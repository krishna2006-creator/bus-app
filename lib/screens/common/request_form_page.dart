import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/models/request.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/request_service.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/bus_service.dart';

class RequestFormPage extends StatefulWidget {
  final String title;
  const RequestFormPage({super.key, required this.title});

  @override
  State<RequestFormPage> createState() => _RequestFormPageState();
}

class _RequestFormPageState extends State<RequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  RequestType _type = RequestType.missedBus;
  String? _busNumber;
  final _messageController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser!;
    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final req = Request(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: user.id,
        userName: user.name ?? user.id,
        busNumber: _busNumber ?? user.assignedBusNumber ?? 'N/A',
        type: _type,
        message: _messageController.text.trim(),
      );
      await context.read<RequestService>().addRequest(req, auth.users);
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('Request submitted')));
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    if (auth.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = auth.currentUser!;
    final buses = context.watch<BusService>().buses;
    final color = _roleColor(user.role);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: color),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<RequestType>(
                  initialValue: _type,
                  items: RequestType.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(_typeLabel(t))))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _type = v ?? RequestType.missedBus),
                  decoration: InputDecoration(
                    labelText: 'Request Type',
                    prefixIcon: Icon(Icons.category, color: color),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: color, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _busNumber ?? user.assignedBusNumber,
                  items: buses
                      .map((b) => DropdownMenuItem(
                          value: b.busNumber,
                          child: Text('Bus ${b.busNumber} - ${b.route}')))
                      .toList(),
                  onChanged: (v) => setState(() => _busNumber = v),
                  decoration: InputDecoration(
                    labelText: 'Bus',
                    prefixIcon: Icon(Icons.directions_bus, color: color),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: color, width: 2),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Select bus' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _messageController,
                  minLines: 3,
                  maxLines: 6,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter message' : null,
                  decoration: InputDecoration(
                    labelText: 'Message',
                    prefixIcon: Icon(Icons.message, color: color),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.grey300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: color, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: Icon(Icons.send, color: AppColors.white),
                    label: const Text('Submit Request',
                        style: TextStyle(color: AppColors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _roleColor(UserRole role) {
    switch (role) {
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

  String _typeLabel(RequestType t) {
    switch (t) {
      case RequestType.missedBus:
        return 'Missed Bus';
      case RequestType.stopBus:
        return 'Request Stop';
      case RequestType.delayBus:
        return 'Delay Notice';
      case RequestType.busIssue:
        return 'Bus Issue';
    }
  }
}
