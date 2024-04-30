#!/usr/bin/env bash

RESET=$(tput sgr0)
RED=$(tput setaf 1)
L_BLUE=$(tput setaf 159)
LL_BLUE=$(tput setaf 219)
L_PURPLE=$(tput setaf 200)
BOLD=$(tput bold)

ctrl_c(){
	echo -e "${RED}[!] SIGINT sent to ${0} Process.\nExiting...${NC}"; exit 0
}

removeTMPFiles(){
	rm -rf "${mktempNot12021}" "${mktemp12021}"; exit 0
}

banner(){

	echo -e "${RED}

	██████╗ ███████╗███╗   ██╗███████╗██╗    ██╗███████╗██████╗ 
	██╔══██╗██╔════╝████╗  ██║██╔════╝██║    ██║██╔════╝██╔══██╗
	██████╔╝█████╗  ██╔██╗ ██║█████╗  ██║ █╗ ██║█████╗  ██████╔╝
	██╔══██╗██╔══╝  ██║╚██╗██║██╔══╝  ██║███╗██║██╔══╝  ██╔══██╗
	██║  ██║███████╗██║ ╚████║███████╗╚███╔███╔╝███████╗██║  ██║
	╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚══════╝ ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝ ${RESET}"
}

help(){
	banner

cat << HELP

	${L_BLUE}${BOLD}Description: This bash script extracts information about dD VPSs 
		     and automatically renews plesk licenses.

	Syntax: ${0}  [-f|-l|-c|-r|-h]

	Usage:  ${0} -f file {-l}{-c}{-r}{-h} ${RESET}

	${L_PURPLE}Options:

		-f -> Specifies Servers' Input Text

		-l -> Extracts IP:Hostname List

		-c -> Check 12021 Port Connections on Servers

		-r -> Update Plesk's Licenses on Servers

		-h -> Displays this Help and Exit ${RESET}

HELP

}

trap ctrl_c INT
trap removeTMPFiles EXIT

checkFileType(){
	local vps_regex="^\[VPS\]$"	
	local dedicated_regex="^\[DEDICATED\]$" 

	grep -qiPa "${vps_regex}" ${1} && echo "VPS" || { grep -qiPa "${dedicated_regex}" ${1} && echo "Dedicated" ; } || return 1
}

getIPs(){
	local ip
	local -a ips

	mapfile -t ips < <(grep  -iPo "\d{1,3}(\.\d{1,3}){3}" "${mainfile}") 

	for ip in "${ips[@]}"; do
		printf "%s\n" "${ip}"
	done
}

checkAliveHost(){
	local ip
	local aliveServer
	local -a hosts=($(getIPs)) # or mapfile -t hosts < <(getIPs)
	local -a aliveHosts

	if [[ "${c_flag}" == true ]] && [[ "${r_flag}" == false ]]; then

		for ip in "${hosts[@]}"; do
			local status=1

			timeout 1 bash -c "ping -c1 ${ip}" &>/dev/null && \
			{ status=0 && echo -e "${L_BLUE}[*] $(dig -x ${ip} +short) Alive${RESET}" && aliveHosts+=(${ip}) ; }

			[[ "${status}" -eq 1 ]] && { \
				for port in $(seq 1 100); do
					timeout 1 bash -c "echo '' > /dev/tcp/${ip}/${port}" &>/dev/null && \
					{ status=0 && aliveHosts+=(${ip}) && break ; } &
				done; wait

				} || \
				
			[[ "${status}" -eq 1 ]] && echo -e "${RED}[!] ${ip} Seems Inactive or ICMP Packet Rejected :(${RESET}"
		done
	fi
}

checkSSHPort(){
	local server
	local ip
	local -a servers12021
	local -a not12021Servers
	declare mktemp12021=$(mktemp)
	declare mktempNot12021=$(mktemp)
	#[[ -n "${1}" ]] && declare mktemp12021=$(mktemp) && declare mktempNot12021=$(mktemp)

	while IFS= read -r server; do
		#timeout 1 bash -c "echo '' > /dev/tcp/${server}/12021" &>/dev/null && servers12021+=(${server}) || \
		#not12021Servers+=(${server})

		(
			timeout 1 bash -c "echo '' > /dev/tcp/${server}/12021" &>/dev/null

			[[ ${?} -eq 0 ]] && echo "${server}" >> "${mktemp12021}" || echo "${server}" >> "${mktempNot12021}" 
		) &

	done < <(getIPs); wait

	mapfile -t servers12021 < "${mktemp12021}"
	mapfile -t not12021Servers < "${mktempNot12021}"

	{ [[ "${r_flag}" == true && "${c_flag}" == false ]] || [[ "${1}" == "IPS" ]] ; } && { \

		for ip in "${servers12021[@]}"; do
			printf "%s\n" "${ip}"
		done

	}
	
	{ [[ "${r_flag}" == false ]] && [[ "${c_flag}" == true ]] && [[ -z "${1}" ]]; } && { \

		for ip in "${not12021Servers[@]}"; do
			hostname=$(dig -x ${ip} +short)
			[[ ! -z "${hostname}" ]] && echo -e "${RED}[!] 12021 Port closed on ${ip} -> $(dig -x ${ip} +short)${RESET}" || \
			echo -e "${RED}[!] 12021 Port closed on ${ip} -> No Hostname Obtained neither :(${RESET}"
		done

		[[ "${#not12021Servers[@]}" -eq 0 ]] && echo -e "${L_PURPLE}[+] 12021 Port Opened on all Hosts :)${RESET}\n"
	}

}

checkPleskLicense(){
	local ip keynameOS keynameDS
	local regex_ip='^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
	local keyPath="/etc/sw/keys/keys"
	local originServerIp=

	#[[ "${c_flag}" == true ]] && local -a servers=($(checkSSHPort "IPS"))

	{ [[ $(checkFileType "${mainfile}") == "VPS" ]] && originServerIP="151.80.59.30" ; } || \
	{ [[ $(checkFileType "${mainfile}") == "DEDICATED" ]] && originServerIP="57.128.96.133" ; }

	[[ -z "${1}" ]] && echo -e "${L_BLUE}[+] Extracting $(dig -x ${originServerIP} +short)'s MD5 Hash...${RESET}"
	keynameOS=$(ssh -p12021 root@${originServerIP} '[[ -n $(ls -A /etc/sw/keys/keys/* 2>/dev/null) ]] && realpath /etc/sw/keys/keys/key* > /tmp/md5hash && md5sum /tmp/md5hash && rm -rf /tmp/md5hash' | awk '{print $1}') && \
	[[ -z "${1}" ]] && echo -e "\n${L_BLUE}[+] MD5 Hash Obtained (${keynameOS})${RESET}\n"

	{ [[ "${r_flag}" == false ]] && [[ "${c_flag}" == true ]] ; } && { \

		local -a servers=($(checkSSHPort "IPS")) && [[ -n "${keynameOS}" ]] &&

			for ip in "${servers[@]}"; do
				(
				[[ ${ip} =~ $regex_ip ]] && keynameDS=$(ssh -p12021 root@${ip} '[[ -n $(ls -A /etc/sw/keys/keys/* 2>/dev/null) ]] && realpath /etc/sw/keys/keys/key* > /tmp/md5hash && md5sum /tmp/md5hash && rm -rf /tmp/md5hash' | awk '{print $1}')

				[[ "${keynameOS}" == "${keynameDS}" ]] && { \

					echo -e "${LL_BLUE}[*] Plesk key's MD5 Hash on $(dig -x ${ip} +short 2>/dev/null || ${ip}) ("${keynameDS}") matches :)${RESET}"
					
				} || echo -e "\n${RED}[!] Plesk Licenses' Hash on $(dig -x ${ip} +short) does not match :( (${keynameDS}"
				) &

			done; wait || { echo -e "\n${RED} [!] Plesk License Directory ~ "/etc/sw/keys/keys" on $(dig -x ${ip} +short) seems empty :(${RESET}" ; exit 1 ; }
	}

	{ [[ "${r_flag}" == true ]] && [[ "${c_flag}" == false ]] ; } && { \
	
		[[ -n "${keynameOS}" ]] && { \

			keynameDS=$(ssh -p12021 root@${1} '[[ -n $(ls -A /etc/sw/keys/keys/* 2>/dev/null) ]] && realpath /etc/sw/keys/keys/key* > /tmp/md5hash && md5sum /tmp/md5hash && rm -rf /tmp/md5hash' | awk '{print $1}')

			[[ "${keynameOS}" == "${keynameDS}" ]] && return 0 || return 1

		} || return 1
	}

}

updatePleskLicense(){
	local server
	local originServerIP=
	local -a servers=($(checkSSHPort)) # or mapfile -t servers < <(checkSSHPort)

	{ [[ $(checkFileType "${mainfile}") == "VPS" ]] && originServerIP="151.80.59.30" ;} || { \
	[[ $(checkFileType "${mainfile}") == "DEDICATED" ]] && originServerIP="57.128.96.133" ; }

	checkFileType "${mainfile}" &>/dev/null || { echo -e "${RED}[!] ${mainfile} File is not [VPS] or [DEDICATED] valid format${RESET}\n"; exit 1; } 

	for server in "${servers[@]}"; do

#		ssh -p 12021 root@${server} 'rm -rf /etc/sw/keys/keys/*' &>/dev/null && \
#		scp -3 scp://${originServerIP}:12021//etc/sw/keys/keys/* scp://${server}:12021//etc/sw/keys/keys &>/dev/null && \
#		ssh -p 12021 root@${server} 'service psa restart' &>/dev/null && { \
		#[[ "${?}" -eq 0 ]] && echo -e "${L_BLUE}[+] $(dig -x ${server} +short) Plesk's License Updated :) ${RESET}" || \
		#echo -e "${RED}[*] $(dig -x ${server} +short) Plesk's License Upgrade Failed :( ${RESET}" ; } &

		ssh -p 12021 root@${server} 'rm -rf /etc/sw/keys/keys/*' &>/dev/null && \
		scp -3 scp://${originServerIP}:12021//etc/sw/keys/keys/* scp://${server}:12021//etc/sw/keys/keys &>/dev/null && \
		ssh -p 12021 root@${server} 'service psa restart' &>/dev/null && { \
		[[ "${?}" -eq 0 ]] && echo -e "${L_BLUE}[+] $(dig -x ${server} +short) Plesk's License seems Updated :/${RESET}" || \
		echo -e "${RED}[*] $(dig -x ${server} +short) Plesk's License Upgrade Failed :( ${RESET}" ; } &

	done; wait

	echo -e "\n${L_BLUE}[+] Checking Plesk License after Update...${RESET}\n"

	for server in "${servers[@]}"; do
		checkPleskLicense "${server}" && echo -e "${L_BLUE}[*] $(dig -x ${server} +short) Plesk's License correctly Updated :)${RESET}" || { \

			ssh -p 12021 root@${server} 'rm -rf /etc/sw/keys/keys/*' &>/dev/null && \
			scp -3 scp://${originServerIP}:12021//etc/sw/keys/keys/* scp://${server}:12021//etc/sw/keys/keys &>/dev/null && \
			ssh -p 12021 root@${server} 'service psa restart' &>/dev/null && { \
			[[ "${?}" -eq 0 ]] && echo -e "${L_BLUE}[*] $(dig -x ${server} +short) Plesk's License correctly Update :)${RESET}" || \
			echo -e "${RED}[!] $(dig -x ${server} +short) Plesk's License Upgrade Failed :( ${RESET}" ; }
		}
	done
}

main(){

	local f_flag=false
	local l_flag=false
	local c_flag=false
	local r_flag=false

	local mainfile=
	local file_regex="^(\d{1,3}(\.\d{1,3}){3})\:.*(\..*){2}"

	while getopts ":f::clhr" opt; do
		case "${opt}" in

			f ) f_flag=true; mainfile=$(realpath "${OPTARG}") ;;

			l ) l_flag=true ;;

			c ) c_flag=true ;;

			r ) r_flag=true ;;

			h ) help; exit 0;;

			\? ) banner && echo -e "\n\t${RED}[!] Unknown Option: -${OPTARG}${RESET}\n"; exit 1 ;;

			* ) banner && echo -e "\n\t${RED}[!] Unimplemented Option: -${opt}${RESET}\n"; exit 1 ;;
		esac
	done

	[[ "${#}" -le 2 ]] && banner && \
	echo -e "\n\t${L_BLUE}[!] Not enough Parameters specified. Try ${0} -h to print Help${RESET}\n\n" && exit 0

	[[ -e "${mainfile}" ]] && { grep -qiPa "${file_regex}" "${mainfile}" || \
	{ banner; echo -e "\n${RED}[!] File Format not supported or allowed${RESET}\n"; exit 1; } ; } || \
	{ banner; echo -e "\n${RED}[!] ${mainfile} File not exists on system $(hostname --fqdn)${RESET}\n"; exit 1; }

	"${c_flag}" && echo -e "\n${L_BLUE}[+] Checking if Hosts are alive...${RESET}\n" && echo -e "${L_PURPLE}$(checkAliveHost)${RESET}" && \
	echo -e "\n${L_BLUE}[+] Checking 12021 Port Connection on Servers...${RESET}\n" && echo -e "${L_PURPLE}$(checkSSHPort)${RESET}" && \
	echo -e "\n${L_BLUE}[+] Checking Plesk License Status on Server...${RESET}\n" && echo -e "${L_PURPLE}$(checkPleskLicense)${RESET}\n"

	"${l_flag}" && echo -e "\n${L_BLUE}[+] Extracting IP:Hostname list...${RESET}" && echo -e "${L_PURPLE}$(grep -iPav '^\[.*\]$' ${mainfile})\n${RESET}"

	"${r_flag}" && echo -e "\n${L_BLUE}[+] Updating Plesk Licenses...${RESET}\n" && echo -e "\n${L_PURPLE}$(updatePleskLicense)${RESET}\n"
}

main "${@}"
