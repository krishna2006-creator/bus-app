import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:agni_college_bus_tracker/providers/stop_prediction_provider.dart';

class DashboardPredictionWidget extends StatelessWidget {
  const DashboardPredictionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StopPredictionProvider>(
      builder: (context, provider, _) {
        final prediction = provider.prediction;
        if (prediction == null) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(16),
          elevation: 4,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.blueAccent,
              child: Icon(Icons.directions_bus, color: Colors.white),
            ),
            title: Text("Bus ${prediction.busNumber} is arriving"),
            subtitle: Text(
                "ETA: ${prediction.etaMinutes} mins • ${prediction.distanceKm.toStringAsFixed(1)} km"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => context.push('/student/stop-prediction'),
          ),
        );
      },
    );
  }
}
