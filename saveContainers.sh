#!/bin/bash

hash curl 2>/dev/null || { echo "Requires curl for running"; exit 1; }

STACK="hadoop"
OVERRIDED_EXPORT_NAME=""
REGISTRY="mfdev-docker0107:5000"
OUTPUT_CURL=true
OUTPUT_LOGO=true

# ----------------------------------------------

if [ $# -eq 1 ] && [ "$1" == "--help" ]; then
	echo $'Commits and pushes all containers running in Hadoop-cluster to registry\n'
	output=$'Option#Description#Default\n'
	output+="--help#Prints the help"$'\n'
	output+="-s#Specify the stack to export#$STACK"$'\n'
	output+="-n#Specify the export-name for the registry (only for experts suggested)#$STACK"$'\n'
	output+="-r#Specify the registry to push to#$REGISTRY"$'\n'
	output+="-q#Disable the output of curl (progress info)"$'\n'
	output+="-l#Disable the output of the logo"$'\n'
	column -t -s '#' <<< "$output"
	exit 0
fi

# ----------------------------------------------

while getopts s:n:r:ql opt
do
	case $opt in
		s) STACK="$OPTARG";;
		n) OVERRIDED_EXPORT_NAME="$OPTARG";;
		r) REGISTRY="$OPTARG";;
		q) OUTPUT_CURL=false;;
		l) OUTPUT_LOGO=false;;
	esac
done

# Check if specified stack is running
[[ -n "$(docker stack ls | grep -o "$STACK")" ]] || { echo "The specified stack '$STACK' doesn't exist"; exit 1 ; }

EXPORT_NAME=$([ -z "$OVERRIDED_EXPORT_NAME" ] && echo "$STACK" || echo "$OVERRIDED_EXPORT_NAME")

# ----------------------------------------------

if [ "$OUTPUT_LOGO" = true ]; then
	./printLogo.sh
fi

# ----------------------------------------------

echo -e "\e[31mTODO Information about opening socket on docker dameons TODO\e[39m"
echo
docker stack ps -f "desired-state=running" $STACK
echo

# Gathering information about container and nodes

tasks=$(docker stack ps -f "desired-state=running" $STACK)
if [[ -n "$(grep -o "Nothing found in stack" <<< "$tasks")" ]]; then
	exit 1
fi

# TODO Change all the below commands to something like this (At this moment not possible because my current API doesn't support this):
# taskIds=($(docker stack ps -f "desired-state=running" --format="{{ .Id }}" $STACK))

taskIds=($(grep -oP '^[0-9a-z]{12,12}' <<< "$tasks"))
exportNames=($(grep -oP '^[0-9a-z]{12,12}[ ]+\K[a-zA-Z0-9_-]+(?=\.[0-9]+)' <<< "$tasks" | sed "s/^$STACK/$EXPORT_NAME/" ))
nodes=($(grep -oP ' \K[^ ]+(?=[ ]+Running[ ]+Running)' <<< "$tasks"))

containerIds=()
for i in "${taskIds[@]}"; do
	containerIds+=($(docker inspect --format="{{ .Status.ContainerStatus.ContainerID }}" $i))
done

output="TASK-ID NODE CONTAINER-ID EXPORT-NAME"
for i in "${!taskIds[@]}"; do 
	output+=$'\n'"${taskIds[$i]} ${nodes[$i]} ${containerIds[$i]} ${exportNames[$i]}"
done
column -t -s ' ' <<< "$output"

# Build Authentification-Header for Registry
# HEADER=$(echo '{"username":"foo", "password":"bar", "email":"foo@bar.de", "serveraddress":"foo.de"}' | base64)
authentificationHeader=$(echo '{}' | base64)

# When the user presses STRG + C, all the running (curl)-processes are killed
trap SIGINT

# Commit an push containers on each node to registry
for i in "${!taskIds[@]}"; do

	regexNotCommiting='^.+_(visualizer|proxy)$'
	if [[ $"${exportNames[$i]}" =~ $regexNotCommiting ]]; then # Is visualizer-container, not neccesary to commit and push
		echo $'\n'"Skipped commiting and pushing of ${exportNames[$i]}"
		continue
	fi

	## Updating the hostname from IP to "manager" in the Cloudera-Agent-Configuration
	EXEC_COMMAND=`curl -s "http://${nodes[$i]}:2375/containers/${containerIds[$i]}/exec" -XPOST \
	  -H "Content-Type: application/json" \
	  -d "{
	    \"AttachStdout\": true,
	    \"Tty\": true,
	    \"Cmd\": [ \"/bin/sh\", \"-c\", \"./writeServerHostnameInAgentConfig.sh manager\" ]
	}"
	`
	echo "EXEC_COMMAND: $EXEC_COMMAND"
	EXEC_ID=$(echo $EXEC_COMMAND | grep -oP '{"Id":[ ]?"\K[0-9a-f]+')
	echo "EXEC_ID: $EXEC_ID"
	curl -s "http://${nodes[$i]}:2375/exec/${EXEC_ID}/start" -XPOST \
	  -H "Content-Type: application/json" \
	  -d '{
	    "Detach": false,
	    "Tty": true
	}'

	repo="$REGISTRY/${exportNames[$i]}"

	echo -e "\n\n\e[32mcurl -X POST 'http://${nodes[$i]}:2375/commit?container=${containerIds[$i]}&repo=$repo&tag=latest'\e[39m"
	if [ "$OUTPUT_CURL" = true ]; then
		curl -X POST "http://${nodes[$i]}:2375/commit?container=${containerIds[$i]}&repo=$repo&tag=latest" \
		&& echo -e "\n\e[32mcurl -X POST -H 'X-Registry-Auth: $authentificationHeader' 'http://${nodes[$i]}:2375/images/$repo:latest/push'\e[39m" \
		&& curl -X POST -H "X-Registry-Auth: $authentificationHeader" "http://${nodes[$i]}:2375/images/$repo:latest/push" &
	else
		curl -s -X POST "http://${nodes[$i]}:2375/commit?container=${containerIds[$i]}&repo=$repo&tag=latest" > /dev/null \
		&& echo -e "\n\e[32mcurl -X POST -H 'X-Registry-Auth: $authentificationHeader' 'http://${nodes[$i]}:2375/images/$repo:latest/push'\e[39m" \
		&& curl -s -X POST -H "X-Registry-Auth: $authentificationHeader" "http://${nodes[$i]}:2375/images/$repo:latest/push" > /dev/null &
	fi
done

# Wait until completion of all (curl)-processes
echo "Waiting for containers to commit..." & wait
echo
echo "-------------------------------------------------------"
#TODO Check if successfull
echo -e "\e[32m All containers commited and pushed to registry\e[39m"
echo "-------------------------------------------------------"
echo
