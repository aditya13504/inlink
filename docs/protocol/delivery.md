# Delivery Semantics — Draft

- QUEUED: message is persisted locally.
- IN_TRANSIT: a transport or relay has accepted it; recipient delivery is not implied.
- DELIVERED: authenticated receipt from the recipient endpoint is verified.
- EXPIRED: configured expiry has passed without delivery.
- FAILED: a permanent, user-actionable failure has occurred.

Retries must use bounded exponential backoff with jitter. Message IDs must be deduplicated within a bounded retention window. Queue and retry limits must be explicit. Acknowledgements must be authenticated and bound to the relevant message ID.
