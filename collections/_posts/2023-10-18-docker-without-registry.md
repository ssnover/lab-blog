---
layout: post
title: "Deploying Docker Containers without a Registry"
date: 2023-10-18
projects: [homelab]
---

I've previously been pretty lazy in how I deploy applications to servers running on my homelab. The absolutely easiest way to get a program running on one of my servers was to push it to a GitHub repository, clone that repository on the host, compile it, open a Byobu terminal, and run it. The biggest pains there are that compiling leaves a lot of artifacts and that compiling on these devices takes quite a while since I generally use old laptops and smaller server devices. If I delete the artifacts to free up disk space, the compile time takes longer when I update the service.

This is an annoying pickle, and one that I knew I could solve with Docker containers. However, my experience with Docker containers previously was that I'd store them in a private cloud registry (or maybe a public one), then I could add keys to the remote host so that it could pull the container and run it. I didn't want to pay to put containers up, nor did I want them to be public and possibly leak API keys and the like. That seemed to imply I had to also self-host a Docker registry... Doable, but kind of just moving the problem.

However, a neat thing I found out while looking through the documentation for Docker is that Docker can actually save images to disk as a tarball and load them back from this format! This pretty easily solved the problem I was running into, and for the last service I developed I dropped the whole operation into a script:

```bash
#!/usr/bin/env bash
set -x
set -eo pipefail

SERVER_USER=${SERVER_USER:=shane}
SERVER_IP=${SERVER_IP:=192.168.5.102}

docker build --target runtime --tag homepage .
docker save homepage | gzip > /tmp/homepage_saved.tar.gz
scp /tmp/homepage_saved.tar.gz ${SERVER_USER}@${SERVER_IP}:/tmp
scp docker-compose.yml ${SERVER_USER}@${SERVER_IP}:/tmp
ssh ${SERVER_USER}@${SERVER_IP} 'docker load < /tmp/homepage_saved.tar.gz'
```

This is still a little manual, needing to run the to-host.sh script each time, but lightens the mental load completely. This has other advantages of my "run in Byobu" style like restarts being handled by Docker and getting access to all of the tooling around Docker.

Anyway, this is a short one, but I hope it helps ease someone's experiencing developing custom applications for their homelab!