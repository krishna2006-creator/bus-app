import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/services/bus_service.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';

class AddBusPage extends StatefulWidget {
  const AddBusPage({super.key});

  @override
  State<AddBusPage> createState() => _AddBusPageState();
}

class _AddBusPageState extends State<AddBusPage> {
  final _formKey = GlobalKey<FormState>();
  final _busNumberController = TextEditingController();
  final _routeController = TextEditingController();
  final _driverNameController = TextEditingController();
  final _driverPhoneController = TextEditingController();
  final _stopsController = TextEditingController();
  bool _isOperating = true;
  bool _isSaving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final busService = context.read<BusService>();
    final messenger = ScaffoldMessenger.of(context);

    final stops = _stopsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final bus = Bus(
      id: DateTime.now().millisecondsSinceEpoch,
      busNumber: _busNumberController.text.trim(),
      route: _routeController.text.trim(),
      driverName: _driverNameController.text.trim().isEmpty
          ? null
          : _driverNameController.text.trim(),
      driverPhone: _driverPhoneController.text.trim().isEmpty
          ? null
          : _driverPhoneController.text.trim(),
      isOperating: _isOperating,
      stops: stops,
    );

    try {
      await busService.addBus(bus);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Bus added')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed to add bus: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Bus'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.adminBlue),
          onPressed: () => context.pop(),
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
                _LabeledField(
                  label: 'Bus Number',
                  controller: _busNumberController,
                  icon: Icons.confirmation_number,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter bus number'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                _LabeledField(
                  label: 'Route',
                  controller: _routeController,
                  icon: Icons.route,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter route' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                _LabeledField(
                  label: 'Driver Name (optional)',
                  controller: _driverNameController,
                  icon: Icons.person,
                ),
                const SizedBox(height: AppSpacing.md),
                _LabeledField(
                  label: 'Driver Phone (optional)',
                  controller: _driverPhoneController,
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: AppSpacing.md),
                _LabeledField(
                  label: 'Stops (comma separated)',
                  controller: _stopsController,
                  icon: Icons.location_on,
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  title: const Text('Operating'),
                  value: _isOperating,
                  activeThumbColor: AppColors.adminBlue,
                  onChanged: (v) => setState(() => _isOperating = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: Icon(Icons.save, color: AppColors.white),
                    label: Text('Save Bus',
                        style: TextStyle(color: AppColors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.adminBlue,
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
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? Function(String?)? validator;
  final int maxLines;
  final TextInputType? keyboardType;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.icon,
    this.validator,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.adminBlue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.grey300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.adminBlue, width: 2),
        ),
      ),
    );
  }
}
