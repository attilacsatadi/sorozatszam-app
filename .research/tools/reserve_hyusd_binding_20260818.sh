#!/usr/bin/env bash
set -euo pipefail

: "${CAST:?CAST required}"
: "${RPC_URL:?RPC_URL required}"
: "${RTOKEN:?RTOKEN required}"
: "${EXPECTED_MAIN:?EXPECTED_MAIN required}"
: "${EXPECTED_BASKET:?EXPECTED_BASKET required}"
: "${EXPECTED_BM:?EXPECTED_BM required}"
: "${EXPECTED_STRSR:?EXPECTED_STRSR required}"
: "${COLLATERAL:?COLLATERAL required}"
: "${WRAPPER:?WRAPPER required}"
: "${EXPECTED_POOL:?EXPECTED_POOL required}"
: "${EXPECTED_GAUGE:?EXPECTED_GAUGE required}"
: "${AERO:?AERO required}"
: "${RESULT_DIR:?RESULT_DIR required}"

mkdir -p evidence "$RESULT_DIR"
BLOCK="$($CAST block-number --rpc-url "$RPC_URL")"
HASH="$($CAST block "$BLOCK" --rpc-url "$RPC_URL" --field hash)"
{
  echo "chain_id=$($CAST chain-id --rpc-url "$RPC_URL")"
  echo "block=$BLOCK"
  echo "block_hash=$HASH"
  echo "timestamp_utc=$(date -u +%FT%TZ)"
} | tee evidence/environment.txt

call_raw() {
  local key="$1" address="$2" sig="$3"; shift 3
  local out err rc
  err=$(mktemp)
  set +e
  out=$($CAST call --rpc-url "$RPC_URL" --block "$BLOCK" "$address" "$sig" "$@" 2>"$err")
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    printf '%s\tPASS\t%s\n' "$key" "$(printf '%s' "$out" | tr '\n' ';')" | tee -a evidence/calls.tsv
  else
    printf '%s\tFAIL\t%s\n' "$key" "$(tr '\n' ';' < "$err")" | tee -a evidence/calls.tsv
  fi
  rm -f "$err"
}
value() {
  awk -F '\t' -v k="$1" '$1==k && $2=="PASS" {sub(/;$/, "", $3); print $3; exit}' evidence/calls.tsv
}
address_value() {
  value "$1" | grep -Eo '0x[0-9a-fA-F]{40}' | head -1 | tr '[:upper:]' '[:lower:]'
}
lower() { tr '[:upper:]' '[:lower:]'; }

: > evidence/calls.tsv
call_raw rtoken_name "$RTOKEN" 'name()(string)'
call_raw rtoken_symbol "$RTOKEN" 'symbol()(string)'
call_raw rtoken_main "$RTOKEN" 'main()(address)'
call_raw rtoken_total_supply "$RTOKEN" 'totalSupply()(uint256)'
call_raw rtoken_baskets_needed "$RTOKEN" 'basketsNeeded()(uint192)'
call_raw rtoken_issuance_available "$RTOKEN" 'issuanceAvailable()(uint256)'
call_raw rtoken_redemption_available "$RTOKEN" 'redemptionAvailable()(uint256)'

MAIN=$(address_value rtoken_main)
call_raw main_basket_handler "$MAIN" 'basketHandler()(address)'
call_raw main_backing_manager "$MAIN" 'backingManager()(address)'
call_raw main_st_rsr "$MAIN" 'stRSR()(address)'
call_raw main_rsr "$MAIN" 'rsr()(address)'
call_raw main_issuance_paused "$MAIN" 'issuancePaused()(bool)'
call_raw main_issuance_paused_or_frozen "$MAIN" 'issuancePausedOrFrozen()(bool)'
call_raw main_trading_paused_or_frozen "$MAIN" 'tradingPausedOrFrozen()(bool)'
call_raw main_frozen "$MAIN" 'frozen()(bool)'

BASKET=$(address_value main_basket_handler)
BM=$(address_value main_backing_manager)
STRSR=$(address_value main_st_rsr)
RSR=$(address_value main_rsr)

call_raw basket_enable_issuance_premium "$BASKET" 'enableIssuancePremium()(bool)'
call_raw basket_nonce "$BASKET" 'nonce()(uint48)'
NONCE=$(value basket_nonce | grep -Eo '^[0-9]+' | head -1)
call_raw basket_historical "$BASKET" 'getHistoricalBasket(uint48)(address[],uint256[])' "$NONCE"
call_raw basket_prime "$BASKET" 'getPrimeBasket()(address[],bytes32[],uint192[])'
call_raw basket_quantity_wrapper "$BASKET" 'quantity(address)(uint192)' "$WRAPPER"
call_raw basket_price_without_premium "$BASKET" 'price(bool)(uint192,uint192)' false
call_raw basket_price_with_premium "$BASKET" 'price(bool)(uint192,uint192)' true
call_raw basket_fully_collateralized "$BASKET" 'fullyCollateralized()(bool)'
call_raw basket_status "$BASKET" 'status()(uint8)'
call_raw basket_is_ready "$BASKET" 'isReady()(bool)'

call_raw collateral_erc20 "$COLLATERAL" 'erc20()(address)'
call_raw collateral_pool "$COLLATERAL" 'pool()(address)'
call_raw collateral_status "$COLLATERAL" 'status()(uint8)'
call_raw collateral_saved_peg_price "$COLLATERAL" 'savedPegPrice()(uint192)'
call_raw collateral_last_save "$COLLATERAL" 'lastSave()(uint48)'
call_raw collateral_ref_per_tok "$COLLATERAL" 'refPerTok()(uint192)'
call_raw collateral_price "$COLLATERAL" 'price()(uint192,uint192)'
call_raw collateral_token0_price "$COLLATERAL" 'tokenPrice(uint8)(uint192,uint192)' 0
call_raw collateral_token1_price "$COLLATERAL" 'tokenPrice(uint8)(uint192,uint192)' 1
call_raw collateral_token0_reserve "$COLLATERAL" 'tokenReserve(uint8)(uint192)' 0
call_raw collateral_token1_reserve "$COLLATERAL" 'tokenReserve(uint8)(uint192)' 1

call_raw wrapper_underlying "$WRAPPER" 'underlying()(address)'
call_raw wrapper_gauge "$WRAPPER" 'gauge()(address)'
call_raw wrapper_reward_token "$WRAPPER" 'rewardToken()(address)'
call_raw wrapper_total_supply "$WRAPPER" 'totalSupply()(uint256)'
call_raw wrapper_bm_balance "$WRAPPER" 'balanceOf(address)(uint256)' "$BM"
call_raw wrapper_strsr_balance "$WRAPPER" 'balanceOf(address)(uint256)' "$STRSR"

GAUGE=$(address_value wrapper_gauge)
POOL=$(address_value wrapper_underlying)
call_raw gauge_staking_token "$GAUGE" 'stakingToken()(address)'
call_raw gauge_reward_token "$GAUGE" 'rewardToken()(address)'
call_raw gauge_wrapper_balance "$GAUGE" 'balanceOf(address)(uint256)' "$WRAPPER"
call_raw gauge_wrapper_earned "$GAUGE" 'earned(address)(uint256)' "$WRAPPER"

call_raw pool_token0 "$POOL" 'token0()(address)'
call_raw pool_token1 "$POOL" 'token1()(address)'
call_raw pool_stable "$POOL" 'stable()(bool)'
call_raw pool_reserve0 "$POOL" 'reserve0()(uint256)'
call_raw pool_reserve1 "$POOL" 'reserve1()(uint256)'
call_raw pool_total_supply "$POOL" 'totalSupply()(uint256)'
call_raw pool_wrapper_idle_balance "$POOL" 'balanceOf(address)(uint256)' "$WRAPPER"

call_raw strsr_total_supply "$STRSR" 'totalSupply()(uint256)'
call_raw strsr_exchange_rate "$STRSR" 'exchangeRate()(uint192)'
call_raw rsr_strsr_balance "$RSR" 'balanceOf(address)(uint256)' "$STRSR"

HIST=$(value basket_historical | tr '[:upper:]' '[:lower:]')
PRIME=$(value basket_prime | tr '[:upper:]' '[:lower:]')
WRAP_LC=$(echo "$WRAPPER" | lower)
hist_member=false; prime_member=false
grep -q "$WRAP_LC" <<<"$HIST" && hist_member=true
grep -q "$WRAP_LC" <<<"$PRIME" && prime_member=true

P0=$(value basket_price_without_premium)
P1=$(value basket_price_with_premium)
premium_price_differs=false
[ "$P0" != "$P1" ] && premium_price_differs=true

graph_pass=true
[ "$MAIN" = "$(echo "$EXPECTED_MAIN" | lower)" ] || graph_pass=false
[ "$BASKET" = "$(echo "$EXPECTED_BASKET" | lower)" ] || graph_pass=false
[ "$BM" = "$(echo "$EXPECTED_BM" | lower)" ] || graph_pass=false
[ "$STRSR" = "$(echo "$EXPECTED_STRSR" | lower)" ] || graph_pass=false
[ "$(address_value collateral_erc20)" = "$WRAP_LC" ] || graph_pass=false
[ "$(address_value collateral_pool)" = "$(echo "$EXPECTED_POOL" | lower)" ] || graph_pass=false
[ "$POOL" = "$(echo "$EXPECTED_POOL" | lower)" ] || graph_pass=false
[ "$GAUGE" = "$(echo "$EXPECTED_GAUGE" | lower)" ] || graph_pass=false
[ "$(address_value wrapper_reward_token)" = "$(echo "$AERO" | lower)" ] || graph_pass=false
[ "$(address_value gauge_staking_token)" = "$(echo "$EXPECTED_POOL" | lower)" ] || graph_pass=false
[ "$(address_value gauge_reward_token)" = "$(echo "$AERO" | lower)" ] || graph_pass=false

{
  echo "graph_pass=$graph_pass"
  echo "historical_basket_contains_wrapper=$hist_member"
  echo "prime_basket_contains_wrapper=$prime_member"
  echo "enable_issuance_premium=$(value basket_enable_issuance_premium)"
  echo "saved_peg_price=$(value collateral_saved_peg_price)"
  echo "price_without_premium=$P0"
  echo "price_with_premium=$P1"
  echo "premium_price_differs=$premium_price_differs"
  echo "issuance_paused_or_frozen=$(value main_issuance_paused_or_frozen)"
  echo "issuance_available=$(value rtoken_issuance_available)"
  echo "total_supply=$(value rtoken_total_supply)"
  echo "collateral_status=$(value collateral_status)"
  echo "basket_status=$(value basket_status)"
  echo "basket_ready=$(value basket_is_ready)"
  echo "basket_fully_collateralized=$(value basket_fully_collateralized)"
} | tee evidence/verdict.txt

rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"
cp evidence/* "$RESULT_DIR/"
find "$RESULT_DIR" -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 sha256sum > "$RESULT_DIR/SHA256SUMS.txt"
