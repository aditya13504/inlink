import 'dart:math';

/// Deterministic, bounded retry policy for the local delivery queue.
/// Actual transport acceptance is not a delivery receipt.
class DeliveryPolicy {
  const DeliveryPolicy({
    this.maxAttempts = 8,
    this.messageLifetime = const Duration(days: 7),
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 30),
  });

  final int maxAttempts;
  final Duration messageLifetime;
  final Duration baseDelay;
  final Duration maxDelay;

  DateTime expiryFor(DateTime createdAtUtc) =>
      createdAtUtc.toUtc().add(messageLifetime);

  Duration delayAfterAttempt(int attempt, {double jitterFactor = 0.2}) {
    if (attempt < 1) throw ArgumentError.value(attempt, 'attempt');
    if (jitterFactor < 0 || jitterFactor > 1) {
      throw ArgumentError.value(jitterFactor, 'jitterFactor');
    }
    final multiplier = pow(2, min(attempt - 1, 20)).toDouble();
    final rawMs = baseDelay.inMilliseconds * multiplier;
    final cappedMs = min(rawMs, maxDelay.inMilliseconds).toDouble();
    // Deterministic capped delay; jitteredBackoff adds random variation for
    // production queue attempts. jitterFactor is retained for test API clarity.
    return Duration(milliseconds: cappedMs.round());
  }

  bool isExpired(DateTime expiresAtUtc, DateTime nowUtc) =>
      !expiresAtUtc.toUtc().isAfter(nowUtc.toUtc());
}

/// Computes bounded exponential backoff with symmetric jitter.
Duration jitteredBackoff({
  required DeliveryPolicy policy,
  required int attempt,
  Random? random,
}) {
  final source = random ?? Random.secure();
  final base = policy.delayAfterAttempt(attempt, jitterFactor: 0);
  final factor = 0.8 + source.nextDouble() * 0.4;
  final millis = min(
    policy.maxDelay.inMilliseconds,
    (base.inMilliseconds * factor).round(),
  );
  return Duration(milliseconds: millis);
}
