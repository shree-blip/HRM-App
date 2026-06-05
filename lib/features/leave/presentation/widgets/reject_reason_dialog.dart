import 'package:flutter/material.dart';

/// Collects a rejection reason (required), mirroring RejectReasonDialog.
Future<String?> showRejectReasonDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Reject Leave'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Reason for rejection *',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  setState(() => error = 'Please enter a reason.');
                  return;
                }
                Navigator.pop(ctx, text);
              },
              child: const Text('Reject'),
            ),
          ],
        ),
      );
    },
  );
}
