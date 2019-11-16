***
__《crontab调度器》__
***
__功能：__

* 托管操作系统的cron任务，统一由此调度器来调度，方便管理维护及动态扩展。

__用法：__
只需要在crontab中加入 */1 * * * * sh /YourPath/crontab_scheduler.sh 
即可调用主进程，然后主进程负责调用配置文件中的合个任务子进程。

***
__crontab_common_task.ini:__
* 公共任务配置文件；提供给其他进程添加和删除任务的配置文件
__crontab_controller__
* 调度机控制器；提供灵活调度任务等的控制和管理
__crontab_scheduler.sh__
* 主进程脚本；系统crond调用
***

__注意这三个文件所在的目录结构：__

/YOURPATH/crontab_scheduler.sh

/YOURPATH/log/crontab_controller

/YOURPATH/log/crontab_common_task.ini
