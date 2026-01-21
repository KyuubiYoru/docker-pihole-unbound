#!/bin/sh
# Cache warming script for Unbound
# Queries top domains from Pi-hole's FTL database to keep them fresh in cache

set -e

# Configuration (can be overridden via environment variables)
DAYS_BACK="${WARM_CACHE_DAYS:-3}"
MAX_DOMAINS="${WARM_CACHE_MAX:-500}"
UNBOUND_PORT="${UNBOUND_PORT:-5335}"
DELAY_MS="${WARM_CACHE_DELAY_MS:-10}"
PIHOLE_DB="/etc/pihole/pihole-FTL.db"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Pi-hole database exists
if [ ! -f "$PIHOLE_DB" ]; then
    log_error "Pi-hole FTL database not found at $PIHOLE_DB"
    exit 1
fi

# Check if dig is available
if ! command -v dig > /dev/null 2>&1; then
    log_error "dig command not found. Please install bind-tools."
    exit 1
fi

# Check if Unbound is responding
if ! dig @127.0.0.1 -p "$UNBOUND_PORT" +short +time=2 localhost > /dev/null 2>&1; then
    log_warn "Unbound may not be responding on port $UNBOUND_PORT, continuing anyway..."
fi

log_info "Extracting top $MAX_DOMAINS domains from the last $DAYS_BACK days..."

# Extract top domains that were NOT blocked (status 2 = forwarded/answered)
# Status codes: 0=unknown, 1=blocked (gravity), 2=forwarded, 3=cached, 4=regex blocked, etc.
DOMAINS=$(sqlite3 "$PIHOLE_DB" "
    SELECT domain 
    FROM queries 
    WHERE timestamp > strftime('%s', 'now', '-$DAYS_BACK days')
      AND status IN (2, 3)
      AND domain NOT LIKE '%arpa'
      AND domain NOT LIKE 'localhost%'
    GROUP BY domain 
    ORDER BY COUNT(*) DESC 
    LIMIT $MAX_DOMAINS;
" 2>/dev/null)

if [ -z "$DOMAINS" ]; then
    log_warn "No domains found in the database for the specified period."
    exit 0
fi

TOTAL=$(echo "$DOMAINS" | wc -l)
log_info "Found $TOTAL domains to warm up"

COUNT=0
FAILED=0
START_TIME=$(date +%s)

for domain in $DOMAINS; do
    COUNT=$((COUNT + 1))
    
    # Query A record
    if dig @127.0.0.1 -p "$UNBOUND_PORT" "$domain" A +short +time=5 +tries=1 > /dev/null 2>&1; then
        # Also query AAAA if A succeeded
        dig @127.0.0.1 -p "$UNBOUND_PORT" "$domain" AAAA +short +time=5 +tries=1 > /dev/null 2>&1 || true
    else
        FAILED=$((FAILED + 1))
    fi
    
    # Progress indicator every 50 domains
    if [ $((COUNT % 50)) -eq 0 ]; then
        log_info "Progress: $COUNT/$TOTAL domains processed..."
    fi
    
    # Small delay to avoid hammering upstream DNS
    if [ "$DELAY_MS" -gt 0 ]; then
        sleep "0.0$DELAY_MS" 2>/dev/null || sleep 1
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_info "Cache warming complete!"
log_info "  Domains processed: $COUNT"
log_info "  Failed lookups: $FAILED"
log_info "  Duration: ${DURATION}s"
