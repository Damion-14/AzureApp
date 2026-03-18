#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:7071}"
API_KEY="${API_KEY:-}"
ITEM_ID="${ITEM_ID:-item-1001}"
IDEMPOTENCY_KEY="${IDEMPOTENCY_KEY:-idem-1001}"

if [[ -z "${API_KEY}" ]]; then
  echo "Set API_KEY before running this script." >&2
  exit 1
fi

PAYLOAD="$(cat <<JSON
{
  "itemId": "${ITEM_ID}",
  "name": "PoC Item",
  "quantity": 4,
  "uom": "EA",
  "lastUpdatedBy": "manual-test"
}
JSON
)"

echo "PUT first request..."
FIRST_RESPONSE="$(curl -sS -X PUT "${BASE_URL}/v1/items/${ITEM_ID}" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: ${API_KEY}" \
  -H "Idempotency-Key: ${IDEMPOTENCY_KEY}" \
  -d "${PAYLOAD}")"
OPERATION_ID="$(echo "${FIRST_RESPONSE}" | jq -r '.operationId')"
echo "OperationId=${OPERATION_ID}"

echo "PUT replay request..."
SECOND_RESPONSE="$(curl -sS -X PUT "${BASE_URL}/v1/items/${ITEM_ID}" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: ${API_KEY}" \
  -H "Idempotency-Key: ${IDEMPOTENCY_KEY}" \
  -d "${PAYLOAD}")"
SECOND_OPERATION_ID="$(echo "${SECOND_RESPONSE}" | jq -r '.operationId')"

if [[ "${SECOND_OPERATION_ID}" != "${OPERATION_ID}" ]]; then
  echo "Expected same operationId on replay. got=${SECOND_OPERATION_ID} expected=${OPERATION_ID}" >&2
  exit 1
fi

echo "Polling operation status..."
for _ in {1..30}; do
  STATUS="$(curl -sS "${BASE_URL}/v1/operations/${OPERATION_ID}" -H "X-Api-Key: ${API_KEY}" | jq -r '.status')"
  echo "Status=${STATUS}"
  if [[ "${STATUS}" == "succeeded" ]]; then
    break
  fi
  if [[ "${STATUS}" == "failed" ]]; then
    curl -sS "${BASE_URL}/v1/operations/${OPERATION_ID}" -H "X-Api-Key: ${API_KEY}" | jq .
    exit 1
  fi
  sleep 1
done

echo "GET item snapshot..."
curl -sS "${BASE_URL}/v1/items/${ITEM_ID}" -H "X-Api-Key: ${API_KEY}" | jq .
