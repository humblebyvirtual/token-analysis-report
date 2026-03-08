#!/bin/bash

# Universal Token Analyzer Script
# Supports Solana (via QuickNode/Helius) and Base (via BaseScan scraping)
# Usage: ./analyze-token.sh <TOKEN_ADDRESS> [--chain solana|base]

# Configuration
QUICKNODE_SOLANA_ENDPOINT="${QUICKNODE_SOLANA_ENDPOINT:-}"
HELIUS_SOLANA_ENDPOINT="${HELIUS_SOLANA_ENDPOINT:-https://mainnet.helius-rpc.com/?api-key=0916cf57-c291-4224-8f46-3918438de6ba}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Help
if [ -z "$1" ] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo -e "${CYAN}Universal Token Analyzer${NC}"
    echo ""
    echo "Usage: $0 <TOKEN_ADDRESS> [--chain solana|base|bsc]"
    echo ""
    echo "Examples:"
    echo "  $0 Dst6VcVu93sjex2t1i2yzWPEdtFijLjMGYsq2uMKpump --chain solana"
    echo "  $0 0x5bdc2d52adf52e7c510e17a79310a45d80d14b07 --chain base"
    echo "  $0 0xACEF48622c189ffAdB7E697b62d7656a8cfD3d67 --chain bsc"
    echo ""
    echo "Environment variables:"
    echo "  QUICKNODE_SOLANA_ENDPOINT - your Solana QuickNode endpoint URL"
    echo "  HELIUS_SOLANA_ENDPOINT   - your Helius endpoint (has default)"
    echo ""
    exit 0
fi

TOKEN=$1
CHAIN=""

# Parse chain argument
if [ "$2" == "--chain" ] && [ -n "$3" ]; then
    CHAIN=$3
fi

# Auto-detect chain if not specified
if [ -z "$CHAIN" ]; then
    if [[ "$TOKEN" =~ ^[1-9A-HJ-NP-Za-km-z]{32,44}$ ]]; then
        CHAIN="solana"
    elif [[ "$TOKEN" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        CHAIN="base"
    else
        echo -e "${YELLOW}Could not auto-detect chain. Please specify --chain solana, base, or bsc${NC}"
        exit 1
    fi
fi

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}   TOKEN ANALYZER${NC}"
echo -e "${CYAN}   Chain: $CHAIN${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# Fetch token metadata from DexScreener
DEX_DATA=$(curl -s "https://api.dexscreener.com/latest/dex/tokens/$TOKEN" 2>/dev/null)

if [ ! -z "$DEX_DATA" ]; then
    NAME=$(echo $DEX_DATA | python3 -c "
import sys,json
d=json.load(sys.stdin)
# Try top-level token symbol first, then fallback to first pair baseToken
symbol = d.get('token',{}).get('symbol')
if not symbol:
    pairs = d.get('pairs',[])
    if pairs:
        symbol = pairs[0].get('baseToken',{}).get('symbol')
print(symbol or 'Unknown')" 2>/dev/null)
    MC=$(echo $DEX_DATA | python3 -c "
import sys,json
d=json.load(sys.stdin)
# MarketCap may be in quoteToken or in first pair
mc = d.get('quoteToken',{}).get('marketCap')
if not mc or mc == 'None':
    pairs = d.get('pairs',[])
    if pairs:
        mc = pairs[0].get('marketCap')
print(mc or 'Unknown')" 2>/dev/null)
    PRICE=$(echo $DEX_DATA | python3 -c "
import sys,json
d=json.load(sys.stdin)
price = d.get('priceUsd')
if not price or price == 'None':
    pairs = d.get('pairs',[])
    if pairs:
        price = pairs[0].get('priceUsd')
print(price or 'Unknown')" 2>/dev/null)
    VOLUME=$(echo $DEX_DATA | python3 -c "
import sys,json
d=json.load(sys.stdin)
vol = d.get('volume24h')
if not vol or vol == 'None':
    pairs = d.get('pairs',[])
    if pairs:
        vol = pairs[0].get('volume24h')
print(vol or 'Unknown')" 2>/dev/null)
    
    # CoinGecko fallback if DexScreener missing price or volume
    if [ "$PRICE" = "Unknown" ] || [ "$VOLUME" = "Unknown" ]; then
        # Fetch CoinGecko data with token address as provided
        CG_URL="https://api.coingecko.com/api/v3/simple/token_price/solana?contract_addresses=$TOKEN&vs_currencies=usd&include_24hr_vol=true&include_24hr_change=true"
        CG_RESP=$(curl -s "$CG_URL")
        # Test if valid JSON with token data
        if echo "$CG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(1 if '$TOKEN' in d else 0)" 2>/dev/null | grep -q 1; then
            if [ "$PRICE" = "Unknown" ]; then
                PRICE=$(echo "$CG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$TOKEN',{}).get('usd','Unknown'))" 2>/dev/null)
            fi
            if [ "$VOLUME" = "Unknown" ]; then
                VOLUME=$(echo "$CG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$TOKEN',{}).get('usd_24h_vol','Unknown'))" 2>/dev/null)
            fi
        fi
    fi
    
    echo -e "${BLUE}📊 Token: $NAME${NC}"
    echo -e "${BLUE}💰 MC: $MC${NC}"
    echo -e "${BLUE}💵 Price: $PRICE${NC}"
    echo -e "${BLUE}📈 24h Volume: ${VOLUME}${NC}"
    echo ""
fi

# ========== SOLANA PATH ==========
if [ "$CHAIN" = "solana" ]; then
    echo -e "${CYAN}🔍 Fetching Solana holder data...${NC}"
    echo ""
    
    # Determine endpoint
    RPC_ENDPOINT=""
    if [ -n "$QUICKNODE_SOLANA_ENDPOINT" ]; then
        RPC_ENDPOINT="$QUICKNODE_SOLANA_ENDPOINT"
        echo "Using QuickNode endpoint"
    else
        RPC_ENDPOINT="$HELIUS_SOLANA_ENDPOINT"
        echo "Using Helius endpoint (set QUICKNODE_SOLANA_ENDPOINT for QuickNode)"
    fi
    
    # Get holder data
    HOLDER_RESPONSE=$(curl -s "$RPC_ENDPOINT" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTokenLargestAccounts\",\"params\":[\"$TOKEN\",{\"limit\":10,\"commitment\":\"finalized\"}]}" 2>/dev/null)

    # Mint & Freeze Authority Check
    echo ""
    echo -e "${YELLOW}🔐 MINT & FREEZE AUTHORITIES${NC}"
    ACCOUNT_INFO=$(curl -s "$RPC_ENDPOINT" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getAccountInfo\",\"params\":[\"$TOKEN\",{\"encoding\":\"jsonParsed\"}]}" 2>/dev/null)

    MINT_AUTH=$(echo "$ACCOUNT_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('value',{}).get('data',{}).get('parsed',{}).get('info',{}).get('mintAuthority','Unknown'))" 2>/dev/null)
    FREEZE_AUTH=$(echo "$ACCOUNT_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('value',{}).get('data',{}).get('parsed',{}).get('info',{}).get('freezeAuthority','Unknown'))" 2>/dev/null)

    if [ "$MINT_AUTH" = "None" ] && [ "$FREEZE_AUTH" = "None" ]; then
        echo -e "  ${GREEN}✅ Mint: renounced${NC}"
        echo -e "  ${GREEN}✅ Freeze: renounced${NC}"
    elif [ "$MINT_AUTH" != "None" ]; then
        echo -e "  ${RED}🔴 Mint: ACTIVE (address: ${MINT_AUTH:0:10}...)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Mint: ${MINT_AUTH}${NC}"
    fi
    if [ "$FREEZE_AUTH" != "None" ]; then
        echo -e "  ${RED}🔴 Freeze: ACTIVE (address: ${FREEZE_AUTH:0:10}...)${NC}"
    fi
    echo ""

    # LP Lock Check (for Pump.fun tokens)
    echo -e "${YELLOW}🔒 LIQUIDITY LOCK STATUS${NC}"
    if command -v python3 &>/dev/null; then
        LP_OUTPUT=$(python3 /home/nodos/check-lplock.py "$TOKEN" 2>&1 | grep -v "^$" | head -5)
        if [ -z "$LP_OUTPUT" ]; then
            echo -e "  ${CYAN}ℹ️  LP lock analysis unavailable${NC}"
        else
            echo "$LP_OUTPUT" | sed 's/^/  /'
        fi
    else
        echo -e "  ${YELLOW}⚠️  python3 not available — LP check skipped${NC}"
    fi
    echo ""

    # Creator Wallet Age Check
    echo -e "${YELLOW}👴 CREATOR WALLET AGE (Top Holder)${NC}"
    TOP_HOLDER=$(echo "$HOLDER_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d.get('result',{}).get('value',[]); print(v[0]['address'] if v else '')" 2>/dev/null)
    if [ -n "$TOP_HOLDER" ]; then
        SIG_RESP=$(curl -s "$RPC_ENDPOINT" \
            -X POST \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getSignaturesForAddress\",\"params\":[\"$TOP_HOLDER\",{\"limit\":1}]}" 2>/dev/null)
        BLOCK_TIME=$(echo "$SIG_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); s=d.get('result',[{}])[0]; print(s.get('blockTime',''))" 2>/dev/null)
        if [ -n "$BLOCK_TIME" ] && [ "$BLOCK_TIME" != "None" ]; then
            AGE_H=$(( ( $(date +%s) - BLOCK_TIME ) / 3600 ))
            if [ $AGE_H -lt 48 ]; then
                echo -e "  ${RED}🆕 Top holder wallet is FRESH (${AGE_H}h old)${NC}"
            else
                echo -e "  ${GREEN}✅ Top holder wallet age: ${AGE_H}h${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠️  Could not determine age (no txs or API limit)${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  No top holder data${NC}"
    fi
    echo ""
    
    if echo "$HOLDER_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'result' in d else 1)" 2>/dev/null; then
        # Success - parse and display
        echo "$HOLDER_RESPONSE" | python3 -c "
import sys,json

data=json.load(sys.stdin)
value=data.get('result',{}).get('value',[])
if not value:
    print('No holder data returned (token may have no holders)')
    sys.exit(0)

total=sum(float(h.get('uiAmount',0)) for h in value)
print(f'Top 10 holders:')
print('')
print('Rank  Address               Amount              %     Flag')
print('----  -------------------  -----------------  -----  ------')
for i,h in enumerate(value[:10], 1):
    addr=h.get('address','Unknown')
    amount=float(h.get('uiAmount',0))
    pct=(amount/total*100) if total > 0 else 0
    
    flag=''
    if pct > 50:
        flag='🔴 CRITICAL'
    elif pct > 20:
        flag='🚨 HIGH'
    elif pct > 10:
        flag='⚠️ MEDIUM'
    
    print(f'{i:4}  {addr[:18]:18}  {amount:>17,.0f}  {pct:>6.1f}%  {flag}')
" 2>/dev/null
        
        # Concentration metrics
        TOP1_PCT=$(echo "$HOLDER_RESPONSE" | python3 -c "
import sys,json
data=json.load(sys.stdin)
value=data.get('result',{}).get('value',[])
total=sum(float(h.get('uiAmount',0)) for h in value)
top1=float(value[0].get('uiAmount',0)) if value else 0
print(round(top1/total*100,1))" 2>/dev/null)
        
        TOP5_PCT=$(echo "$HOLDER_RESPONSE" | python3 -c "
import sys,json
data=json.load(sys.stdin)
value=data.get('result',{}).get('value',[])
total=sum(float(h.get('uiAmount',0)) for h in value)
top5=sum(float(h.get('uiAmount',0)) for h in value[:5])
print(round(top5/total*100,1))" 2>/dev/null)
        
        echo ""
        echo -e "${YELLOW}📊 CONCENTRATION:${NC}"
        echo "  Top 1:  ${TOP1_PCT}%"
        echo "  Top 5:  ${TOP5_PCT}%"
        echo ""
        
        # Bundling check (already added after mint/freeze check)
        echo -e "${YELLOW}🔗 BUNDLING CHECK (Top 10):${NC}"
        echo "$HOLDER_RESPONSE" | python3 -c "
import sys,json
data=json.load(sys.stdin)
value=data.get('result',{}).get('value',[])
if len(value) < 2:
    print('Not enough holders to compare')
    sys.exit(0)
for i in range(min(9, len(value)-1)):
    amt_i=float(value[i].get('uiAmount',0))
    amt_next=float(value[i+1].get('uiAmount',0))
    if amt_i == 0:
        continue
    diff=abs(amt_i-amt_next)/amt_i*100
    status='✅ BUNDLED' if diff < 1 else f'{diff:.1f}% diff'
    print(f'  Rank {i+1:2} vs {i+2:2}: {status}')
" 2>/dev/null
        
    else
        echo -e "${RED}❌ Error fetching holder data from Solana RPC${NC}"
        echo "Check: Endpoint reachable, API key valid, token address correct"
        exit 1
    fi

# ========== BASE PATH ==========
elif [ "$CHAIN" = "base" ]; then
    echo -e "${CYAN}🔍 Fetching Base holder data (via BaseScan)...${NC}"
    echo ""
    echo "Note: Base holder data requires manual scraping or paid API."
    echo "Attempting to fetch from BaseScan holders table..."
    echo ""
    
    # Try to fetch the holders HTML table from BaseScan
    HOLDERS_HTML=$(curl -s "https://basescan.org/token/generic-tokenholders2?a=$TOKEN&ps=100&p=1" 2>/dev/null)
    
    if echo "$HOLDERS_HTML" | grep -q "quickExportTokenHolerData"; then
        # Extract the data array string
        JS_LINE=$(echo "$HOLDERS_HTML" | grep -o "quickExportTokenHolerData = '[^']*'" | head -1)
        
        if [ -n "$JS_LINE" ]; then
            # Extract the JSON array part (between single quotes)
            JSON_ARRAY=$(echo "$JS_LINE" | sed "s/quickExportTokenHolerData = '//;s/'$//")
            
            if [ -n "$JSON_ARRAY" ]; then
                echo "$JSON_ARRAY" | python3 -c '
import json
import sys

data_str = sys.stdin.read()

try:
    data = json.loads(data_str)
except json.JSONDecodeError as e:
    print(f"Parse error: {e}")
    sys.exit(1)

print(f"Top 10 holders:")
print("")
print("Rank  Address               Amount              % (of top 10 sum)")
print("----  -------------------  -----------------  -----")

# Compute sum of top 10 for relative percentages
top10 = data[:10]
sum_top10 = 0
for row in top10:
    qty_str = row[3].replace(",", "")
    try:
        qty = float(qty_str)
        sum_top10 += qty
    except:
        continue

for i, row in enumerate(top10, 1):
    addr = row[1][:18]
    qty_str = row[3].replace(",", "")
    try:
        qty = float(qty_str)
    except:
        qty = 0
    pct = (qty / sum_top10 * 100) if sum_top10 > 0 else 0
    print(f"{i:4}  {addr:18}  {qty:>17,.0f}  {pct:>6.1f}%")

# Concentration of top 5 relative to top 10 sum
if sum_top10 > 0:
    top5_sum = 0
    for row in top10[:5]:
        qty_str = row[3].replace(",", "")
        try:
            top5_sum += float(qty_str)
        except:
            pass
    top5_pct = (top5_sum / sum_top10 * 100) if sum_top10 > 0 else 0
    print("")
    print(f"Top 5 concentration (of top 10): {top5_pct:.1f}%")
    print("Note: Without total supply, percentages are relative to top 10 sum only.")
' 2>/dev/null
                echo ""
                echo -e "${YELLOW}📊 Note:${NC} Full token supply needed for accurate concentration metrics."
                echo "To get total supply on Base, use RPC call 0x18160ddd or visit BaseScan token page."
                echo ""
                echo -e "${CYAN}⚠️  BaseScan scraping is limited; consider a paid API for automation${NC}"
            else
                echo -e "${YELLOW}⚠️  Could not extract holder data array from BaseScan page${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Could not find holder data line on BaseScan page${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  BaseScan did not return holder data (token may have no holders or requires API)${NC}"
    fi

# ========== BSC PATH ==========
elif [ "$CHAIN" = "bsc" ]; then
    echo -e "${CYAN}🔍 Fetching BSC holder data (via BscScan)...${NC}"
    echo ""
    echo "Note: BSC holder data requires manual scraping or paid API."
    echo "Attempting to fetch from BscScan holders table..."
    echo ""
    
    # Try to fetch the holders HTML table from BscScan
    HOLDERS_HTML=$(curl -s "https://bscscan.com/token/generic-tokenholders2?a=$TOKEN&ps=100&p=1" 2>/dev/null)
    
    if echo "$HOLDERS_HTML" | grep -q "quickExportTokenHolerData"; then
        # Extract the data array string
        JS_LINE=$(echo "$HOLDERS_HTML" | grep -o "quickExportTokenHolerData = '[^']*'" | head -1)
        
        if [ -n "$JS_LINE" ]; then
            # Extract the JSON array part (between single quotes)
            JSON_ARRAY=$(echo "$JS_LINE" | sed "s/quickExportTokenHolerData = '//;s/'$//")
            
            if [ -n "$JSON_ARRAY" ]; then
                echo "$JSON_ARRAY" | python3 -c '
import json
import sys

data_str = sys.stdin.read()

try:
    data = json.loads(data_str)
except json.JSONDecodeError as e:
    print(f"Parse error: {e}")
    sys.exit(1)

print(f"Top 10 holders:")
print("")
print("Rank  Address               Amount              % (of top 10 sum)")
print("----  -------------------  -----------------  -----")

# Compute sum of top 10 for relative percentages
top10 = data[:10]
sum_top10 = 0
for row in top10:
    qty_str = row[3].replace(",", "")
    try:
        qty = float(qty_str)
        sum_top10 += qty
    except:
        continue

for i, row in enumerate(top10, 1):
    addr = row[1][:18]
    qty_str = row[3].replace(",", "")
    try:
        qty = float(qty_str)
    except:
        qty = 0
    pct = (qty / sum_top10 * 100) if sum_top10 > 0 else 0
    print(f"{i:4}  {addr:18}  {qty:>17,.0f}  {pct:>6.1f}%")

# Concentration of top 5 relative to top 10 sum
if sum_top10 > 0:
    top5_sum = 0
    for row in top10[:5]:
        qty_str = row[3].replace(",", "")
        try:
            top5_sum += float(qty_str)
        except:
            pass
    top5_pct = (top5_sum / sum_top10 * 100) if sum_top10 > 0 else 0
    print("")
    print(f"Top 5 concentration (of top 10): {top5_pct:.1f}%")
    print("Note: Without total supply, percentages are relative to top 10 sum only.")
' 2>/dev/null
                echo ""
                echo -e "${YELLOW}📊 Note:${NC} Full token supply needed for accurate concentration metrics."
                echo "To get total supply on BSC, use BscScan RPC or visit token page."
                echo ""
                echo -e "${CYAN}⚠️  BscScan scraping is limited; consider a paid API for automation${NC}"
            else
                echo -e "${YELLOW}⚠️  Could not extract holder data array from BscScan page${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Could not find holder data line on BscScan page${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  BscScan did not return holder data (token may have no holders or requires API)${NC}"
    fi

else
    echo -e "${RED}❌ Unsupported chain: $CHAIN${NC}"
    echo "Supported: solana, base, bsc"
    exit 1
fi

echo ""
echo -e "${CYAN}======================================${NC}"
echo ""
echo "💡 Tip: Always DYOR and check socials before investing!"
echo ""
