#!/bin/bash

# *** !!! This Script Can't Called By Other Process !!! *** #
# ***    Because it must be called by system cron       *** #
# *** !!! This Script Can't Called By Other Process !!! *** #

#===================================================================================#
#                                                                                   #
#    Author:                                                                        #
#        |_ libin wx382598                                                          #
#                                                                                   #
#    Name:                                                                          #
#        |_ crontab_scheduler.sh                                                    #
#                                                                                   #
#    Explain:                                                                       #
#        |_ Some simple or similar task scripts into this script to schedule.       #
#        |_ In order to save system overhead and Convenient management              #
#        |_ Clock start from 1970-01-01 0:00:00                                     #
#        |_ Please try to set the cycle as an easy to understand value              #
#                                                                                   #
#    Extend Method:                                                                 #
#        |_ Add correspoding tasks rule to the crontab_common_task.ini              #
#                                                                                   #
#    About err_coode:                                                               #
#        |_ 1000:                                                                   #
#        |    |_ Inner error,please check crontab_common_task.ini.                  #
#        |                                                                          #
#        |_ 2000:                                                                   #
#        |    |_ Bad format;                                                        #
#        |    |_ Task cycle is not contain 'H' or 'M'.                              #
#        |                                                                          #
#        |_ 2001:                                                                   #
#        |    |_ Task is not daily task.                                            #
#        |    |_ but cycle od minute is NULL or not contain '/'.                    #
#        |                                                                          #
#        |_ 2002:                                                                   #
#        |    |_ Task is X_MIN_TASK;                                                #
#        |    |_ but cycle of hour or minute is bad format.                         #
#        |                                                                          #
#        |_ 2003:                                                                   #
#        |    |_ Task is DAILY_TASK;                                                #
#        |    |_ but cycle of minute is contain '/'.                                #
#        |                                                                          #
#        |_ 2004:                                                                   #
#        |    |_ Task is DAILY_TASK;                                                #
#        |    |_ but cycle of hour or minute is NULL or not integer.                #
#        |                                                                          #
#        |_ 2005:                                                                   #
#        |    |_ cycle of hour or minute is not integer                             #
#        |    |_ Or Incorrect range of integer values.                              #
#        |                                                                          #
#        |_ 2006:                                                                   #
#            |_ Inner error, unsupport task type.                                   #
#                                                                                   #
#                                                                                   #
#===================================================================================#

g_bin_path=$(dirname $0)
g_shell_name=$(basename $0)
g_base_path="${g_bin_path}/log"
g_log_file="${g_base_path}/crontab_scheduler.log"
g_cache_list="${g_base_path}/cache_crontab_list.ini"
g_common_list="${g_base_path}/crontab_common_task.ini"
g_prev_common_list="${g_base_path}/prev_cron_common_task.ini"
g_svn_common_list="${g_base_path}/.svn_cron_common_task.ini"
g_bad_process_cnf="${g_base_path}/.crontab_bad_caller.cnf"

g_HHMM=$(date +'%H%M')
g_now_long_min=$((`date +%s`/60))
g_1_min_task[1]=''
g_x_min_task[1]=''
g_daily_task[1]=''

# load controller
if [ -f "${g_base_path}/crontab_controller" ]
then
	. ${g_base_path}/crontab_controller
else
	g_debug_switch='OFF'
	g_user='root'
	g_group='root'
	g_cancel_all_1_min_task='OFF'
	g_cancel_daily_task=''
	g_cancel_all_daily_task='OFF'
	g_cancel_all_task='OFF'
	g_kill_bad_process='OFF'
fi

function logger()
{
	[ "$1" = "DEBUG" ] && [ "${g_debug_switch}" != "ON" ] && return 0;
	echo "`date +'%Y-%m-%d %H:%M:%S'`.`printf "%03d\n" $((10#$(date +'%N')/1000000))` [$1] (line:$3): $2" >>$g_log_file
	return 0
}

function init_env()
{
	if [ ! -d "$g_base_path" ]
	then
		mkdir -p $g_base_path
	fi
	# first run this script,cp common ini to svn common ini
	# for self-healing and robustness
	if [ ! -f "$g_svn_common_list" ]
	then
		cp -p $g_common_list $g_svn_common_list
		chown root:root $g_svn_common_list
	fi

	if [ ! -f "$g_common_list" ] || [ ! -s "$g_common_list" ]
	then
		recover_common_list_ini
	fi

	if [ ! -f "$g_cache_list" ] || [ ! -s "$g_cache_list" ]
	then
		logger "ERROR" "cache file:${g_cache_list} is not exist; refresh it now." $LINENO
		refresh_task_list 'NO_WAIT'
	fi
}

# if common file is invalid, use prev file to recover
# for self-healing and robustness
function recover_common_list_ini()
{
	logger "WARN " "extern ERR,cp prev common ini to recover common ini" $LINENO
	if [ -f "$g_prev_common_list" ] 
	then
		cp -p $g_prev_common_list $g_common_list
	else
		cp -p $g_svn_common_list $g_common_list
	fi

	chmod 750 $g_common_list
	chown ${g_user}:${g_group} $g_common_list 
}

# must called by root of system cron
function check_caller()
{
	logger "DEBUG" "<<check_caller>>____start" $LINENO	
	if [ "`whoami`" != "root" ]
	then
		logger "ERROR" "!!! sorry `whoami`, you can't call it !!!" $LINENO
		return 1
	fi
	# must called by crontab, sh call this
	local tmp_file="${g_base_path}/tmp_$$_check.txt"
	local call_infos=`ps -ef|grep -v 'grep'|grep "${g_shell_name}"`
	local called_num=`echo "${call_infos}"|wc -l`
	if [ ${called_num} -eq 2 ]
	then
		logger "DEBUG" "all caller is normal" $LINENO
	elif [ ${called_num} -gt 2 ]
	then
		echo "${call_infos}">$tmp_file
		# not call by 'sh xxxx'
		grep -vw "sh ${g_bin_path}/${g_shell_name}" ${tmp_file} >${g_bad_process_cnf}	
		# not called by this time
		grep -vw "$$" ${tmp_file} >>${g_bad_process_cnf}	
		logger "WARN " "!!! exist bad caller !!!" $LINENO
		logger "INFO " "$(cat ${g_bad_process_cnf})" $LINENO
	else
		logger "ERROR" "(err_code:1000) should not step here..." $LINENO
	fi
	# kill -9
	if [ "${g_kill_bad_process}" = "YES" ]
	then
		logger "DEBUG" "kill -9 ..." $LINENO
		awk '{print $2}' ${g_bad_process_cnf} |xargs kill -9 
	fi
	rm -rf ${tmp_file} ${g_bad_process_cnf} &>/dev/null
	logger "DEBUG" "<<check_caller>>____end" $LINENO	
	return 0
}

# read cache task file
# cache file must exist here
function init_task_list()
{
	if [ "${g_cancel_all_task}" = "ON" ]
	then
		logger "INFO " "[controller] cancel all tasks ON" $LINENO
		return 0
	fi
	logger "DEBUG" "<<init_task_list>>____start" $LINENO	
	local lab_flag=''

	while read line || [[ -n $line ]]
	do
		[ -z "$line" ] && continue
		if [ "$line" = "@1_MIN_TASK@" -o "$line" = "@X_MIN_TASK@" -o "$line" = "@DAILY_TASK@" ]
		then
			local lab_flag=${line}
			continue
		fi

		if [ "${lab_flag}" = "@1_MIN_TASK@" ]
		then
			if [ -z "${g_1_min_task[1]}" ]
			then
				g_1_min_task[1]="${line}"
				logger "DEBUG" "<<init_task_list>> g_1_min_task[1]=$line" $LINENO	
			else
				local len=${#g_1_min_task[@]}
				local next=`expr ${len} + 1`
				g_1_min_task[${next}]="${line}"
				logger "DEBUG" "<<init_task_list>> g_1_min_task[$next]=$line" $LINENO	
			fi
		elif [ "${lab_flag}" = "@X_MIN_TASK@" ]
		then
			local cyc_time=`echo "$line" |cut -d "|" -f 1`
			local cmd_name=`echo "$line" |cut -d "|" -f 2`
			# is timeout
			if [ $((g_now_long_min%cyc_time)) -eq 0 ]
			then
				if [ -z "${g_x_min_task[1]}" ]
				then
					g_x_min_task[1]="${cmd_name}"
					logger "DEBUG" "<<init_task_list>> g_x_min_task[1]=$cmd_name" $LINENO	
				else
					local len=${#g_x_min_task[@]}
					local next=`expr ${len} + 1`
					g_x_min_task[${next}]="${cmd_name}"
					logger "DEBUG" "<<init_task_list>> g_x_min_task[$next]=$cmd_name" $LINENO	
				fi
			fi
		elif [ "${lab_flag}" = "@DAILY_TASK@" ]
		then
			local cyc_time=`echo "$line" |cut -d "|" -f 1`
			local cmd_name=`echo "$line" |cut -d "|" -f 2`
			if [ "D${g_HHMM}" != "${cyc_time}" ]
			then
				continue
			fi
			# if controller cancel this task
			if [ -n "${g_cancel_daily_task}" ] && [ "$(echo ${g_cancel_daily_task}|tr -d ':')" = "${cyc_time}" ]
			then
				logger "WARN " "[controller] cancel this ${g_cancel_daily_task}" $LINENO
				continue
			fi
			# is timeout
			if [ -z "${g_daily_task[1]}" ]
			then
				g_daily_task[1]="${cmd_name}"
				logger "DEBUG" "<<init_task_list>> g_daily_task[1]=$cmd_name" $LINENO	
			else
				local len=${#g_daily_task[@]}
				local next=`expr ${len} + 1`
				g_daily_task[${next}]="${cmd_name}"
				logger "DEBUG" "<<init_task_list>> g_daily_task[$next]=$cmd_name" $LINENO	
			fi
		else
			logger "ERROR" "(err_code:2006) Ignore invalid task label:$lab_flag" $LINENO
			continue
		fi
	done <${g_cache_list}
	logger "DEBUG" "<<init_task_list>>____end" $LINENO	
}

function one_min_task()
{
	if [ "${g_cancel_all_1_min_task}" = "ON" ]
	then
		logger "INFO " "[controller] cancel all 1_min_task ON" $LINENO
		return 0
	fi
	if [ -z "${g_1_min_task[1]}" ]
	then
		logger "INFO " "1_MIN_TASK list is NULL" $LINENO
		return 0
	fi
	for cmd in "${g_1_min_task[@]}"
	do
		[ -z "${cmd}" ] && continue
		logger "INFO " "[1] Start ${cmd}" $LINENO
		${cmd} &
	done
}

function unfixed_min_task()
{
	if [ -z "${g_x_min_task[1]}" ]
	then
		logger "INFO " "X_MIN_TASK list is NULL" $LINENO
		return 0
	fi
	for cmd in "${g_x_min_task[@]}"
	do
		[ -z "${cmd}" ] && continue
		logger "INFO " "[X] Start ${cmd}" $LINENO
		${cmd} &
	done
}

function daily_time_task()
{
	if [ "${g_cancel_all_daily_task}" = "ON" ]
	then
		logger "INFO " "[controller] cancel all daily_task ON" $LINENO
		return 0
	fi
	if [ -z "${g_daily_task[1]}" ]
	then
		logger "INFO " "DAILY_TASK list is NULL" $LINENO
		return 0
	fi
	for cmd in "${g_daily_task[@]}"
	do
		[ -z "${cmd}" ] && continue
		logger "INFO " "[D] Start ${cmd}" $LINENO
		${cmd} &
	done
}

# add tesk to cache file
function add_task_2_cache_list()
{
	local label_type="$1"
	local cmd_name="$2"
	case "$label_type" in
		'1_MIN_TASK' | 'X_MIN_TASK' | 'DAILY_TASK' )
			{
				local  label_name="@${label_type}@"
			}
			;;
		*)
			{
				logger "ERROR" "(err_code:2006) Ignore invalid task label:${label_type}" $LINENO
				return 0
			}
			;;
	esac
	# if uniq
	if [ `grep -w "${cmd_name}" ${g_cache_list} |wc -l` -ne 0 ]
	then
		logger "DEBUG" "exist ${cmd_name} in cache,return" $LINENO
		return 0
	fi

	if [ `grep -w "${label_name}" ${g_cache_list} |wc -l` -ne 0 ]
	then
		logger "DEBUG" "append to ${label_name}:$cmd_name" $LINENO
		sed -i "/${label_name}/a\\${cmd_name}" $g_cache_list
	else
		logger "DEBUG" "Write ${label_name}:$cmd_name" $LINENO
		echo "${label_name}" >>${g_cache_list}
		echo "${cmd_name}"   >>${g_cache_list}
	fi
	return 0
}

# refresh task list for next time 
# The reason for waiting is to maximize the perception of common ini changes.
function refresh_task_list()
{
	local is_wait="$1"
	if [ "${is_wait}" != "NO_WAIT" ]
	then
		sleep 30
	fi

	logger "DEBUG" "<<refresh_task_list>>____start" $LINENO	
	while true
	do	
		# must rebuild cache file
		[ "${is_wait}" = "NO_WAIT" ] && break
		# if common file is changed,should rebuild cache file
		if [ ! -f "${g_prev_common_list}" ] || [ ! -s "${g_prev_common_list}" ]
		then
			cp ${g_common_list} ${g_prev_common_list}
		else
			diff ${g_common_list} ${g_prev_common_list} >/dev/null
			if [ $? -eq 0 ]
			then
				logger "INFO " "common file has no change,return" $LINENO
				return 0
			else
				logger "INFO " "common file has changed !" $LINENO
			fi
		fi
		break
	done
	logger "INFO " "========== Refresh cache ini now ==========" $LINENO
	rm -rf ${g_cache_list} >/dev/null

	local all_task_vaild='true'
	while read line || [[ -n $line ]]
	do
		[ -z "${line}" ] && continue
		[ `echo "${line}" |grep '^#' |wc -l` -ne 0 ] && continue

		local cycle_time=`echo "$line" |cut -d "|" -f 1 |tr -d ' '|tr -d '\t'`
		local cmd_name=`echo "$line" |cut -d "|" -f 2 |sed 's/^[ \t]*//g'`
		# check format
		if [ `echo "${cycle_time}" |grep '.*H.*M$' |wc -l` -eq 0 ]
		then
			logger "ERROR" "(err_code:2000) Ignore bad format line:${line}" $LINENO
			local all_task_vaild='false'
			continue
		elif [ -z "${cmd_name}" ]
		then
			logger "ERROR" "(err_code:2000) CMD is NULL,Ignore bad line:${line}" $LINENO
			local all_task_vaild='false'
			continue
		fi

		local format_time=`echo "${cycle_time}" |tr -d 'M'`
		local cycle_h=`echo "${format_time}" |cut -d H -f 1`
		local cycle_m=`echo "${format_time}" |cut -d H -f 2`
		local first_hour_B="${cycle_h:0:1}"
		local first_min_B="${cycle_m:0:1}"
		local hour=`echo "${cycle_h}" |cut -d / -f 2`
		local min=`echo "${cycle_m}" |cut -d / -f 2`

		# it is maybe 1_min_task
		if [ "${first_hour_B}" = '-' -o "${first_hour_B}" = '' ]
		then
			if [ "${first_min_B}" != '/' ]
			then
				logger "ERROR" "(err_code:2001) Ignore bad format line:${line}" $LINENO
				local all_task_vaild='false'
				continue
			fi
			if [ -z "${min}" ] || [ "${min}" = "0" ] # cant 0 min cycle
			then
				logger "ERROR" "(err_code:2001) Ignore bad format line:${line}" $LINENO
				loocal all_task_vaild='false'
				continue
			elif [[ ! ${min} =~ ^[0-9]+$ ]] || [ ${min} -lt 0 -o ${min} -gt 59 ]
			then
				logger "ERROR" "(err_code:2005) Ignore bad format line:${line}" $LINENO
				loocal all_task_vaild='false'
				continue
			fi
			local total_min=${min}
			if [ ${total_min} -eq 1 ]
			then
				add_task_2_cache_list '1_MIN_TASK' "${cmd_name}"
			else
				add_task_2_cache_list 'X_MIN_TASK' "${total_min}|${cmd_name}"
			fi
		# it is maybe x_min_task
		elif [ "${first_hour_B}" = '/' ]
		then
			# $hour must be number
			if [ -z "${hour}" ] || [[ ! ${hour} =~ ^[0-9]+$ ]] 
			then
				logger "ERROR" "(err_code:2002) Ignore bad format line:${line}" $LINENO
				local all_task_vaild='false'
				continue
			elif [ ${hour} -lt 0 -o ${hour} -gt 23 ]
			then
				logger "ERROR" "(err_code:2002) Ignore bad format line:${line}" $LINENO
				local all_task_vaild='false'
				continue
			fi
			# hour is number here
			if [ "${first_min_B}" = '/' ]
			then
				# $min must be number
				if [ -z "$min}" ] || [[ ! ${min} =~ ^[0-9]+$ ]] 
				then
					logger "ERROR" "(err_code:2002) Ignore bad format line:${line}" $LINENO
					local all_task_vaild='false'
					continue
				elif [ ${min} -lt 0 -o ${min} -gt 59 ]
				then
					logger "ERROR" "(err_code:2002) Ignore bad format line:${line}" $LINENO
					local all_task_vaild='false'
					continue
				fi
				# both number
				local total_min=$((${hour}*60+${min}))
			elif [ "${first_min_B}" = '-' -o "${first_min_B}" = '' -o "${first_min_B}" = '0' ]
			then
				local total_min=$((${hour}*60))
			else
				logger "ERROR" "(err_code:2002) Ignore bad format line:${line}" $LINENO
				local all_task_vaild=='false'
				continue
			fi
			add_task_2_cache_list 'X_MIN_TASK' "${total_min}|${cmd_name}"
		# it is maybe daily task
		# cycle_h == hour
		else
			if [ "$first_min_B" = '/' ]
			then
				logger "ERROR" "(err_code:2003) Ignore bad format line:${line}" $LINENO
				local all_task_vaild='false'
				continue
			elif [ -z "${hour}" -o -z "${min}" ] || [[ ! ${hour}${min} =~ ^[0-9]+$ ]] 
			then
				logger "ERROR" "(err_code:2004) Ignore bad format line:${line}" $LINENO
				local all_task_vaild='false'
				continue
			elif [ ${hour} -lt 0 -o ${hour} -gt 23 ] || [ ${min} -lt 0 -o ${min} -gt 59 ]
			then
				logger "ERROR" "(err_code:2005) Ignore bad format line:${line}" $LINENO
				local all_task_vaild='false'
				continue
			fi
			# they are must be two digits
			# because need to match g_HHMM 
			[ -z "${hour:1:1}" ] && local hour="0${hour}"
			[ -z "${min:1:1}" ] && local min="0${min}"
			# all is number, so it is daily task.
			add_task_2_cache_list 'DAILY_TASK' "D${hour}${min}|${cmd_name}"
		fi
	done <${g_common_list}

	if [ "${all_task_vaild}" = "true" ]
	then
		logger "INFO " "ALL task is vaild" $LINENO
	else
		logger "WARN " "Not all task list is vaild" $LINENO
	fi
	cp ${g_common_list} ${g_prev_common_list}
	logger "DEBUG" "<<refresh_task_list>>____end" $LINENO	
}

function finish_done()
{
	chmod 750 $g_log_file
	chown ${g_user}:${g_group} $g_log_file

}

main()
{
	check_caller

	init_env	

	init_task_list

	one_min_task

	unfixed_min_task

	daily_time_task
	
	refresh_task_list &

	finish_done
	
}


main 

exit 0


# *** !!! This Script Can't Called By Other Process !!! *** #
# ***    Because it must be called by system cron       *** #
# *** !!! This Script Can't Called By Other Process !!! *** #
