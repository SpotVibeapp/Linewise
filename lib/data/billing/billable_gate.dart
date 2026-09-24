import '../../core/clock.dart';
import 'cost_model.dart';

/// Approval port — implemented by a confirmation dialog in the UI and by
/// scripted fakes in tests. Every provider request must pass through it.
abstract class UserApprovalPort {
  /// Returns true only after the user explicitly approves [estimate],
  /// having seen its full cost explanation.
  Future<bool> confirmProviderRequest(CreditCostEstimate estimate);
}

class SafeModeActiveException implements Exception {
  @override
  String toString() =>
      'Safe mode is ON: all The Odds API requests are disabled. '
      'Turn safe mode off in Settings to allow provider requests.';
}

class UnapprovedRequestException implements Exception {
  @override
  String toString() =>
      'Provider request was not approved. No request was sent and no credits '
      'were consumed.';
}

class MissingApiKeyException implements Exception {
  @override
  String toString() =>
      'No The Odds API key configured. Add your own key in Settings.';
}

/// Safe-mode + explicit-approval gate around every The Odds API call.
///
/// Contract:
/// * Safe mode ON ⇒ nothing leaves the device toward The Odds API.
/// * Every request (even 0-credit discovery) requires an explicit user
///   approval of the shown cost estimate.
/// * Billable requests show the zero-line warning in the estimate.
class BillableGate {
  BillableGate({
    required this.isSafeMode,
    required this.approval,
    required this.clock,
  });

  final bool Function() isSafeMode;
  final UserApprovalPort approval;
  final Clock clock;

  /// Runs [action] only if safe mode is off AND the user approves the estimate.
  Future<T> run<T>(
    CreditCostEstimate estimate,
    Future<T> Function() action,
  ) async {
    if (isSafeMode()) {
      throw SafeModeActiveException();
    }
    final approved = await approval.confirmProviderRequest(estimate);
    if (!approved) {
      throw UnapprovedRequestException();
    }
    return action();
  }
}
