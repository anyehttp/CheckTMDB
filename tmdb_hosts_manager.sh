#!/bin/bash

# ============================================
# TMDB Hosts 管理器脚本
# 功能：管理 TMDB 相关域名的 hosts 配置
# ============================================

# 配置变量
HOSTS_FILE="/etc/hosts"
CONFIG_DIR="/etc/tmdb-hosts"
LOG_FILE="${CONFIG_DIR}/tmdb_hosts.log"
BACKUP_DIR="${CONFIG_DIR}/backups"
IPV4_URL="https://gh-proxy.org/https://raw.githubusercontent.com/cnwikee/CheckTMDB/refs/heads/main/Tmdb_host_ipv4"
IPV6_URL="https://gh-proxy.org/https://raw.githubusercontent.com/cnwikee/CheckTMDB/refs/heads/main/Tmdb_host_ipv6"

# 标记区域（用于识别我们添加的内容）
START_MARKER="# Tmdb Hosts Start - Auto Generated"
END_MARKER="# Tmdb Hosts End - Auto Generated"

# 脚本路径
SCRIPT_PATH="/usr/local/bin/tmdb_hosts_manager.sh"

# 创建必要的目录
init_dirs() {
    mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}"
}

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# 备份 hosts 文件
backup_hosts() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/hosts.backup.${timestamp}"
    cp "${HOSTS_FILE}" "${backup_file}"
    log "INFO" "Hosts 文件已备份到: ${backup_file}"
}

# 清理旧的 TMDB hosts 记录
clean_old_tmdb_hosts() {
    log "INFO" "开始清理旧的 TMDB hosts 记录..."
    
    # 如果标记区域不存在，则无需清理
    if ! grep -q "${START_MARKER}" "${HOSTS_FILE}"; then
        log "INFO" "未找到旧的 TMDB hosts 记录，跳过清理"
        return 0
    fi
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 删除两个标记之间的所有内容（包括标记本身）
    sed "/${START_MARKER}/,/${END_MARKER}/d" "${HOSTS_FILE}" > "${temp_file}"
    
    # 替换原文件
    cat "${temp_file}" > "${HOSTS_FILE}"
    rm -f "${temp_file}"
    
    # 删除可能存在的空行
    sed -i '/^$/N;/\n$/D' "${HOSTS_FILE}"
    
    log "INFO" "旧的 TMDB hosts 记录已清理"
}

# 获取最新的 TMDB IP 地址
fetch_tmdb_ips() {
    log "INFO" "开始获取最新的 TMDB IP 地址..."
    
    # 获取 IPv4 地址
    local ipv4_content=$(curl -s -f "${IPV4_URL}")
    if [ $? -ne 0 ] || [ -z "${ipv4_content}" ]; then
        log "ERROR" "无法获取 IPv4 地址"
        return 1
    fi
    
    # 获取 IPv6 地址
    local ipv6_content=$(curl -s -f "${IPV6_URL}")
    if [ $? -ne 0 ] || [ -z "${ipv6_content}" ]; then
        log "WARN" "无法获取 IPv6 地址，继续使用 IPv4"
    fi
    
    # 提取更新时间
    local update_time=$(echo "${ipv4_content}" | grep "^# Update time:" | sed 's/# Update time: //')
    if [ -z "${update_time}" ]; then
        update_time=$(date '+%Y-%m-%dT%H:%M:%S%z')
    fi
    
    # 保存到临时文件
    echo "${ipv4_content}" > "${CONFIG_DIR}/tmdb_ipv4_latest.txt"
    echo "${ipv6_content}" > "${CONFIG_DIR}/tmdb_ipv6_latest.txt"
    echo "${update_time}" > "${CONFIG_DIR}/last_update.txt"
    
    log "INFO" "TMDB IP 地址获取成功，更新时间: ${update_time}"
    return 0
}

# 添加新的 TMDB hosts 记录
add_new_tmdb_hosts() {
    log "INFO" "开始添加新的 TMDB hosts 记录..."
    
    # 读取最新的 IP 地址
    local ipv4_content=$(cat "${CONFIG_DIR}/tmdb_ipv4_latest.txt" 2>/dev/null)
    local ipv6_content=$(cat "${CONFIG_DIR}/tmdb_ipv6_latest.txt" 2>/dev/null)
    local update_time=$(cat "${CONFIG_DIR}/last_update.txt" 2>/dev/null)
    
    if [ -z "${ipv4_content}" ]; then
        log "ERROR" "没有可用的 TMDB IP 地址"
        return 1
    fi
    
    if [ -z "${update_time}" ]; then
        update_time=$(date '+%Y-%m-%dT%H:%M:%S%z')
    fi
    
    # 添加分隔行和新记录
    echo "" >> "${HOSTS_FILE}"
    echo "${START_MARKER}" >> "${HOSTS_FILE}"
    echo "# 更新时间: ${update_time}" >> "${HOSTS_FILE}"
    echo "# 来源: ${IPV4_URL}" >> "${HOSTS_FILE}"
    echo "" >> "${HOSTS_FILE}"
    
    # 添加 IPv4 记录
    echo "${ipv4_content}" | grep -v "^#" >> "${HOSTS_FILE}"
    
    # 添加 IPv6 记录（如果有）
    if [ -n "${ipv6_content}" ]; then
        echo "" >> "${HOSTS_FILE}"
        echo "${ipv6_content}" | grep -v "^#" >> "${HOSTS_FILE}"
    fi
    
    echo "" >> "${HOSTS_FILE}"
    echo "${END_MARKER}" >> "${HOSTS_FILE}"
    
    log "INFO" "新的 TMDB hosts 记录已添加"
}

# 选项1：更新 hosts
update_hosts() {
    log "INFO" "执行选项1：更新 hosts"
    
    # 备份
    backup_hosts
    
    # 清理旧的 TMDB 记录
    clean_old_tmdb_hosts
    
    # 获取最新的 TMDB IP
    if ! fetch_tmdb_ips; then
        log "ERROR" "更新失败：无法获取 TMDB IP 地址"
        return 1
    fi
    
    # 添加新的记录
    add_new_tmdb_hosts
    
    # 验证
    local tmdb_count=$(grep -c "themoviedb\|tmdb.org" "${HOSTS_FILE}")
    log "INFO" "更新完成！当前 hosts 中包含 ${tmdb_count} 条 TMDB 相关记录"
    
    # 显示更新后的记录
    echo ""
    echo "更新后的 TMDB 相关记录："
    grep -A5 -B5 "themoviedb\|tmdb.org" "${HOSTS_FILE}" | head -20
}

# 选项2：去除已添加的 IP
remove_tmdb_hosts() {
    log "INFO" "执行选项2：去除已添加的 TMDB hosts 记录"
    
    # 备份
    backup_hosts
    
    # 清理旧的 TMDB 记录
    clean_old_tmdb_hosts
    
    log "INFO" "TMDB hosts 记录已移除"
    
    # 显示移除后的状态
    echo ""
    echo "TMDB hosts 记录已成功移除"
    echo "当前 hosts 文件中 TMDB 相关记录数量："
    grep -c "themoviedb\|tmdb.org" "${HOSTS_FILE}"
}

# 选项3：设置定时任务
setup_cron_job() {
    log "INFO" "执行选项3：设置定时任务"
    
    # 检查脚本是否存在
    if [ ! -f "${SCRIPT_PATH}" ]; then
        log "ERROR" "脚本不存在: ${SCRIPT_PATH}"
        echo "请确保脚本已正确安装到 /usr/local/bin/"
        return 1
    fi
    
    # 创建 cron 配置
    local cron_config="0 9 * * * ${SCRIPT_PATH} --cron-update"
    
    # 检查是否已有定时任务
    if crontab -l 2>/dev/null | grep -q "tmdb_hosts_manager.sh"; then
        echo "检测到已存在的定时任务，将先移除旧任务..."
        # 移除旧的定时任务
        crontab -l 2>/dev/null | grep -v "tmdb_hosts_manager.sh" | crontab -
        sleep 1
    fi
    
    # 添加新的定时任务
    (crontab -l 2>/dev/null; echo "${cron_config}") | crontab -
    
    if [ $? -eq 0 ]; then
        log "INFO" "定时任务设置成功：每天早上9点自动更新 hosts"
        echo ""
        echo "定时任务已成功设置！"
        echo "执行时间：每天上午 9:00"
        echo "执行命令：${SCRIPT_PATH} --cron-update"
        echo ""
        echo "当前用户的定时任务列表："
        crontab -l
    else
        log "ERROR" "定时任务设置失败"
        return 1
    fi
}

# 选项4：移除定时任务
remove_cron_job() {
    log "INFO" "执行选项4：移除定时任务"
    
    # 检查是否存在定时任务
    if ! crontab -l 2>/dev/null | grep -q "tmdb_hosts_manager.sh"; then
        echo "当前没有找到与 TMDB hosts 相关的定时任务"
        log "INFO" "未找到定时任务，无需移除"
        return 0
    fi
    
    # 移除定时任务
    echo "正在移除定时任务..."
    crontab -l 2>/dev/null | grep -v "tmdb_hosts_manager.sh" | crontab -
    
    if [ $? -eq 0 ]; then
        log "INFO" "定时任务已成功移除"
        echo ""
        echo "定时任务已成功移除！"
        echo ""
        echo "当前用户的定时任务列表："
        crontab -l
    else
        log "ERROR" "定时任务移除失败"
        echo "定时任务移除失败"
        return 1
    fi
}

# 定时任务专用更新函数（无交互）
cron_update() {
    log "INFO" "定时任务执行：开始自动更新 TMDB hosts"
    
    # 备份
    backup_hosts
    
    # 清理旧的 TMDB 记录
    clean_old_tmdb_hosts
    
    # 获取最新的 TMDB IP
    if fetch_tmdb_ips; then
        # 添加新的记录
        add_new_tmdb_hosts
        log "INFO" "定时任务执行：TMDB hosts 自动更新完成"
    else
        log "ERROR" "定时任务执行：TMDB hosts 自动更新失败"
    fi
}

# 显示帮助信息
show_help() {
    echo ""
    echo "TMDB Hosts 管理器"
    echo "=================="
    echo ""
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  1          更新 hosts（清理旧的并添加新的）"
    echo "  2          去除已添加的 TMDB hosts 记录"
    echo "  3          设置定时任务（每天早上9点自动更新）"
    echo "  4          移除定时任务"
    echo "  --cron-update  定时任务专用更新（无交互）"
    echo "  --help      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 1        # 更新 hosts"
    echo "  $0 2        # 移除 TMDB hosts 记录"
    echo "  $0 3        # 设置定时任务"
    echo "  $0 4        # 移除定时任务"
    echo ""
}

# 显示菜单
show_menu() {
    clear
    echo "==================================="
    echo "      TMDB Hosts 管理器"
    echo "==================================="
    echo ""
    echo "请选择要执行的操作："
    echo ""
    echo "  1. 更新 hosts"
    echo "     - 去除旧的 TMDB hosts 记录"
    echo "     - 添加最新的 TMDB IP 地址"
    echo ""
    echo "  2. 去除已添加的 TMDB hosts 记录"
    echo "     - 清理所有 TMDB 相关的 hosts 记录"
    echo ""
    echo "  3. 设置定时任务"
    echo "     - 每天早上9点自动更新 hosts"
    echo ""
    echo "  4. 移除定时任务"
    echo "     - 移除自动更新的定时任务"
    echo ""
    echo "  h. 帮助信息"
    echo "  q. 退出"
    echo ""
    echo "==================================="
    read -p "请输入选项 (1-4, h, q): " choice
    
    case "${choice}" in
        1)
            update_hosts
            ;;
        2)
            remove_tmdb_hosts
            ;;
        3)
            setup_cron_job
            ;;
        4)
            remove_cron_job
            ;;
        h|H|help|HELP)
            show_help
            ;;
        q|Q|quit|QUIT)
            echo "退出程序"
            exit 0
            ;;
        *)
            echo "无效的选项，请重新输入"
            sleep 2
            show_menu
            ;;
    esac
}

# 主函数
main() {
    # 初始化目录
    init_dirs
    
    # 记录脚本开始执行
    log "INFO" "脚本开始执行，参数: $*"
    
    # 检查是否以 root 运行
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 此脚本需要 root 权限运行" >&2
        echo "请使用 sudo 执行: sudo $0" >&2
        exit 1
    fi
    
    # 根据参数执行相应操作
    case "$1" in
        "1")
            update_hosts
            ;;
        "2")
            remove_tmdb_hosts
            ;;
        "3")
            setup_cron_job
            ;;
        "4")
            remove_cron_job
            ;;
        "--cron-update")
            cron_update
            ;;
        "--help"|"-h")
            show_help
            ;;
        "")
            # 无参数，显示菜单
            show_menu
            ;;
        *)
            echo "错误: 未知的参数: $1"
            show_help
            exit 1
            ;;
    esac
    
    # 询问用户是否返回菜单
    if [ -z "$1" ]; then
        echo ""
        read -p "按 Enter 键返回主菜单，或输入 q 退出: " return_choice
        if [ "${return_choice}" != "q" ] && [ "${return_choice}" != "Q" ]; then
            show_menu
        else
            echo "退出程序"
        fi
    fi
    
    log "INFO" "脚本执行完成"
}

# 执行主函数
main "$@"
