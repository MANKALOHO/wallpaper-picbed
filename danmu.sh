#!/data/data/com.termux/files/usr/bin/bash

# ====================== 颜色 ======================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ====================== 项目配置 ======================
PROJECTS=(
    "project_a,弹幕API-稳定版,https://github.com/huangxd-/danmu_api.git,danmu_api_stable,9321,npm start"
    "project_b,弹幕API-探索版,https://github.com/lilixu3/danmu_api.git,danmu_api_dev,9322,npm start"
)

CUR_ARG=""
CUR_NAME=""
CUR_GIT=""
CUR_DIR=""
CUR_PORT=""
CUR_CMD=""

load_project_config() {
    local arg="$1"
    for project in "${PROJECTS[@]}"; do
        IFS=',' read -r p_arg p_name p_git p_dir p_port p_cmd <<< "$project"
        if [ "$arg" = "$p_arg" ]; then
            CUR_ARG="$p_arg"
            CUR_NAME="$p_name"
            CUR_GIT="$p_git"
            CUR_DIR="$HOME/$p_dir"
            CUR_PORT="$p_port"
            CUR_CMD="$p_cmd"
            return 0
        fi
    done
    return 1
}

check_installed() {
    local dir="$1"
    [ -d "$dir/.git" ] && [ -d "$dir/node_modules" ]
}

# 检测服务是否在运行（端口是否可连接）
is_running() {
    curl -s --connect-timeout 2 --max-time 3 http://127.0.0.1:$CUR_PORT > /dev/null 2>&1
}

# 可靠的进程终止（多重兜底）
stop_service() {
    local port=$1
    # 1. fuser
    if command -v fuser &> /dev/null; then
        fuser -k ${port}/tcp 2>/dev/null
    fi
    # 2. lsof 找 PID
    if command -v lsof &> /dev/null; then
        local pid=$(lsof -t -i:${port} 2>/dev/null)
        [ -n "$pid" ] && kill -9 $pid 2>/dev/null
    fi
    # 3. ss 找 PID
    if command -v ss &> /dev/null; then
        local pid=$(ss -tlnp sport = :${port} 2>/dev/null | grep -oP 'pid=\K[0-9]+')
        [ -n "$pid" ] && kill -9 $pid 2>/dev/null
    fi
    sleep 0.5
}

get_dir_by_arg() {
    local arg="$1"
    for project in "${PROJECTS[@]}"; do
        IFS=',' read -r p_arg p_name p_git p_dir p_port p_cmd <<< "$project"
        if [ "$arg" = "$p_arg" ]; then
            echo "$HOME/$p_dir"
            return 0
        fi
    done
    echo ""
}

ensure_termux_api() {
    if ! command -v termux-wake-lock &> /dev/null; then
        safe_pkg_install termux-api
    fi
    termux-wake-lock 2>/dev/null
}

release_wakelock() {
    termux-wake-unlock 2>/dev/null
}

safe_pkg_install() {
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NONINTERACTIVE_SEEN=true
    echo "n" | pkg install "$@" -y
}

# ====================== 国内镜像 ======================
MIRROR_FLAG="$HOME/.termux_mirror_set"
setup_mirrors() {
    if [ -f "$MIRROR_FLAG" ]; then
        return 0
    fi
    echo -e "${BLUE}首次配置 Termux 清华镜像源...${NC}"
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main" > $PREFIX/etc/apt/sources.list
    pkg update -y
    if ! timeout 2 curl -s https://registry.npmjs.org > /dev/null; then
        npm config set registry https://registry.npmmirror.com
    fi
    touch "$MIRROR_FLAG"
    echo -e "${GREEN}镜像配置完成${NC}"
}

# ====================== Git 加速 ======================
GIT_PROXIES=(
    "https://ghproxy.com/"
    "https://gh-proxy.org/"
    "https://v4.gh-proxy.org/"
    "https://v6.gh-proxy.org/"
    "https://cdn.gh-proxy.org/"
    "https://gh.api.99988866.xyz/"
    "https://github.com.cnpmjs.org/"
)

smart_clone() {
    local repo="$1" target="$2"
    while true; do
        echo -e "${BLUE}尝试直连 GitHub...${NC}"
        if timeout 30 git clone --quiet "$repo" "$target" 2>/dev/null; then
            return 0
        fi
        rm -rf "$target" 2>/dev/null

        echo -e "${YELLOW}直连失败，尝试国内加速节点...${NC}"
        for proxy in "${GIT_PROXIES[@]}"; do
            echo -n "  → $proxy "
            if timeout 30 git clone --quiet "${proxy}${repo}" "$target" 2>/dev/null; then
                echo -e "${GREEN}成功${NC}"
                return 0
            else
                echo -e "${RED}失败${NC}"
                rm -rf "$target" 2>/dev/null
            fi
        done

        echo -e "${RED}所有加速节点均失败${NC}"
        echo "1. 重试  2. 手动输入代理  3. 退出"
        read -p "请选择 [1-3] (默认 1)：" choice
        case ${choice:-1} in
            1) continue ;;
            2)
                read -p "输入代理前缀（结尾带 /）：" custom_proxy
                if [ -n "$custom_proxy" ]; then
                    echo -e "${BLUE}尝试自定义代理...${NC}"
                    if timeout 30 git clone --quiet "${custom_proxy}${repo}" "$target" 2>/dev/null; then
                        echo -e "${GREEN}成功${NC}"
                        return 0
                    fi
                    rm -rf "$target" 2>/dev/null
                fi
                continue
                ;;
            3) return 1 ;;
            *) continue ;;
        esac
    done
}

# ====================== 安装单个项目（不启动） ======================
install_single() {
    local arg="$1"
    load_project_config "$arg"

    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}     正在安装 $CUR_NAME${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    ensure_termux_api
    setup_mirrors

    if ! command -v timeout &> /dev/null; then
        safe_pkg_install coreutils
    fi

    # 1. 环境
    echo -e "${YELLOW}【1/4】检测环境${NC}"
    for pkg in curl git nodejs; do
        if command -v $pkg &> /dev/null; then
            echo -e "${GREEN}✅ $pkg 已就绪${NC}"
        else
            echo -e "${BLUE}安装 $pkg ...${NC}"
            safe_pkg_install $pkg
        fi
    done
    echo ""

    # 2. 代码
    echo -e "${YELLOW}【2/4】获取代码${NC}"
    if [ -d "$CUR_DIR/.git" ]; then
        cd "$CUR_DIR"
        git pull --quiet
        echo -e "${GREEN}✅ 代码已更新${NC}"
    else
        [ -d "$CUR_DIR" ] && rm -rf "$CUR_DIR"
        if ! smart_clone "$CUR_GIT" "$CUR_DIR"; then
            echo -e "${RED}代码下载失败，安装中止${NC}"
            release_wakelock
            exit 1
        fi
        echo -e "${GREEN}✅ 代码下载完成${NC}"
    fi
    cd "$CUR_DIR"
    echo ""

    # 3. 依赖
    echo -e "${YELLOW}【3/4】安装依赖${NC}"
    while true; do
        if [ -d "node_modules" ] && [ -f "node_modules/express/package.json" ]; then
            echo -e "${GREEN}✅ 依赖已完整${NC}"
            break
        fi
        echo -e "${BLUE}正在安装依赖（约2-3分钟）...${NC}"
        npm install --production --no-audit --no-fund --quiet
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ 依赖安装完成${NC}"
            break
        else
            echo -e "${RED}依赖安装失败${NC}"
            echo "1. 重试  2. 跳过（可能无法启动）  3. 退出"
            read -p "请选择 [1-3] (默认 1)：" dchoice
            case ${dchoice:-1} in
                1) continue ;;
                2) break ;;
                3) release_wakelock; exit 1 ;;
            esac
        fi
    done
    echo ""

    echo -e "${GREEN}✅ $CUR_NAME 安装完成${NC}"
    show_info
    echo ""
    release_wakelock
}

show_info() {
    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e "  地址：http://127.0.0.1:$CUR_PORT"
    echo -e "  Token：87654321"
    echo -e "  日志：$CUR_DIR/server.log"
    echo -e "${GREEN}----------------------------------------${NC}"
}

# ====================== 单个项目管理菜单 ======================
manage_project() {
    local arg="$1"
    load_project_config "$arg"

    while true; do
        local lan_ip=""
        if command -v ifconfig &> /dev/null; then
            lan_ip=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
        fi
        if [ -z "$lan_ip" ] && command -v ip &> /dev/null; then
            lan_ip=$(ip -4 addr show wlan0 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
        fi
        if [ -z "$lan_ip" ] && command -v hostname &> /dev/null; then
            lan_ip=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '127.0.0.1' | head -1)
        fi

        clear
        echo -e "${GREEN}========================================${NC}"
        echo -e "   $CUR_NAME"
        echo -e "${GREEN}========================================${NC}"
        echo ""

        if is_running; then
            echo -e "状态：${GREEN}● 运行中（$CUR_NAME）${NC}"
            local action_text="停止服务"
        else
            echo -e "状态：${RED}○ 未运行（$CUR_NAME）${NC}"
            local action_text="启动服务"
        fi
        echo ""

        echo "1. ${action_text}"
        echo "2. 更新代码"
        echo "3. 重装依赖（删除 node_modules 并重新安装）"
        echo "4. 查看日志(最近20行)"
        echo "5. 卸载本项目（删除所有文件）"
        echo "6. 切换管理其他版本"
        echo "0. 退出"
        echo ""

        echo -e "${YELLOW}访问地址：${NC}"
        echo -e "  本地：http://127.0.0.1:$CUR_PORT"
        if [ -n "$lan_ip" ]; then
            echo -e "  局域网：http://$lan_ip:$CUR_PORT"
        else
            echo -e "  局域网：${RED}未连接 WiFi${NC}"
        fi
        echo -e "  Token：87654321"
        if ! is_running; then
            echo -e "  ${RED}（服务未运行，地址可能不可用）${NC}"
        fi
        echo ""

        read -p "请输入选项 [0-6] (默认 0)：" choice
        case ${choice:-0} in
            1)
                if [ "$action_text" = "启动服务" ]; then
                    stop_service $CUR_PORT   # 先确保端口干净
                    cd "$CUR_DIR"
                    nohup $CUR_CMD > server.log 2>&1 &
                    echo -e "${GREEN}已启动${NC}"
                    sleep 1
                else
                    stop_service $CUR_PORT
                    echo -e "${GREEN}已停止${NC}"
                fi
                ;;
            2)
                cd "$CUR_DIR"
                echo -e "${BLUE}正在更新...${NC}"
                git pull --quiet
                echo -e "${GREEN}更新完成${NC}"
                ;;
            3)
                cd "$CUR_DIR"
                echo -e "${BLUE}删除旧依赖...${NC}"
                rm -rf node_modules
                echo -e "${BLUE}重新安装依赖（约2-3分钟）...${NC}"
                npm install --production --no-audit --no-fund --quiet
                echo -e "${GREEN}依赖安装完成${NC}"
                ;;
            4)
                cd "$CUR_DIR"
                echo -e "${BLUE}最近日志：${NC}"
                tail -n 20 server.log
                echo ""
                ;;
            5)
                read -p "确定要删除 $CUR_NAME 的所有文件吗？(输入 yes 确认，默认取消)：" confirm
                if [ "${confirm:-no}" = "yes" ]; then
                    stop_service $CUR_PORT
                    rm -rf "$CUR_DIR"
                    echo -e "${GREEN}已卸载${NC}"
                    break
                else
                    echo -e "${YELLOW}已取消${NC}"
                fi
                ;;
            6)
                local target="project_b"
                [ "$CUR_ARG" = "project_b" ] && target="project_a"
                if check_installed "$(get_dir_by_arg $target)"; then
                    manage_project "$target"
                else
                    install_single "$target"
                    manage_project "$target"
                fi
                return
                ;;
            0)
                release_wakelock
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
        [ "${choice:-0}" != "0" ] && read -p "按回车继续..."
    done
}

# ====================== 主菜单 ======================
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}========================================${NC}"
        echo -e "   弹幕 API 一键部署工具箱"
        echo -e "${GREEN}========================================${NC}"
        echo ""

        local stable_installed="未安装"
        local dev_installed="未安装"
        if check_installed "$(get_dir_by_arg project_a)"; then
            stable_installed="${GREEN}已安装${NC}"
        fi
        if check_installed "$(get_dir_by_arg project_b)"; then
            dev_installed="${GREEN}已安装${NC}"
        fi

        echo -e "1. 弹幕API-稳定版 (端口 9321)  [状态：$stable_installed]"
        echo -e "2. 弹幕API-探索版 (端口 9322)  [状态：$dev_installed]"
        echo "3. 同时下载两个版本（不启动）"
        echo "0. 退出"
        echo ""
        read -p "请选择 [0-3] (默认 0)：" choice
        case ${choice:-0} in
            1)
                if check_installed "$(get_dir_by_arg project_a)"; then
                    manage_project project_a
                else
                    install_single project_a
                    read -p "安装完成，按回车进入管理菜单 (输入 n 返回主菜单)：" yn
                    if [ "${yn:-y}" != "n" ]; then
                        manage_project project_a
                    fi
                fi
                ;;
            2)
                if check_installed "$(get_dir_by_arg project_b)"; then
                    manage_project project_b
                else
                    install_single project_b
                    read -p "安装完成，按回车进入管理菜单 (输入 n 返回主菜单)：" yn
                    if [ "${yn:-y}" != "n" ]; then
                        manage_project project_b
                    fi
                fi
                ;;
            3)
                echo -e "${BLUE}即将下载两个版本，请稍候...${NC}"
                for arg in project_a project_b; do
                    if ! check_installed "$(get_dir_by_arg $arg)"; then
                        install_single "$arg"
                    else
                        echo -e "${GREEN}项目 ${arg} 已安装，跳过${NC}"
                        sleep 1
                    fi
                done
                echo -e "${GREEN}下载完成！请返回主菜单选择要启动的版本。${NC}"
                read -p "按回车返回主菜单..."
                ;;
            0)
                release_wakelock
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====================== 入口 ======================
ensure_termux_api

if [ -n "$1" ]; then
    if load_project_config "$1"; then
        if check_installed "$CUR_DIR"; then
            manage_project "$1"
        else
            install_single "$1"
            read -p "安装完成，按回车进入管理菜单 (输入 n 返回主菜单)：" yn
            if [ "${yn:-y}" != "n" ]; then
                manage_project "$1"
            fi
        fi
    else
        echo -e "${RED}无效的项目参数：$1${NC}"
        exit 1
    fi
else
    main_menu
fi

release_wakelock