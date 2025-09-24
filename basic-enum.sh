#!/bin/bash

#for ((i=0; i<=100; i++)); do echo -e "${i} - \e[${i}mTexto para testes\e[0m"; done

[[ ${#} != 1 ]] && echo "Usage: ${0} hostfile" && exit 0

Off="\e[0m"
FRed="\e[31m"
FGreen="\e[32m"
BRed="\e[41m"
BWhite="\e[7m"
Besp="\e[100m"
Itali="\e[3m"
Subli="\e[4m"
Inter="\e[5m"
FYellow="\e[33m"
FCyan="\e[36m"


ppids=()
clear_on_exit(){
	for PID in "${ppids[@]}"; do 
		[[ "$(ps --pid "${PID}" -o pid=)" ]] && kill -15 "${PID}" 
	done
	wait
	exit 0
}
trap clear_on_exit SIGINT

tools=("wc" "wafw00f" "naabu" "nuclei" "httpx" "theHarvester" "amass" "nikto" "whatweb" "feroxbuster") 
for i in "${tools[@]}"; do
        [[ $(command -v ${i}) ]] || { echo -e "${Subli}Ferramenta não encontrada no sistema${Off} --> ${BRed}${i}${Off}"; exit 1; }
done

file=${1}
[[ ! -f ${file} ]] && { echo -e "${Subli}Entrada deve ser um arquivo.${Off}"; exit 1; }

while IFS= read -r domain; do 
	[[ "${domain}" =~ ( |$'\t') ]] && { echo -e "${BWhite}${domain}${Off} *contém tabulações ou espaço em branco"; exit 1; }
done < ${file}

for i in 5 4 3 2 1; do
	echo -ne "\r[!] Iniciando em ${FRed}${BWhite}${i}${Off}"
	sleep 1
done
echo

while read -r dir; do
        /usr/bin/mkdir -p "${PWD}/Scans/${dir}" 2>/dev/null && echo -e "Diretório ${Besp}${PWD}/Scans/${dir}${Off} criado"
done < ${file}

cmds=(
	"/usr/bin/wafw00f __DOMAIN__ --findall --output=${PWD}/Scans/__DOMAIN__/wafw00f.json --format=json --no-colors"
	"/usr/bin/naabu -host __DOMAIN__ -cdn -output ${PWD}/Scans/__DOMAIN__/naabu.json -json -verify -silent"
	"/usr/bin/theHarvester -d __DOMAIN__ -b baidu,bevigil,bing,bingapi,brave,bufferoverun,censys,certspotter,criminalip,crtsh,dehashed,dnsdumpster,duckduckgo,fullhunt,github-code,hackertarget,hunter,hunterhow,intelx,netlas,onyphe,otx,pentesttools,projectdiscovery,rapiddns,rocketreach,securityTrails,sitedossier,subdomaincenter,subdomainfinderc99,threatminer,tomba,urlscan,virustotal,yahoo,whoisxml,zoomeye,venacus -q -f ${PWD}/Scans/__DOMAIN__/theHarvester.out"
	"/usr/bin/amass enum -active -d __DOMAIN__ -silent -norecursive -nocolor -log ${PWD}/Scans/__DOMAIN__/amass.log -o ${PWD}/Scans/__DOMAIN__/amass.txt"
	"/usr/bin/nikto -h __DOMAIN__ -maxtime 1h -Format json -output ${PWD}/Scans/__DOMAIN__/nikto.json"
	"/usr/bin/whatweb --plugins=Apache,Nginx,Cloudflare,F5-BIGIP,Title,X-Powered-By,PHP,Python,Perl,Ruby,WordPress,Joomla,Drupal,Magento,Shopify,Laravel,Symfony,Django,Jetty,OpenResty,Google-Analytics,jQuery,Bootstrap,Modernizr,HTML5,HTTPServer,Meta-Author __DOMAIN__ --log-verbose=${PWD}/Scans/__DOMAIN__/WhatWeb.txt"
	"/usr/bin/nuclei -target __DOMAIN__ -json-export ${PWD}/Scans/__DOMAIN__/nuclei.json -no-color -silent"
	"/usr/bin/feroxbuster -u __DOMAIN__ --user-agent 'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0' -H 'Accept: */*' -o ${PWD}/Scans/__DOMAIN__/ferox.txt --filter-status 404 --time-limit 90m --redirects --no-recursion --dont-extract-links --quiet"
)

mapfile -t domains < "${file}"
MAX_JOBS=4

for c in "${cmds[@]}"; do
	for domain in "${domains[@]}"; do
		cmd="${c//__DOMAIN__/${domain}}"
		eval "${cmd} &>/dev/null" &
		P_PID=$(ps --ppid ${!} -o pid=)
		PID=${P_PID// /}
		ppids+=("${PID}")
		echo -e "[+] ${Besp}$(date +'%H:%M:%S')${Off} - Iniciado ${Itali}${FGreen}${c%% *}${Off} em ${FYellow}${domain}${Off} --> PID: ${FCyan}${!}${Off} --> PPID: ${FCyan}${PID// /}${Off}"
		while (( $(jobs -r | /usr/bin/wc -l) >= MAX_JOBS )); do
			sleep 30
		done
	done
done
wait
clear_on_exit
