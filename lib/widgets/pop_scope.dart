import 'package:flutter/material.dart';

typedef PopScopeCallback = Future<void> Function(bool didPop, dynamic result);

class AppPopScope extends StatelessWidget {
  final Widget child;
  final bool canPop;
  final PopScopeCallback? onPopInvokedWithResult;

  const AppPopScope({
    super.key,
    required this.child,
    this.canPop = true,
    this.onPopInvokedWithResult,
  });

  @override
  Widget build(BuildContext context) {
    // Use PopScope (modern replacement for deprecated WillPopScope)
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (onPopInvokedWithResult != null) {
          await onPopInvokedWithResult!(didPop, result);
        }
      },
      child: child,
    );
  }
}
