#!/bin/bash

# Default Fluent Bit host and port
FLUENTBIT_HOST="localhost"
FLUENTBIT_PORT="2020"

# Check if custom host and port are provided as parameters
if [ ! -z "$1" ]; then
  FLUENTBIT_HOST=$1
fi

if [ ! -z "$2" ]; then
  FLUENTBIT_PORT=$2
fi

# Fluent Bit health check URL
FLUENTBIT_HEALTH_URL="http://${FLUENTBIT_HOST}:${FLUENTBIT_PORT}/api/v1/health"

# Use curl to get the HTTP status code
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $FLUENTBIT_HEALTH_URL)

# Check if the status code is 200
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "OK - Fluent Bit is healthy."
    exit 0
else
    echo "CRITICAL - Fluent Bit is not healthy. HTTP Status: $HTTP_STATUS"
    exit 2
fi
