import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agni_college_bus_tracker/theme.dart';
import 'package:agni_college_bus_tracker/services/bus_service.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';

class EditBusPage extends StatefulWidget {
  final Bus bus;

  const EditBusPage({super.key, required this.bus});

  @override
  State<EditBusPage> createState() => _EditBusPageState();
}

class _EditBusPageState extends State<EditBusPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _busNumberController;
  late TextEditingController _routeController;
  late TextEditingController _driverNameController;
  late TextEditingController _driverPhoneController;
  late TextEditingController _stopsController;
  late bool _isOperating;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _busNumberController = TextEditingController(text: widget.bus.busNumber);
    _routeController = TextEditingController(text: widget.bus.route);
    _driverNameController =
        TextEditingController(text: widget.bus.driverName ?? '');
    _driverPhoneController =
        TextEditingController(text: widget.bus.driverPhone ?? '');
    _stopsController = TextEditingController(text: widget.bus.stops.join(', '));
    _isOperating = widget.bus.isOperating;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final busService = context.read<BusService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final stops = _stopsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final updatedBus = Bus(
      id: widget.bus.id,
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
      await busService.updateBus(updatedBus);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Bus updated')));
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger
          .showSnackBar(SnackBar(content: Text('Failed to update bus: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Bus'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.adminBlue),
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
