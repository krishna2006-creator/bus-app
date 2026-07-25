import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/theme.dart';

class ManageDriversPage extends StatefulWidget {
  const ManageDriversPage({super.key});

  @override
  State<ManageDriversPage> createState() => _ManageDriversPageState();
}

class _ManageDriversPageState extends State<ManageDriversPage> {
  List<User> _backendDrivers = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchDriversFromBackend();
  }

  Future<void> _fetchDriversFromBackend() async {
    setState(() => _loading = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/drivers'),
        headers: await ApiService.getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _backendDrivers =
            data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching drivers from backend: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final drivers = _backendDrivers.isNotEmpty
        ? _backendDrivers
        : auth.users.where((u) => u.role == UserRole.driver).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Drivers'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDriversFromBackend,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: drivers.length,
              itemBuilder: (context, index) {
                final d = drivers[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: ListTile(
                    title: Text(d.name ?? d.id),
                    subtitle: Text(
                        'ID: ${d.id} • Bus: ${d.assignedBusNumber ?? 'N/A'}\nPhone: ${d.phone ?? 'N/A'}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openEditDialog(context, d),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _openEditDialog(BuildContext context, User driver) {
    final idCtrl = TextEditingController(text: driver.id);
    final passCtrl = TextEditingController(text: driver.password ?? '');
    final nameCtrl = TextEditingController(text: driver.name ?? '');
    final phoneCtrl = TextEditingController(text: driver.phone ?? '');
    final busCtrl = TextEditingController(text: driver.assignedBusNumber ?? '');

    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Driver'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: idCtrl,
                    decoration: const InputDecoration(labelText: 'User ID')),
                const SizedBox(height: 8),
                TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true),
                const SizedBox(height: 8),
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 8),
                TextField(
                    controller: busCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Assigned Bus Number (e.g. 1, 2)')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final newId = idCtrl.text.trim();
                final newPwd = passCtrl.text.trim();
                final newName = nameCtrl.text.trim();
                final newPhone = phoneCtrl.text.trim();
                final newBus = busCtrl.text.trim();

                if (newId.isEmpty) {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('User ID is required')));
                  return;
                }

                // Try backend update
                try {
                  final busId = newBus.isNotEmpty ? int.tryParse(newBus) : null;
                  final updateBody = <String, dynamic>{
                    'full_name': newName.isEmpty ? null : newName,
                    'phone': newPhone.isEmpty ? null : newPhone,
                  };
                  if (newPwd.isNotEmpty) {
                    updateBody['password'] = newPwd;
                  }
                  if (busId != null) {
                    updateBody['assigned_bus_id'] = busId;
                  }

                  final response = await http.put(
                    Uri.parse('${ApiService.baseUrl}/drivers/$newId'),
                    headers: await ApiService.getHeaders(),
                    body: json.encode(updateBody),
                  );

                  if (response.statusCode == 200) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Driver updated successfully')));
                    await _fetchDriversFromBackend();
                    nav.pop();
                    return;
                  }
                } catch (e) {
                  debugPrint(
                      'Backend update failed, falling back to local: $e');
                }

                // Fallback to local update
                if (newId != driver.id) {
                  if (auth.users.any((u) => u.id == newId)) {
                    messenger.showSnackBar(
                        const SnackBar(content: Text('ID already exists')));
                    return;
                  }
                  await auth.changeUserId(driver.id, newId);
                }

                final updated = driver.copyWith(
                  id: newId,
                  password: newPwd.isNotEmpty ? newPwd : driver.password,
                  name: newName.isEmpty ? null : newName,
                  phone: newPhone.isEmpty ? null : newPhone,
                  assignedBusNumber: newBus.isEmpty ? null : newBus,
                );

                await auth.updateUser(updated);
                messenger.showSnackBar(
                    const SnackBar(content: Text('Driver updated locally')));
                nav.pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
