#!/bin/bash

hash curl 2>/dev/null || { echo "Requires curl for running"; exit 1; }

STACK="hadoop"
OVERRIDED_START_NAME=""
REGISTRY="mfdev-docker0107:5000"
FORCE_UPDATE_OF_STACK=false
MANAGER_PORT="80"
DEPLOY_VISUALIZER=false
PROXY_PORT="" #Random Port assigned
DEPLOYMENT=true
OUTPUT_LOGO=true

imageExistsInStackInRegistry () { # 1 Argument: Image-name
  [[ "$(curl -s $REGISTRY/v2/_catalog)" = *"${STACK}_${1}"* ]]
}

# ----------------------------------------------

printUsage() {
    echo $'Starts the saved images in the registry via swarm to test software on them\n'
    output=$'OPTION#DESCRIPTION#DEFAULT\n'
    output+="--help#Prints the help"$'\n'
    output+="-s#Specify the saved stack beeing deployed#$STACK"$'\n'
    output+="-n#Specify the name of the stack thats beeing started (only for experts suggested)#$STACK"$'\n'
    output+="-r#Specify the registry where the images should be pulled from#$REGISTRY"$'\n'
    output+="-f#Force the updating of the stack if it already exists"$'\n'
    output+="-p#Specify the port of the webinterface of the manager container#$MANAGER_PORT"$'\n'
    output+="-v#Enable the deployment of the visualizer-container"$'\n'
    output+="-w#Specify the port for the proxy. If value is empty a random, free port is choosen. If value is 0, no proxy will be started#\"$PROXY_PORT\""$'\n'
    output+="-d#Disable deployment - This is usefull to just get the docker-compose.yml"$'\n'
    output+="-l#Disable the output of the logo"$'\n'
    column -t -s '#' <<< "$output"
}

# ----------------------------------------------

while getopts s:n:r:fp:vwdl opt
do
   case $opt in
    s) STACK="$OPTARG";;
    n) OVERRIDED_START_NAME="$OPTARG";;
    r) REGISTRY="$OPTARG";;
    f) FORCE_UPDATE_OF_STACK=true;;
    p) MANAGER_PORT="$OPTARG";;
    v) DEPLOY_VISUALIZER=true;;
    w) PROXY_PORT="$OPTARG";;
    d) DEPLOYMENT=false;;
    l) OUTPUT_LOGO=false;;
    *) printUsage; exit 1;;
   esac
done

START_NAME=$([ -z "$OVERRIDED_START_NAME" ] && echo "$STACK" || echo "$OVERRIDED_START_NAME")

# ----------------------------------------------

if [[ -n "$(docker stack ls | grep -o $START_NAME)" ]]; then
	echo "The stack $START_NAME is already running. To force the updating of it use the option -f (see --help)"
	if [ "$FORCE_UPDATE_OF_STACK" = false ]; then
		exit 1
	fi
fi

# ----------------------------------------------

regexNumber='^[0-9]+$'
if ! [[ $MANAGER_PORT =~ $regexNumber ]]; then
  echo "The port of the manager-webinterface is not a number (is $MANAGER_PORT)"
  exit 1
fi

regexNumberOrEmpty='^([0-9]+|)$'
if ! [[ $PROXY_PORT =~ $regexNumberOrEmpty ]]; then
  echo "The port of the proxy is not a number (is $PROXY_PORT)"
  exit 1
fi

# ----------------------------------------------

if [ "$OUTPUT_LOGO" = true ]; then
  ./printLogo.sh
fi

# ----------------------------------------------

echo $'\n'"generating docker-compose.yml with registry: $REGISTRY, stack: $STACK, startName: $START_NAME"

if ! imageExistsInStackInRegistry manager; then
  echo "The manager image in the stack $STACK at the registry $REGISTRY was not found (Image: $REGISTRY/${STACK}_manager)"
  exit 1
fi

# ----------------------------------------------

NODE_COUNTER=1
while imageExistsInStackInRegistry node$NODE_COUNTER; do
  NODE_COUNTER=$((NODE_COUNTER + 1))
done
NODE_COUNTER=$((NODE_COUNTER - 1))

cat <<EOF > docker-compose.yml
version: "3.3"
services:

  manager:
    image: $REGISTRY/${STACK}_manager
    hostname: manager
    ports:
      - target: 7180
        published: $MANAGER_PORT
        protocol: tcp
        mode: host
    deploy:
      endpoint_mode: dnsrr
      placement:
        constraints: [node.role == manager]
    environment:
      - AMOUNT_NODES=$NODE_COUNTER
    networks:
      - network
EOF

for i in $(seq 1 $NODE_COUNTER); do
cat <<EOF >> docker-compose.yml

  node$i:
    image: $REGISTRY/${STACK}_node$i
    hostname: node$i
    deploy:
      endpoint_mode: dnsrr
    environment:
      - AMOUNT_NODES=$NODE_COUNTER
    networks:
      - network
EOF
done

if [ "$DEPLOY_VISUALIZER" = true ]; then
cat <<EOF >> docker-compose.yml

  visualizer:
    image: dockersamples/visualizer:stable
    ports:
      - "443:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
    deploy:
      placement:
        constraints: [node.role == manager]
    networks:
      - network
EOF
fi

if [ "$PROXY_PORT" != "0" ]; then
cat <<EOF >> docker-compose.yml

  proxy:
    image: $REGISTRY/proxy:latest
    ports:
      - "$PROXY_PORT:3128"
    deploy:
      placement:
        constraints: [node.role == manager]
    environment:
      - AMOUNT_NODES=$NODE_COUNTER
    networks:
      - network

EOF
fi

cat <<EOF >> docker-compose.yml

networks:
  network:
    driver: overlay
EOF

if [ "$DEPLOYMENT" = true ]; then
  echo $'\n'"starting docker-compose.yml"$'\n'
  docker stack deploy -c docker-compose.yml $START_NAME

  echo
  echo -e "\e[32m-------------------------------------\e[39m"
  echo -e "\e[32mStartup complete\e[39m"
  echo -e "\e[32m-------------------------------------\e[39m"

  ip="$(docker node inspect self --format '{{ .Status.Addr  }}')"
  echo $'\nURLs:'
  echo "webinterface manager:     http://$ip:$MANAGER_PORT"
  if [ "$DEPLOY_VISUALIZER" = true ]; then
    echo "webinterface visualizer:  http://$ip:443"
  fi
  if [ "PROXY_PORT" != "0" ]; then
    exposedProxyPort=$(docker service inspect --format "{{range .Endpoint.Ports}}{{.PublishedPort}}{{end}}" "${START_NAME}_proxy")
    echo "Proxy-URL:  http://$ip:$exposedProxyPort"
  fi
fi
