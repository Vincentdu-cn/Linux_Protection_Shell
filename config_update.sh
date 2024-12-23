#!/bin/bash

# 定义日志文件
LOG_FILE="./result.log"

# 检查是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 用户运行此脚本。" | tee -a "$LOG_FILE"
    exit 1
fi

# 定义函数以记录日志
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 配置审计规则
configure_audit_rules() {
    log "配置审计规则..."
    cat <<EOL >> /etc/audit/rules.d/audit.rules
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins
EOL
    service auditd restart
    log "审计规则配置完成。"
}

# 配置密码策略
configure_password_policy() {
    log "配置密码策略..."
    sed -i '/^PASS_MAX_DAYS/c\PASS_MAX_DAYS   90' /etc/login.defs
    sed -i '/^PASS_MIN_DAYS/c\PASS_MIN_DAYS   3' /etc/login.defs
    sed -i '/^PASS_MIN_LEN/c\PASS_MIN_LEN    8' /etc/login.defs
    sed -i '/^PASS_WARN_AGE/c\PASS_WARN_AGE   5' /etc/login.defs

    if [ -f /etc/debian_version ]; then
        log "检测到 Ubuntu/Debian 系统，检查 libpam-pwquality 是否已安装..."
        if dpkg -l | grep -q libpam-pwquality; then
            log "libpam-pwquality 已安装。"
        else
            log "libpam-pwquality 未安装，正在安装..."
            apt-get update
            apt-get install -y libpam-pwquality
        fi
        log "写入pwquality.conf..."
        cat <<EOL > /etc/security/pwquality.conf
        minlen = 8
        dcredit = -1
        ucredit = -1
        lcredit = -1
        ocredit = -1
        difok = 3
EOL
        
    elif [ -f /etc/redhat-release ]; then
        log "检测到 CentOS/RHEL 系统，配置 /etc/pam.d/system-auth..."
        echo "password requisite pam_pwquality.so try_first_pass local_users_only retry=5 authtok_type= minlen=8 difok=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1" >> /etc/pam.d/system-auth
    fi
    
    log "密码策略配置完成。"
}

# 配置登录失败次数及锁定策略
configure_login_failures() {
    log "配置登录失败次数及锁定策略..."
   
    line1="auth  [default=die]  pam_faillock.so authfail audit deny=5 unlock_time=600 fail_interval=900"
    line2="auth  sufficient  pam_faillock.so authsucc audit deny=5 unlock_time=600 fail_interval=900"
    # 定义目标文件
    file="/etc/pam.d/common-auth"
    
    # 使用 sed 插入行
    sed -i "/pam_unix.so/a\\
    $line1\\
    $line2" "$file"
    
    log "登录失败次数及锁定策略配置完成。"
}

# 配置SSH登录超时策略
configure_sshlogin() {
    log "配置SSH登录超时策略..."
    echo -e "ClientAliveInterval 1800\nClientAliveCountMax 2" >> /etc/ssh/sshd_config
    log "SSH登录超时策略配置完成。"
}
# 显示菜单
show_menu() {
    echo "请选择要执行的操作："
    echo "1) 一键全修复"
    echo "2) 配置审计规则"
    echo "3) 配置密码策略"
    echo "4) 配置登录失败次数及锁定策略"
    echo "5) 配置SSH登录超时策略"
    echo "6) 退出"
}

# 主程序
while true; do
    show_menu
    read -p "请输入选项 (1-6): " choice
    case $choice in
        1)
            configure_audit_rules
            configure_password_policy
            configure_login_failures
            log "所有修复已完成。"
            ;;
        2)
            configure_audit_rules
            ;;
        3)
            configure_password_policy
            ;;
        4)
        
            configure_login_failures
            ;;
        5)
        
            configure_sshlogin
            ;;
        6)
            log "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项，请输入 1 到 6 之间的数字。"
            ;;
    esac
done
