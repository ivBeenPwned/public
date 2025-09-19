#!/bin/bash

if [[ $(id -u) == 0 ]]; then
	echo -e "O script NÃO deve ser executado como root, pois:\n\n - Poderá ocorrer erros ao executar certos escaneamentos como AjaxSpider devido a limitação de uso com o Firefox para usuários que possuem permissiões Administrativas (root) no dispostivo"
	exit 1
fi

URL=()

if [[ -z "${1}" ]]; then
	echo -e "USAGE: ${0} [STRING OU ARQUIVO]"
	exit 1
elif [[ -f "${1}" ]]; then
	while IFS= read -r domain; do
		URL+=("${domain}")
	done < "${1}"

else
	URL=("${1}")
fi

for content in "${URL[@]}"; do
	if ! [[ "${content}" =~ ^https?:\/\/[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}(/.*)?$ ]]; then
		echo -e "O domínio ${content} passado é inválido. Esquema = http(s)://subdomain.domain.tld/directory"
		echo -e "Saindo..."
		exit 1
	fi
done

APIKEY=$(/usr/bin/tr -dc 'a-zA-Z0-9' < /dev/urandom | /usr/bin/fold -w 32 | /usr/bin/head -c 32)
HOST="http://localhost"
PORT="38080"

clear_on_exit(){
	PID=$(/usr/bin/pgrep -f "/usr/share/zaproxy/${VERSION}")
	if ! [[ -z ${PID} ]]; then
		/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/ascan/action/stopAllScans/?apikey=${APIKEY}"
		/usr/bin/sleep 1
		/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/core/action/shutdown/?apikey=${APIKEY}"
	fi
exit 0
}

interrupting(){
	if [[ ${exits} -eq 0 ]]; then
		/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/spider/action/pause/?apikey=${APIKEY}&scanId=${SPIDER_ID}"
		/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/ascan/action/pause/?apikey=${APIKEY}&scanId=${ACTIVE_SCAN_ID}"
		echo -e "\nPausando scaneamentos..."
		echo -e "\nAções> [S]air [P]róximo [C]ontinuar"
		exits=1
		while true; do
			read -t 30 -n1 action
			case "${action}" in
				s|S) echo -e "\nEncerrando o script..."; clear_on_exit; exit 0;;
				p|P) echo -e "\nSeguindo para o próximo scan"; 
					/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/spider/action/stopAllScans/?apikey=${APIKEY}"
					sleep 0.5
					/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/ajaxSpider/action/stop/?apikey=${APIKEY}"
					sleep 0.5
					/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/ascan/action/stopAllScans/?apikey=${APIKEY}"
					sleep 0.5
					exits=0; break;;
				c|C) echo -e "\nContinuando..."
					/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/spider/action/resume/?apikey=${APIKEY}&scanId=${SPIDER_ID}"
					sleep 1
					/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/ascan/action/resume/?apikey=${APIKEY}&scanId=${ACTIVE_SCAN_ID}"
					sleep 1
					exits=0; break;;
			esac
		done
	else
		echo -e "\nForçando finalização do script..."
		clear_on_exit
	fi
}
					
trap interrupting SIGINT

#Iniciando o ZAPROXY
PS_LIST="$(ps aux)"
PS_ZAP="${PS_LIST##*\/usr\/share\/zaproxy\/}"
VERSION="${PS_ZAP}:0:10}" #Fallback
PID=$(/usr/bin/pgrep -f "/usr/share/zaproxy/${VERSION}")
if [[ -z ${PID} ]]; then
	/usr/bin/zaproxy -daemon -port "${PORT}" -config "api.key=${APIKEY}" 1>${PWD}/zap.log 2>/dev/null &
	echo -e "Iniciando ZAPROXY"
	/usr/bin/sleep 5
	echo -e "Chave de API criada: ${APIKEY}"
	sleep 5
	ZAP_STATUS=""
	while ! [ -z "${ZAP_STATUS}" ]; do
		sleep 1
		/usr/bin/curl -X GET -s "${HOST}:${PORT}/JSON/stats/view/stats/?apikey=${APIKEY}"
		sleep 1
	done
else
	echo -e "ZAP já está rodando, finalize-o primeiro"
	exit 0
fi

for DOMAIN in "${URL[@]}"; do

	#Limpar sessão
        SESSION_CLEAR=$(/usr/bin/curl -sX GET "${HOST}:${PORT}/JSON/core/action/newSession/?apikey=${APIKEY}")
        if [[ "${SESSION_CLEAR}" =~ "OK" ]]; then
                echo -e "\nNova sessão criada para = ${DOMAIN}"
                /usr/bin/sleep 2;
        fi

	#Importar URL
	/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/core/action/accessUrl/?apikey=${APIKEY}&url=${DOMAIN}"

	#Spider Scan
	SPIDER_ID=$(/usr/bin/curl -sX GET "${HOST}:${PORT}/JSON/spider/action/scan/?apikey=${APIKEY}&url=${DOMAIN}&recurse=5" | /usr/bin/grep -oE "[0-9]+")
	echo -e "\nIniciando Spider Scan com ID: ${SPIDER_ID}..."
	SPIDER_PERCENTAGE=0
	while [ "${SPIDER_PERCENTAGE}" != "100" ]; do 
		SPIDER_PERCENTAGE=$(curl -sX GET "${HOST}:${PORT}/JSON/spider/view/status/?apikey=${APIKEY}&scanId=${SPIDER_ID}" | /usr/bin/grep -oE "[0-9]+")
		/usr/bin/sleep 2
		echo -ne "\r(${DOMAIN}) Spider Scan ${SPIDER_PERCENTAGE}%... "
	done || echo -e "\nOcorreu algum erro ao executar o Spider Scan"
	echo ""

	#Definir browser para AJAX
	/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/ajaxSpider/action/setOptionBrowserId/?apikey=${APIKEY}&String=firefox-headless"

	#Ajax Spider
	/usr/bin/curl -X GET -so /dev/null "${HOST}:${PORT}/JSON/ajaxSpider/action/scan/?apikey=${APIKEY}&url=${DOMAIN}"
	echo -e "\nIniciando o AjaxSpider"
	AJAX_STATUS=""
	AJAX_TIMER=0
	while [ "${AJAX_STATUS}" != "stopped" ]; do 
		AJAX_STATUS=$(curl -X GET -s "${HOST}:${PORT}/JSON/ajaxSpider/view/status/?apikey=${APIKEY}" | /usr/bin/grep -o "stopped")
		echo -ne "\rAjaxSpider em execução há $((AJAX_TIMER++)) segundos... (Tempo limite: 600 segundos)"
		/usr/bin/sleep 1
	done 

	#Active Scan
	ACTIVE_SCAN_ID=$(/usr/bin/curl -s -X GET "${HOST}:${PORT}/JSON/ascan/action/scan/?apikey=${APIKEY}&url=${DOMAIN}&scanPolicyName=Default%20Policy" | /usr/bin/grep -oE "[0-9]+")
	echo -e "\nIniciando Active Scan com ID: ${ACTIVE_SCAN_ID}..."
	ACTIVE_SCAN_PERCENTAGE=0
	while [ "${ACTIVE_SCAN_PERCENTAGE}" != "100" ]; do 
		ACTIVE_SCAN_PERCENTAGE=$(curl -sX GET "${HOST}:${PORT}/JSON/ascan/view/status/?apikey=${APIKEY}&scanId=${ACTIVE_SCAN_ID}" | /usr/bin/grep -oE "[0-9]+")
		/usr/bin/sleep 1
		echo -ne "\r(${DOMAIN}) Active Scan ${ACTIVE_SCAN_PERCENTAGE}%..."
	done 
	echo ""

	#Gerar relatório
	FILENAME=$(printf "${DOMAIN}" | /usr/bin/cut -d "/" -f3)
	curl -sX GET "${HOST}:${PORT}/JSON/reports/action/generate/?title=ZAP%20Scanning%20Report&template=risk-confidence-html&apikey=${APIKEY}&reportDir=${PWD}&sites=${DOMAIN}&reportFileName=${FILENAME}"

done

clear_on_exit
