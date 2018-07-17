#!/bin/bash

hash curl jq 2>/dev/null || { echo "Requires curl and jq for running"; exit 1; }

AMOUNT=""
REGISTRY="mfdev-docker0107:5000"
STACK="hadoop"
IMAGE_MANAGER="manager:8.4"
IMAGE_NODE="node:8.4"
FORCE_UPDATE_OF_STACK=false
MANAGER_PORT="80"
DEPLOY_VISUALIZER=false
PROXY_PORT="" #Random Port assigned
DEPLOYMENT=true
OUTPUT_LOGO=true

# ----------------------------------------------

printUsage() {
	echo $'Starts blank nodes via swarm to install software on them\n'
	output=$'OPTION#DESCRIPTION#DEFAULT\n'
	output+="--help#Prints the help"$'\n'
	output+="-a#Specify the amount of node containers to start#-Option is required-"$'\n'
	output+="-f#Force the updating of the stack if it already exists"$'\n'
	output+="-r#Specify the registry where the images should be pulled from#$REGISTRY"$'\n'
	output+="-s#Specify the name of the stack beeing deployed#$STACK"$'\n'
	output+="-m#Specify the image for the manager#$IMAGE_MANAGER"$'\n'
	output+="-n#Specify the image for the node#$IMAGE_NODE"$'\n'
	output+="-p#Specify the port of the webinterface of the manager container#$MANAGER_PORT"$'\n'
	output+="-v#Enable the deployment of the visualizer-container"$'\n'
	output+="-w#Specify the port for the proxy. If value is empty a random, free port is choosen. If value is 0, no proxy will be started#\"$PROXY_PORT\""$'\n'
	output+="-d#Disable deployment - This is usefull to just get the docker-compose.yml"$'\n'
	output+="-l#Disable the output of the logo"$'\n'
	column -t -s '#' <<< "$output"
}

# ----------------------------------------------

while getopts fa:r:s:m:n:p:vw:dl opt; do
   case $opt in
		a) AMOUNT="$OPTARG";;
		f) FORCE_UPDATE_OF_STACK=true;;
		r) REGISTRY="$OPTARG";;
		s) STACK="$OPTARG";;
		m) IMAGE_MANAGER="$OPTARG";;
		n) IMAGE_NODE="$OPTARG";;
		p) MANAGER_PORT="$OPTARG";;
		v) DEPLOY_VISUALIZER=true;;
		w) PROXY_PORT="$OPTARG";;
		d) DEPLOYMENT=false;;
		l) OUTPUT_LOGO=false;;
		*) printUsage; exit 1;;
	esac
done

# ----------------------------------------------

if [[ -n "$(docker stack ls | grep -o $STACK)" ]]; then
	echo "The stack $STACK is already running. To force the updating of it use the option -f (see --help)"
	if [ "$FORCE_UPDATE_OF_STACK" = false ]; then
		exit 1
	fi
fi

# ----------------------------------------------

if [ -z "$AMOUNT" ]; then
	echo "No amount of node containers to start was given, specify it with the option -a (see --help)"
	exit 1
fi

regexNumber='^[0-9]+$'
if ! [[ $AMOUNT =~ $regexNumber ]]; then
  echo "The amount of node containers to start is not a number (is $AMOUNT)"
  exit 1
fi

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

echo $'\n'"generating docker-compose.yml with amount: $AMOUNT, registry: $REGISTRY, stack: $STACK, manager image: $IMAGE_MANAGER, node image: $IMAGE_NODE"

cat <<EOF > docker-compose.yml
version: "3.3"
services:

  manager:
    image: $REGISTRY/$IMAGE_MANAGER
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
      - AMOUNT_NODES=$AMOUNT
      - PROXY_URL=itproxy-dev.1and1.org
      - PROXY_PORT=3128
    networks:
      - network
EOF

for i in $(seq 1 $AMOUNT); do
cat <<EOF >> docker-compose.yml

  node$i:
    image: $REGISTRY/$IMAGE_NODE
    hostname: node$i
    deploy:
      endpoint_mode: dnsrr
    environment:
      - AMOUNT_NODES=$AMOUNT
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
      - AMOUNT_NODES=$AMOUNT
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
  docker stack deploy -c docker-compose.yml $STACK

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
    exposedProxyPort=$(docker service inspect --format "{{range .Endpoint.Ports}}{{.PublishedPort}}{{end}}" "${STACK}_proxy")
    echo "Proxy-URL:  http://$ip:$exposedProxyPort"
  fi
fi
