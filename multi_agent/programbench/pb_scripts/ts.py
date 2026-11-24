"""Prefix every stdin line with a unix timestamp (seconds, 3 decimals) so the stream-json
log of each agent carries wall-clock time for latency analysis."""
import sys, time
for line in sys.stdin:
    sys.stdout.write(f"{time.time():.3f} {line}")
    sys.stdout.flush()
