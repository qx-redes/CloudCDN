sudo route add -net 200.129.39.108 netmask 255.255.255.255 gw 200.129.39.97
sudo route add default gw 200.129.39.110
sudo route del -net 200.129.39.96 netmask 255.255.255.224 gw 0.0.0.0
