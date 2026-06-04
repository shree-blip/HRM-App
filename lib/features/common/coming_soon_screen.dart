import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell/app_drawer.dart';

/// Placeholder destination for modules not yet built. Keeps navigation
/// functional so the dashboard's links don't dead-end or crash.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.route,
    this.phase,
  });

  final String title;
  final String route;
  final int? phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: AppDrawer(currentRoute: route),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                phase != null
                    ? 'This module is coming in Phase $phase.'
                    : 'This module is coming in a later phase.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => context.go('/'),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
