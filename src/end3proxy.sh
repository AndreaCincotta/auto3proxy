#!/bin/bash

# terminate running 3proxy process
sudo kill -9 `pidof 3proxy`

# get all gateways
gateway_list=$(ip route show table all | grep "table" | sed 's/.*\(table.*\)/\1/g' | awk '{print $2}' | sort | uniq | grep -e "[0-9]")

# flush ip rules and routes
for gateway in ${gateway_list[@]}
do
    # flush tables
    echo "FLUSHING $gateway..";
    sudo ip rule flush table $gateway;
    sudo ip route flush table $gateway;
done

# clean rt_tables file
sed -i_bak -e "/gateway/d" /etc/iproute2/rt_tables
