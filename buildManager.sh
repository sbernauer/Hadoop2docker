export GIT_SSL_NO_VERIFY=1
docker build -t mfdev-docker0107.server.lan:5000/manager:8.4 https://git.mamdev.server.lan/sbernauer/Hadoop2docker_Image_Manager.git
docker push mfdev-docker0107.server.lan:5000/manager:8.4
