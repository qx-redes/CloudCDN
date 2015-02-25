#!/bin/bash

#Apaga os logs de execuções anterior
echo "" > log.txt

while :
do
	#Captura a carga da CPU
	cpu_idle=`snmpget -v 2c -c manager localhost .1.3.6.1.4.1.2021.11.11.0 -Ov | cut -d " " -f 2`
	cpu_load=$(( 100 - cpu_idle ))
	
	#Captura uso da memória
	mem_total=`snmpget -v 2c -c manager localhost .1.3.6.1.4.1.2021.4.5.0 -Ov | cut -d " " -f 2`
	mem_in_use=`snmpget -v 2c -c manager localhost .1.3.6.1.4.1.2021.4.11.0 -Ov | cut -d " " -f 2`
	perc_mem_in_use=$(((mem_in_use * 100) / mem_total))

	echo `date +%T` $cpu_load" "$perc_mem_in_use >> log.txt
	
	sleep 1
done
