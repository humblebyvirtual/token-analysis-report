#!/bin/bash

# analyze-with-vpn.sh - Run token analysis through VPNBook for OKX access

set -e

# Configuration
VPN_CONFIG="${HOME}/Downloads/vpnbook-us16-tcp443.ovpn"
VPN_PASSWORD="vpnbook"  # Update this to current VPNBook password
ANALYZER="./analyze-token.sh"
OKX_TEST="onchainos market memepump-token-details"

# Check args
if [ -z "$1" ]; then
    echo "Usage: $0 <TOKEN_ADDRESS> [--chain solana|base|bsc]"
    echo ""
    echo "Example: $0 BWJ7zJauzatao4FsBnGdVsqdBi3k5NbgSY62noZApump --chain solana"
    exit 1
fi

TOKEN="$1"
CHAIN_ARG=""
if [ "$2" == "--chain" ] && [ -n "$3" ]; then
    CHAIN_ARG="--chain $3"
fi

# Check files exist
if [ ! -f "$VPN_CONFIG" ]; then
    echo "Error: VPN config not found at $VPN_CONFIG"
    echo "Please download a .ovpn file from vpnbook.com and place it there."
    exit 1
fi

if [ ! -x "$ANALYZER" ]; then
    echo "Error: Analyzer not found at $ANALYZER"
    exit 1
fi

# Check if onchainos exists (needed for OKX)
if ! command -v onchainos &>/dev/null; then
    echo "Warning: onchainos CLI not found. Install it first:"
    echo "  npx @bnb-chain/mcp@latest"
    echo "Proceeding with RPC fallback only..."
    USE_VPN_FOR_OKX=false
else
    USE_VPN_FOR_OKX=true
fi

echo "=========================================="
echo "  VPN-Powered Token Analyzer"
echo "  Token: ${TOKEN:0:10}..."
echo "  Chain: ${CHAIN_ARG:-auto}"
echo "=========================================="
echo ""

# Start VPN in background
echo "Starting VPN (VPNBook)..."
sudo openvpn --config "$VPN_CONFIG" --daemon --writepid /tmp/vpnbook.pid --log /tmp/vpnbook.log

# Wait for VPN to be ready (tun0 interface)
echo -n "Waiting for VPN connection"
for i in {1..30}; do
    if ip addr show tun0 &>/dev/null; then
        echo " ✅"
        break
    fi
    echo -n "."
    sleep 1
done

if ! ip addr show tun0 &>/dev/null; then
    echo " ❌ VPN failed to start (no tun0 interface)."
    echo "Check logs: sudo cat /tmp/vpnbook.log"
    exit 1
fi

# Verify IP changed
VPN_IP=$(curl -s ifconfig.me)
echo "VPN IP: $VPN_IP"

# Test OKX reachability if we plan to use it
if [ "$USE_VPN_FOR_OKX" = true ]; then
    echo "Testing OKX API through VPN..."
    if onchainos market memepump-token-details "$TOKEN" --chain solana &>/dev/null; then
        echo "✅ OKX API reachable — will use accurate metrics"
    else
        echo "⚠️  OKX API still unreachable — falling back to RPC"
    fi
fi

echo ""
echo "Running analyzer..."
echo "-------------------------------------------"

# Run analyzer (it will use onchainos automatically if available)
if [ -n "$CHAIN_ARG" ]; then
    "$ANALYZER" "$TOKEN" $CHAIN_ARG
else
    "$ANALYZER" "$TOKEN"
fi

echo ""
echo "-------------------------------------------"
echo "Analysis complete."

# Ask if user wants to stop VPN
read -p "Disconnect VPN? (y/N): " -r DISCONNECT
if [[ "$DISCONNECT" =~ ^[Yy]$ ]]; then
    echo "Stopping VPN..."
    if [ -f /tmp/vpnbook.pid ]; then
        sudo kill "$(cat /tmp/vpnbook.pid)" 2>/dev/null || true
        rm -f /tmp/vpnbook.pid
    else
        sudo pkill -f "openvpn.*$VPN_CONFIG" 2>/dev/null || true
    fi
    echo "VPN stopped."
else
    echo "VPN left running. Disconnect later with: sudo kill \$(cat /tmp/vpnbook.pid) 2>/dev/null || sudo pkill -f openvpn"
fi
