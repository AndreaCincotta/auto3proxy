#!/bin/bash

ARG1=${1:-false}		# optional argument for debug echos

if [ "$ARG1" = true ]
then
    echo "Program start.."
    echo ""
fi


# support variables
i=1   				# interface cycle counter
j=0   				# XML parser cycle counter


# parse configuration XML
username=$(xmlstarlet select -t -v "/root/Proxy/username" -nl /usr/local/bin/auto3proxy/gateway_conf.xml)
base_port=$(xmlstarlet select -t -v "/root/Proxy/base_port" -nl /usr/local/bin/auto3proxy/gateway_conf.xml)
readarray -t mask_arr < <(xmlstarlet select -t -v "/root/Gateways/Gateway/@mask" -nl /usr/local/bin/auto3proxy/gateway_conf.xml)
readarray -t gateway_arr < <(xmlstarlet select -t -v "/root/Gateways/Gateway/@gateway_mapped" -nl /usr/local/bin/auto3proxy/gateway_conf.xml)
readarray -t name_arr < <(xmlstarlet select -t -v "/root/Gateways/Gateway/@name" -nl /usr/local/bin/auto3proxy/gateway_conf.xml)

# build associative arrays
declare -A gateway_map          # gateway map
declare -A name_map             # name map
for key in ${mask_arr[@]}
do
    gateway_map["$key"]=${gateway_arr[j]};
    name_map["$key"]=${name_arr[j]};
    j=$((j+1));
done


# call ender script silently
sudo /usr/local/bin/auto3proxy/end3proxy.sh >/dev/null 2>&1

# append gateways to rt_tables file
for value in "${gateway_map[@]}"
do
    value_index=${value#gateway*};
    echo "$value_index $value" >> /etc/iproute2/rt_tables;
done

# init the cfg file
cp /usr/local/bin/auto3proxy/base_cfg.cfg /usr/local/3proxy/conf/3proxy.cfg


# do while cycle on interfaces
flag=true
while $flag
do
    # get inet
    inet[$i]=$(ip -f inet addr show eth$i 2> /dev/null | sed -En -e 's/.*inet ([0-9.]+).*/\1/p');

    # if the network interface exists, proceed
    if [ "${inet[$i]}" ]
    then
        # network interface exists

        # get interface, default gateway and mask
        interface[$i]="eth$i";
        mask[$i]=${inet[$i]%.*}".0/24";
        default_gateway[$i]=${inet[$i]%.*}".1";

        # get the mapped gateway, if exists
        gateway[$i]=${gateway_map[${mask[$i]}]};

        # if the mapped gateway exists, proceed
        if [ "${gateway[$i]}" ]
        then
            # mapped gateway exists

            # get gateway index and relative port
            gateway_index[$i]=${gateway[$i]#gateway*};
            port[$i]=$(($base_port+${gateway_index[$i]}));
            # get the correct name mapped
            name[$i]=${name_map[${mask[$i]}]};

            # %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% DEBUG %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            if [ "$ARG1" = true ]
            then
                #
                if [ $i -gt 1 ]
                then
                    echo; # for blank line
                fi
                echo "cycle index: $i";
                echo "inet: ${inet[$i]}";
                echo "interface: ${interface[$i]}";
                echo "default gateway: ${default_gateway[$i]}";
                echo "mask: ${mask[$i]}";
                echo "GATEWAY MAPPED: ${gateway[$i]}";
                echo "PORT ASSIGNED: ${port[$i]}";
                echo "NAME MAPPED: ${name[$i]}";
                #
            fi
            # %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% DEBUG %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

            # set routing
            #
            sudo ip route replace ${mask[$i]} dev ${interface[$i]} src ${inet[$i]} table ${gateway[$i]};
            sudo ip route replace default via ${default_gateway[$i]} dev ${interface[$i]} table ${gateway[$i]};
            sudo ip rule add from ${inet[$i]}/32 table ${gateway[$i]};
            sudo ip rule add to ${inet[$i]}/32 table ${gateway[$i]};
            #

            # append to file
            #
            echo "" >> /usr/local/3proxy/conf/3proxy.cfg; 
            echo "# ${gateway_index[$i]} - ${name[$i]} - port ${port[$i]}" >> /usr/local/3proxy/conf/3proxy.cfg;
            echo "allow $username" >> /usr/local/3proxy/conf/3proxy.cfg;
            echo "parent 1000 extip ${inet[$i]} 0" >> /usr/local/3proxy/conf/3proxy.cfg;
            echo "proxy -p${port[$i]} -a" >> /usr/local/3proxy/conf/3proxy.cfg;
            echo "flush" >> /usr/local/3proxy/conf/3proxy.cfg;
            #
        fi

    else
        # network interface does not exist, cycle ends
        flag=false;
    fi

    # end of the cycle
    i=$((i+1));
done


# start 3proxy
sudo 3proxy /usr/local/3proxy/conf/3proxy.cfg


if [ "$ARG1" = true ]
then
echo ""
echo "Program end."
fi
