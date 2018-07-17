# TODO Check if jq is installed (perhaps: otherwise using fallback with grep)
# TODO Check if server is running and reachable

hash curl jq 2>/dev/null || { echo "Requires curl and jq for running"; exit 1; }

yarn_nodemanager_log_dirs="/var/log/hadoop-yarn/container"

if [ "$#" -ne 3 ]; then
    echo "Must have 3 arguments: 1.) The ip/hostname of Cloudera-Manager 2.) The port of the Cloudera-Manager 3.) Use the proxy or not (true|false)"
    exit 1
fi

IP=$1
PORT=$2
if [ "$3" = false ]; then
  PROXY_INFORMATION="--noproxy $IP"
fi

yarnRoleNames=$(curl -4 $PROXY_INFORMATION -s -u admin:admin "http://$IP:$PORT/api/v10/clusters/Cluster%201/services/yarn/roles" \
| jq '.items[] | select(.type | contains("NODEMANAGER")).name' | grep -oP '^"\K.*(?=")')
echo "YARN-NodeManager-Rolenames:"
echo "$yarnRoleNames"
echo
echo "Updating configurations..."
while read i; do
  curl -4 $PROXY_INFORMATION -s -X PUT -u admin:admin -H "Content-Type: application/json" \
  -d '{"items": [{"name" : "yarn_nodemanager_log_dirs", "value":"'$yarn_nodemanager_log_dirs'"}]}' \
  "http://$IP:$PORT/api/v10/clusters/Cluster%201/services/yarn/roles/$i/config" > /dev/null
done <<< "$yarnRoleNames"

echo
echo "Set configuration of 'yarn_nodemanager_log_dirs' to: $yarn_nodemanager_log_dirs"
echo
curl -4 $PROXY_INFORMATION -s -X POST --user admin:admin -H "Content-Type: application/json" -d '{}' \
"http://$IP:$PORT/api/v10/clusters/Cluster%201/commands/restart" > /dev/null
echo "Restart of cluster triggered"
