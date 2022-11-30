set +x
# Wait for all ClusterOperators to be ready
timeout_min=40

echo -n "Waiting up to $timeout_min minutes for all cluster operators to start..."
is_ready=0
start_time=$(date +%s)
end_time=$(($start_time + 60 * $timeout_min))

while [ $(date +%s) -lt $end_time ]
do
  operators=$(oc get ClusterOperator -o go-template --template '{{range .items}}{{print .metadata.name " "}}{{end}}' || echo "cluster_unreachable")
  is_ready=0
  for i in $operators ;
  do
    if [ -z "$i" ];
    then
      continue
    fi
    if oc wait ClusterOperator $i --for condition=available --timeout=10s &> /dev/null;
    then
      if oc wait ClusterOperator $i --for condition=degraded --timeout=1s &> /dev/null;
      then
        is_ready=0
        echo -n "$i is Degraded"
        break
      else
        is_ready=1
      fi
      if oc wait ClusterOperator $i --for condition=progressing --timeout=1s &> /dev/null;
      then
        is_ready=0
        echo -n "$i still progressing"
        break
      else
        is_ready=1
      fi
    else
      is_ready=0
      break
    fi
  done
  if [ $is_ready -eq 1 ]
  then
    printf "\nAll cluster operators started.\n"
    break
  fi
  sleep 10
  echo -n "."
done

if [ $is_ready -eq 0 ]
then
  printf "\nERROR: Cluster is not reachable or some cluster operators are still progressing, check status of cluster operators.\n"
  exit 1
fi
