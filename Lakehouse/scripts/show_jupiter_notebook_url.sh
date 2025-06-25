cd /root/lakehouse/
podman compose logs --tail 20 jupyter 2> /tmp/logs
  TOKEN=$(grep -Eo 'token=[0-9a-f]+' /tmp/logs | head -1 | cut -d= -f2)
  HOST_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1)

  echo -e "\n📓 Jupyter Lab is up!"
  echo -e "   http:///${HOST_IP}:8888/lab?token=${TOKEN}\n"
