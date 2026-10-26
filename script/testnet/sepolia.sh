#!/usr/bin/env bash
# Runs the Base Sepolia end-to-end deployment and live scenarios (web/scripts/testnet.mjs).
#
#   script/testnet/sepolia.sh                 # uses ~/.foundry/keystores/sepolia-deployer
#   KEYSTORE=path PASSWORD_FILE=path script/testnet/sepolia.sh
#   IMPORT_KEY=1 script/testnet/sepolia.sh    # prompts (hidden) for a testnet key and stores it encrypted
#   FORK=1 script/testnet/sepolia.sh          # rehearsal on a local anvil fork of Base Sepolia
#
# The key is decrypted into the environment of the node process only; it is never printed, written
# to the repository or passed on a command line (forge signs with the keystore).
set -euo pipefail
cd "$(dirname "$0")/../.."
FOUNDRY="${FOUNDRY_BIN:-$HOME/.foundry/bin}"
KEYSTORE="${KEYSTORE:-$HOME/.foundry/keystores/sepolia-deployer}"
PASSWORD_FILE="${PASSWORD_FILE:-$HOME/.foundry/keystores/.sepolia-pw}"
export RPC_URL="${RPC_URL:-https://sepolia.base.org}"

if [[ "${FORK:-0}" == "1" ]]; then
  # anvil's first default account: a public test key, valid only on the local fork
  export DEPLOYER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
  export RPC_URL=http://127.0.0.1:8547
  if ! "$FOUNDRY/cast" chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    "$FOUNDRY/anvil" --fork-url https://sepolia.base.org --port 8547 --silent &
    sleep 8
  fi
  exec node web/scripts/testnet.mjs
fi

if [[ "${IMPORT_KEY:-0}" == "1" ]]; then
  mkdir -p "$(dirname "$KEYSTORE")"
  [[ -f "$PASSWORD_FILE" ]] || (umask 077; head -c 32 /dev/urandom | base64 > "$PASSWORD_FILE")
  "$FOUNDRY/cast" wallet import "$(basename "$KEYSTORE")" --keystore-dir "$(dirname "$KEYSTORE")" \
    --interactive --unsafe-password "$(cat "$PASSWORD_FILE")"
fi
[[ -f "$KEYSTORE" ]] || { echo "no keystore at $KEYSTORE (run with IMPORT_KEY=1)"; exit 1; }
[[ "$("$FOUNDRY/cast" chain-id --rpc-url "$RPC_URL")" == "84532" ]] || { echo "RPC is not Base Sepolia"; exit 1; }
echo "deployer: $("$FOUNDRY/cast" wallet address --keystore "$KEYSTORE" --password-file "$PASSWORD_FILE")"
DEPLOYER_KEY="$("$FOUNDRY/cast" wallet decrypt-keystore --keystore-dir "$(dirname "$KEYSTORE")" "$(basename "$KEYSTORE")" \
  --unsafe-password "$(cat "$PASSWORD_FILE")" 2>/dev/null | sed -n 's/.*: \(0x[0-9a-fA-F]\{64\}\).*/\1/p')"
[[ -n "$DEPLOYER_KEY" ]] || { echo "could not decrypt keystore"; exit 1; }
export DEPLOYER_KEY KEYSTORE KEYSTORE_PASSWORD_FILE="$PASSWORD_FILE"
exec node web/scripts/testnet.mjs
