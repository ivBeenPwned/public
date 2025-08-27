#!/bin/bash

clear_on_exit(){
    wait
    [[ -n "${temp_dir}" && -d "${temp_dir}" ]] && rm -rf "${temp_dir}" 1>/dev/null 2>&1
    exit 1
}
trap clear_on_exit SIGINT

script_id=$$
wordlist=${1}

check_wordlist(){
    ! [[ -e "${wordlist}" ]] && echo "Especificar o arquivo de palavras. Exemplo: ${0} wordlist.txt" && exit 1 
    ! [[ -s "${wordlist}" ]] && echo "O arquivo ${wordlist} está vazio." && exit 1
    [[ $(< "${wordlist}") =~ [^a-z$'\n'] ]] && echo "Somente letra e/ou palavra em minúsculo" && exit 1
    while read -r length; do 
        (( ${#length} >= 30 )) && echo "A palavra ${length} ultrapassa o limite de caracteres."
    done < "${wordlist}" && exit 1
}
check_wordlist

words=()
while read -r word; do
    words+=("${word}")
    words+=("${word^}")
    words+=("${word^^}")
done < "${wordlist}"

symbols=("!" "@" "#" "$" "%" "&" "*" "_" "-" "." "?")
datas_dias=( $(for m in {1..12}; do for d in {1..31}; do printf "%02d%02d\n" "${d}" "${m}"; done; done) )
datas_anos=( {1980..2025} )
numeros_padroes=( 0 00 000 123 1234 12345 123456 123456789 1234567890 )
numbers=( "${datas_dias[@]}" "${datas_anos[@]}" "${numeros_padroes[@]}" )

evaluate_permutations(){
    first=$(( ${#words[@]} ))
    second=$(( ${#words[@]} * ${#numbers[@]} * 2 ))
    third=$(( ${#words[@]} * ${#symbols[@]} * 2 ))
    fourth=$(( ${#words[@]} * ${#numbers[@]} * ${#symbols[@]} * 6 ))
    fifth=$(( ${#words[@]} * ${#words[@]} - ${#words[@]} ))
    sixth=$(( ( ${#words[@]} * ${#words[@]} - ${#words[@]} ) * ${#numbers[@]} * 3 ))
    seventh=$(( ( ${#words[@]} * ${#words[@]} - ${#words[@]} ) * ${#symbols[@]} * 3 ))
    eight=$(( ( ${#words[@]} * ${#words[@]} - ${#words[@]} ) * ${#numbers[@]} * ${#symbols[@]} * 12 ))
    total=$(( first + second + third + fourth + fifth + sixth + seventh + eight ))
}
evaluate_permutations


#Checa se o stdout é para um pipeline, se não for, a saída será um arquivo.
if [ -t 1 ]; then
	output_file="${PWD}/wordlist.lst"
	echo "Arquivo de saída: ${output_file}"
	use_pipe=0
	LC_NUMERIC=en_US.utf8 printf "Total de permutações e combinações: "%\'d\\n"" ${total}
	max_procs=$(nproc)
	printf "Quantos núcleos para a tarefa [1-${max_procs}]? "
	read CPU
	if (( CPU <= max_procs )) && (( CPU >= 1 )); then
    		max_procs=${CPU}
	else
    		echo "Número mínimo ou máximo de CPU excedido"
    		exit 1
	fi
else
	output_file="/dev/stdout"
	(( max_procs = $(nproc) / 2 ))
	use_pipe=1
fi

count=4
update_progress(){
    count=$((count + 12 ))
    echo -ne "\rProgresso: [${count}%]" >&2
}

{
###########################
for word in "${words[@]}"; do
    echo "${word}"
done
(( use_pipe == 0 )) && update_progress
#######################################
for word in "${words[@]}"; do
    for number in "${numbers[@]}"; do
        echo "${word}${number}"
        echo "${number}${word}"
    done
done
(( use_pipe == 0 )) && update_progress
#########################################
for word in "${words[@]}"; do
    for symbol in "${symbols[@]}"; do
        echo "${word}${symbol}"
        echo "${symbol}${word}"
    done
done
(( use_pipe == 0 )) && update_progress
########################################################
for word in "${words[@]}"; do
    for number in "${numbers[@]}"; do
        for symbol in "${symbols[@]}"; do
            echo "${word}${number}${symbol}"
            echo "${word}${symbol}${number}"
            echo "${number}${word}${symbol}"
            echo "${number}${symbol}${word}"
            echo "${symbol}${word}${number}"
            echo "${symbol}${number}${word}"
        done
    done
done
(( use_pipe == 0 )) && update_progress
########################################################

######################################################
for word1 in "${words[@]}"; do
    for word2 in "${words[@]}"; do
        [[ ${word1} == ${word2} ]] && continue
        echo "${word1}${word2}"
    done
done
(( use_pipe == 0 )) && update_progress
##############################################################
for word1 in "${words[@]}"; do
    for word2 in "${words[@]}"; do
        for number in "${numbers[@]}"; do
            [[ ${word1} == ${word2} ]] && continue
            echo "${word1}${word2}${number}"
            echo "${number}${word1}${word2}"
            echo "${word1}${number}${word2}"
        done
    done
done
(( use_pipe == 0 )) && update_progress
##############################################################
for word1 in "${words[@]}"; do
    for word2 in "${words[@]}"; do
        for symbol in "${symbols[@]}"; do
            [[ ${word1} == ${word2} ]] && continue
            echo "${word1}${word2}${symbol}"
            echo "${symbol}${word1}${word2}"
            echo "${word1}${symbol}${word2}"
        done
    done
done
(( use_pipe == 0 )) && update_progress
#########################################################################

if (( use_pipe )); then
    # Modo pipeline → direto pro stdout
    for word1 in "${words[@]}"; do
        for word2 in "${words[@]}"; do
            for number in "${numbers[@]}"; do
                for symbol in "${symbols[@]}"; do
                    [[ ${word1} == ${word2} ]] && continue
                    echo "${word1}${word2}${number}${symbol}"
                    echo "${word1}${word2}${symbol}${number}"
                    echo "${word1}${symbol}${word2}${number}"
                    echo "${word1}${number}${word2}${symbol}"
                    echo "${word1}${symbol}${number}${word2}"
                    echo "${word1}${number}${symbol}${word2}"
                    echo "${symbol}${word1}${word2}${number}"
                    echo "${symbol}${word1}${number}${word2}"
                    echo "${symbol}${number}${word1}${word2}"
                    echo "${number}${word1}${word2}${symbol}"
                    echo "${number}${word1}${symbol}${word2}"
                    echo "${number}${symbol}${word1}${word2}"
                done
            done
        done
    done
else
    # Modo arquivo → com temp_dir + paralelismo
    temp_dir="${PWD}/wl_temp_${script_id}"
    mkdir -p "${temp_dir}"
    i=0
    for word1 in "${words[@]}"; do
        (temp_out="${temp_dir}/part_${i}.tmp"
        for word2 in "${words[@]}"; do
            for number in "${numbers[@]}"; do
                for symbol in "${symbols[@]}"; do
                    [[ ${word1} == ${word2} ]] && continue
                    echo "${word1}${word2}${number}${symbol}"
                    echo "${word1}${word2}${symbol}${number}"
                    echo "${word1}${symbol}${word2}${number}"
                    echo "${word1}${number}${word2}${symbol}"
                    echo "${word1}${symbol}${number}${word2}"
                    echo "${word1}${number}${symbol}${word2}"
                    echo "${symbol}${word1}${word2}${number}"
                    echo "${symbol}${word1}${number}${word2}"
                    echo "${symbol}${number}${word1}${word2}"
                    echo "${number}${word1}${word2}${symbol}"
                    echo "${number}${word1}${symbol}${word2}"
                    echo "${number}${symbol}${word1}${word2}"
                done
            done
        done > "${temp_out}") &
        (( i++ ))
        (( i % max_procs == 0 )) && wait
    done
    wait
    [[ "${temp_dir}" ]] && /usr/bin/cat ${temp_dir}/part_*.tmp
fi
(( use_pipe == 0 )) && update_progress
} > "${output_file}"
#########################################################################
clear_on_exit
