import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A compact placeholder for heavy dashboard widgets that ship in a later
/// phase (Clock, Real-time attendance, Performance chart, Company calendar).
/// Keeps the dashboard layout matching the web app and offers correct
/// navigation into the eventual module.
class PlaceholderWidgetCard extends StatelessWidget {
  const PlaceholderWidgetCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.phase,
    this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int phase;
  final String? route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: route == null ? null : () => context.go(route!),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2,),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Phase $phase',
                              style: theme.textTheme.labelSmall,),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (route != null)
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,),
            ],
          ),
        ),
      ),
    );
  }
}
