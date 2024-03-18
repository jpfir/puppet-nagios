#!/bin/bash

# Default values
HOST="localhost"
PORT="9200"
USER=""
PASSWORD=""
SSL_VERIFY=true
WARN_THRESHOLD=""
CRIT_THRESHOLD=""
CURRENT_NODE=$(hostname | sed 's/\.net$/.lan/')

# Function to print usage
print_usage() {
  echo "Usage: $0 -H <host> -P <port> -u <user> -p <password> -t {cluster_status|nodes|unassigned_shards|jvm_usage|split_brain|disk_usage|thread_pool_queues|no_replica_indices} [-k] [-w warning_threshold] [-c critical_threshold]"
}

# Parse command-line options
while getopts ":H:P:u:p:N:t:w:c:k" opt; do
  case ${opt} in
    H )
      HOST=$OPTARG
      ;;
    P )
      PORT=$OPTARG
      ;;
    u )
      USER=$OPTARG
      ;;
    p )
      PASSWORD=$OPTARG
      ;;
    N )
      CURRENT_NODE=$OPTARG
      ;;
    t )
      TYPE=$OPTARG
      ;;
    k )
      SSL_VERIFY=false
      ;;
    w )
      WARN_THRESHOLD=$OPTARG
      ;;
    c )
      CRIT_THRESHOLD=$OPTARG
      ;;
    \? )
      print_usage
      exit 3 # Unknown
      ;;
  esac
done

# Verify if type is set
if [[ -z "$TYPE" ]]; then
  echo "Error: -t option is required."
  print_usage
  exit 3 # Unknown
fi

# Construct URL and CURL options
OPENSEARCH_URL="https://${HOST}:${PORT}"
CREDENTIALS="$USER:$PASSWORD"
CURL_OPTS="-s"
if [[ $SSL_VERIFY == false ]]; then
  CURL_OPTS="$CURL_OPTS -k"
fi

# Enhanced CURL execution with error handling
execute_curl() {
  local url=$1
  response=$(curl $CURL_OPTS -u $CREDENTIALS "$url" 2>&1)
  curl_status=$?
  
  if [[ $curl_status -ne 0 ]]; then
    echo "CURL error: $response"
    exit 2 # CRITICAL
  else
    echo "$response" | jq . > /dev/null 2>&1
    jq_status=$?
    if [[ $jq_status -ne 0 ]]; then
      echo "Failed to parse JSON response: $response"
      exit 2 # CRITICAL
    fi
  fi
  
  echo "$response"
}

# Function to get cluster health
get_cluster_health() {
  echo $(execute_curl "$OPENSEARCH_URL/_cluster/health")
}

# Adjusted function to get nodes stats optionally for a specific node
get_nodes_stats() {
  local node_name=$1
  local url="$OPENSEARCH_URL/_nodes/stats"
  if [[ -n "$node_name" ]]; then
    # If a node name is provided, adjust the URL or filter logic accordingly
    url="$OPENSEARCH_URL/_nodes/$node_name/stats"
  fi
  echo $(execute_curl "$url")
}

# Function to get disk space usage
check_disk_usage() {
  # Set default warning and critical thresholds if not provided
  if [[ -z "$WARN_THRESHOLD" ]]; then
    WARN_THRESHOLD=70 # Default warning threshold at 70%
  fi

  if [[ -z "$CRIT_THRESHOLD" ]]; then
    CRIT_THRESHOLD=90 # Default critical threshold at 90%
  fi

  local response=$(execute_curl "$OPENSEARCH_URL/_cat/allocation?format=json")
  local node_info=$(echo "$response" | jq -r --arg node "$CURRENT_NODE" '.[] | select(.node == $node)')
  local percent=$(echo "$node_info" | jq -r '.["disk.percent"] // "n/a"')

  if [[ "$node_info" == "" ]]; then
    echo "UNKNOWN: Node $CURRENT_NODE not found in the cluster."
    exit 3 # UNKNOWN
  elif [[ "$percent" == "n/a" ]]; then
    echo "UNKNOWN: Disk information for node $CURRENT_NODE is unavailable."
    exit 3 # UNKNOWN
  else
    local used=$(echo "$node_info" | jq -r '.["disk.used"]')
    local total=$(echo "$node_info" | jq -r '.["disk.total"]')
    local avail=$(echo "$node_info" | jq -r '.["disk.avail"]')
    local perf_data="'$CURRENT_NODE'_used=${used}; '$CURRENT_NODE'_total=${total}; '$CURRENT_NODE'_avail=${avail};"

    if [[ "$percent" -ge "$CRIT_THRESHOLD" ]]; then
      echo "CRITICAL: Disk usage on $CURRENT_NODE is critical: ${percent}% used | $perf_data"
      exit 2 # CRITICAL
    elif [[ "$percent" -ge "$WARN_THRESHOLD" ]]; then
      echo "WARNING: Disk usage on $CURRENT_NODE is high: ${percent}% used | $perf_data"
      exit 1 # WARNING
    else
      echo "OK: Disk usage on $CURRENT_NODE is within thresholds: ${percent}% used | $perf_data"
      exit 0 # OK
    fi
  fi
}

# Function to get thread pool queue size
check_thread_pool_queues() {
  # Adjust to filter by the current node's hostname
  local response=$(execute_curl "$OPENSEARCH_URL/_cat/thread_pool/search?h=node_name,queue&v")

  if [[ -z "$response" ]]; then
    echo "UNKNOWN: Unable to retrieve thread pool queue information."
    exit 3 # UNKNOWN
  fi

  local queue_size=$(echo "$response" | awk -v node="$CURRENT_NODE" '$1 == node {print $2}')

  if [[ -z "$queue_size" ]]; then
    echo "UNKNOWN: No data for node $CURRENT_NODE."
    exit 3 # UNKNOWN
  fi

  # Compare the queue size to the warning threshold
  if [[ "$queue_size" -gt "$WARN_THRESHOLD" ]]; then
    echo "WARNING: High search thread pool queue on $CURRENT_NODE: $queue_size"
    exit 1 # WARNING
  else
    echo "Thread pool queue OK on $CURRENT_NODE | '$CURRENT_NODE'_queue=$queue_size;"
    exit 0 # OK
  fi
}


# Function to check for indices with no replicas
check_no_replica_indices() {
    local response=$(execute_curl "$OPENSEARCH_URL/_cat/indices?h=index,rep&s=index")
    local indices_with_no_replicas=$(echo "$response" | awk '$1 !~ /^\./ && $2 == "0" {print $1}')

    if [[ -n "$indices_with_no_replicas" ]]; then
        echo "CRITICAL: The following user indices have no replicas: $indices_with_no_replicas"
        exit 2 # CRITICAL
    else
        echo "All user indices have replicas."
        exit 0 # OK
    fi
}

# Perform checks based on type
case "$TYPE" in
  cluster_status)
    cluster_health=$(get_cluster_health)
    cluster_status=$(echo "$cluster_health" | jq -r '.status')
    echo "Cluster Status: $cluster_status"
    [[ "$cluster_status" == "green" ]] && exit 0 || { [[ "$cluster_status" == "yellow" ]] && exit 1 || exit 2; }
    ;;
  nodes)
    cluster_health=$(get_cluster_health)
    nodes=$(echo "$cluster_health" | jq -r '.number_of_nodes')
    echo "Nodes: $nodes"
    exit 0 # OK
    ;;
  unassigned_shards)
    cluster_health=$(get_cluster_health)
    unassigned_shards=$(echo "$cluster_health" | jq -r '.unassigned_shards')
    echo "Unassigned Shards: $unassigned_shards"
    [[ "$unassigned_shards" -eq 0 ]] && exit 0 || exit 2
    ;;
  jvm_usage)
    # Ensure that WARN_THRESHOLD and CRIT_THRESHOLD have default values if not set
    if [[ -z "$WARN_THRESHOLD" ]]; then
      WARN_THRESHOLD=70 # Default warning threshold
    fi

    if [[ -z "$CRIT_THRESHOLD" ]]; then
      CRIT_THRESHOLD=90 # Default critical threshold
    fi

    # Get JVM stats for the current node only
    nodes_stats=$(get_nodes_stats $CURRENT_NODE)
    jvm_heap_used_percent=$(echo "$nodes_stats" | jq -r ".nodes[] | select(.name == \"$CURRENT_NODE\") | .jvm.mem.heap_used_percent")

    if [[ -z "$jvm_heap_used_percent" || "$jvm_heap_used_percent" == "null" ]]; then
      echo "UNKNOWN: No JVM stats available for node $CURRENT_NODE."
      exit 3 # UNKNOWN
    fi

    # Perf data string for graphing
    perf_data="'jvm_heap_used_percent'=$jvm_heap_used_percent%;$WARN_THRESHOLD;$CRIT_THRESHOLD;0;100"

    # Compare the JVM heap usage against the thresholds and include perf data in the output
    if (( $(echo "$jvm_heap_used_percent < $WARN_THRESHOLD" | bc -l) )); then
      echo "OK: JVM Heap Used on $CURRENT_NODE is within threshold: ${jvm_heap_used_percent}% | $perf_data"
      exit 0 # OK
    elif (( $(echo "$jvm_heap_used_percent >= $WARN_THRESHOLD && $jvm_heap_used_percent < $CRIT_THRESHOLD" | bc -l) )); then
      echo "WARNING: JVM Heap Used on $CURRENT_NODE is high: ${jvm_heap_used_percent}% | $perf_data"
      exit 1 # WARNING
    else
      echo "CRITICAL: JVM Heap Used on $CURRENT_NODE is very high: ${jvm_heap_used_percent}% | $perf_data"
      exit 2 # CRITICAL
    fi
    ;;
  split_brain)
    cluster_health=$(get_cluster_health)
    master_nodes=$(echo "$cluster_health" | jq -r '.number_of_master_nodes')
    echo "Split Brain: $([[ "$master_nodes" -gt 1 ]] && echo "POSSIBLE" || echo "NO")"
    [[ "$master_nodes" -gt 1 ]] && exit 2 || exit 0
    ;;
  disk_usage)
    check_disk_usage
    ;;
  thread_pool_queues)
    check_thread_pool_queues
    ;;
  no_replica_indices)
    check_no_replica_indices
    ;;
  *)
    echo "Invalid type specified. Valid types are: cluster_status, nodes, unassigned_shards, jvm_usage, split_brain, no_replica_indices. (Not tested: disk_usage, thread_pool_queues)"
    exit 3 # Unknown
    ;;
esac

