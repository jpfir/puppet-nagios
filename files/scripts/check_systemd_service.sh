#!/bin/bash

# Initialize default thresholds (optional, can be set to sensible defaults or left unset)
WARNING_THRESHOLD=""
CRITICAL_THRESHOLD=""

# Initialize service and mode variables
SERVICE=""
MODE=""

# Parse command-line arguments
while getopts ":w:W:c:C:s:m:" opt; do
  case ${opt} in
    w | W)
      WARNING_THRESHOLD=$OPTARG
      ;;
    c | C)
      CRITICAL_THRESHOLD=$OPTARG
      ;;
    s )
      SERVICE=$OPTARG
      ;;
    m )
      MODE=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      ;;
  esac
done
shift $((OPTIND -1))

# Ensure service and mode are provided
if [ -z "$SERVICE" ] || [ -z "$MODE" ]; then
  echo "Usage: $0 -s <service_name> -m <mode> [-w <warning_threshold>] [-c <critical_threshold>]"
  echo "Modes:"
  echo "  status        - Check if the service is active/running."
  echo "  memory_usage  - Monitor the memory usage of the service."
  echo "  uptime        - Check how long the service has been running since its last start."
  exit 3
fi

# Define the function for memory usage check
check_memory_usage() {
  MEMORY_USED=$(systemctl show $SERVICE -p MemoryCurrent --value | tr -d '[:alpha:]')
  if [ "$MEMORY_USED" != "undefined" ] && [ "$MEMORY_USED" != "" ]; then
    MEMORY_USED_MB=$((MEMORY_USED/1024/1024))
    
    # Build the performance data string
    perf_data="'${SERVICE}_memory_usage_MB'=${MEMORY_USED_MB};${WARNING_THRESHOLD};${CRITICAL_THRESHOLD}"
    
    if [ -n "$CRITICAL_THRESHOLD" ] && [ "$MEMORY_USED_MB" -ge "$CRITICAL_THRESHOLD" ]; then
      echo "CRITICAL: Memory used by $SERVICE: ${MEMORY_USED_MB} MB | $perf_data (Critical threshold: ${CRITICAL_THRESHOLD} MB)"
      exit 2
    elif [ -n "$WARNING_THRESHOLD" ] && [ "$MEMORY_USED_MB" -ge "$WARNING_THRESHOLD" ]; then
      echo "WARNING: Memory used by $SERVICE: ${MEMORY_USED_MB} MB | $perf_data (Warning threshold: ${WARNING_THRESHOLD} MB)"
      exit 1
    else
      # If no thresholds are specified or the usage is below the specified thresholds, report as OK.
      echo "OK: Memory used by $SERVICE: ${MEMORY_USED_MB} MB | $perf_data"
      exit 0
    fi
  else
    echo "UNKNOWN: Could not determine memory usage for $SERVICE | $perf_data"
    exit 3
  fi
}


# Function to check uptime and warn if less than 10 minutes
check_uptime() {
  UPTIME_TIMESTAMP=$(systemctl show $SERVICE -p ActiveEnterTimestamp --value)
  
  if [ "$UPTIME_TIMESTAMP" != "undefined" ] && [ -n "$UPTIME_TIMESTAMP" ]; then
    # Convert the timestamp to seconds since epoch
    UPTIME_SECONDS=$(date -d "$UPTIME_TIMESTAMP" +%s)
    # Get the current time in seconds since epoch
    CURRENT_TIME=$(date +%s)
    # Calculate the difference in minutes
    UPTIME_MINUTES=$(( ($CURRENT_TIME - $UPTIME_SECONDS) / 60 ))

    # Calculate days, hours, and minutes for human readability
    DAYS=$((UPTIME_MINUTES / 1440))
    HOURS=$(( (UPTIME_MINUTES % 1440) / 60))
    MINUTES=$((UPTIME_MINUTES % 60))

    # Format the uptime message
    UPTIME_MSG="${DAYS} days ${HOURS} hours ${MINUTES} minutes"
    
    # Check if uptime is less than 10 minutes for warning
    if [ "$UPTIME_MINUTES" -lt 10 ]; then
      echo "WARNING: ${SERVICE} uptime is less than 10 minutes (${UPTIME_MSG}) | 'uptime_minutes'=${UPTIME_MINUTES}"
      exit 1
    else
      echo "OK: ${SERVICE} uptime is ${UPTIME_MSG} | 'uptime_minutes'=${UPTIME_MINUTES}"
      exit 0
    fi
  else
    echo "UNKNOWN - Could not determine uptime for ${SERVICE}"
    exit 3
  fi
}

# Function to check service status
check_status() {
  systemctl is-active --quiet $SERVICE
  if [ $? -eq 0 ]; then
    echo "OK: $SERVICE is running | 'service_status'=1"
    exit 0
  else
    echo "CRITICAL: $SERVICE is not running | 'service_status'=0"
    exit 2
  fi
}

# Call the appropriate function based on the mode
case "$MODE" in
  status)
    check_status
    ;;
  memory_usage)
    check_memory_usage
    ;;
  uptime)
    check_uptime
    ;;
  *)
    echo "Invalid mode specified"
    exit 3
    ;;
esac
