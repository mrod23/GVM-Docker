#!/usr/bin/env bash
set -Eeuo pipefail

if [ ! -d "/run/redis" ]; then
	mkdir /run/redis
fi
if  [ -S /run/redis/redis.sock ]; then
        rm /run/redis/redis.sock
fi
redis-server --unixsocket /run/redis/redis.sock --unixsocketperm 700 --timeout 0 --databases 128 --maxclients 4096 --daemonize yes --port 6379 --bind 0.0.0.0

echo "Wait for redis socket to be created..."
while  [ ! -S /run/redis/redis.sock ]; do
        sleep 1
done

echo "Testing redis status..."
X="$(redis-cli -s /run/redis/redis.sock ping)"
while  [ "${X}" != "PONG" ]; do
        echo "Redis not yet ready..."
        sleep 1
        X="$(redis-cli -s /run/redis/redis.sock ping)"
done
echo "Redis ready."


if  [ ! -d /data ]; then
	echo "Creating Data folder..."
        mkdir /data
fi

if [ ! -f "/firstrun" ]; then
	echo "Running first start configuration..."

	echo "Creating Openvas NVT sync user..."
	useradd --home-dir /usr/local/share/openvas openvas-sync
	chown openvas-sync:openvas-sync -R /usr/local/share/openvas
	chown openvas-sync:openvas-sync -R /usr/local/var/lib/openvas

	touch /firstrun
fi

if  [ ! -d /data/plugins ]; then
	echo "Creating NVT Plugins folder..."
	mkdir /data/plugins
fi

if [ ! -h /usr/local/var/lib/openvas/plugins ]; then
	echo "Fixing NVT Plugins folder..."
	rm -rf /usr/local/var/lib/openvas/plugins
	ln -s /data/plugins /usr/local/var/lib/openvas/plugins
	chown openvas-sync:openvas-sync -R /data/plugins
	chown openvas-sync:openvas-sync -R /usr/local/var/lib/openvas/plugins
fi

echo "Updating NVTs..."
su -c "rsync --compress-level=9 --links --times --omit-dir-times --recursive --partial --quiet rsync://feed.community.greenbone.net:/nvt-feed /usr/local/var/lib/openvas/plugins" openvas-sync
sleep 5

if [ -f /var/run/ospd.pid ]; then
  rm /var/run/ospd.pid
fi

if [ -S /data/ospd.sock ]; then
  rm /data/ospd.sock
fi

if [ ! -d /var/run/ospd ]; then
  mkdir /var/run/ospd
fi

echo "Starting Open Scanner Protocol daemon for OpenVAS..."
ospd-openvas --log-file /usr/local/var/log/gvm/ospd-openvas.log --unix-socket /data/ospd.sock --log-level INFO

while  [ ! -S /data/ospd.sock ]; do
	sleep 1
done

chmod 666 /data/ospd.sock

echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "+ Your OpenVAS Scanner container is now ready to use! +"
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo ""
echo "++++++++++++++++"
echo "+ Tailing logs +"
echo "++++++++++++++++"
tail -F /usr/local/var/log/gvm/*
