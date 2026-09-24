import 'package:flutter/material.dart';

import '../data/billing/cost_model.dart';
import 'app.dart';

/// Pre-request cost preview dialog. Every provider request is preceded by
/// this dialog: it shows the request class, the full cost explanation and the
/// zero-line warning before the user can approve.
Future<bool> showBillableRequestDialog(
  BuildContext context,
  CreditCostEstimate estimate,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final isBillable = estimate.isBillable;
      return AlertDialog(
        title: Row(children: [
          Expanded(child: Text(isBillable ? 'Billable request' : 'Provider request')),
          RequestKindBadge(kind: estimate.kind),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(estimate.explanation),
            const SizedBox(height: 12),
            if (isBillable)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      estimate.zeroResultWarning,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade800),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            const Text(
              'No request has been sent yet. Confirming is explicit and can '
              'consume credits; declining sends nothing.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel — send nothing'),
          ),
          FilledButton(
            style: isBillable
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isBillable
                ? 'Approve — spend ~${estimate.credits} credit(s)'
                : 'Approve — 0 credits'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
