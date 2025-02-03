#!/bin/bash

function show_usage() {
    echo "Usage: $0 <command> [client_number]"
    echo "Commands:"
    echo "  create <number> - Create a new client"
    echo "  delete <number> - Delete an existing client"
    echo "  list           - List all clients"
    exit 1
}

function get_next_available_number() {
    local i=1
    while true; do
        # 检查当前编号是否已被使用
        if ! grep -q "# Client${i} 服務" docker-compose.yml; then
            echo $i
            return
        fi
        ((i++))
    done
}

function create_client() {
    local CLIENT_NUM=$1
    local CLIENT="client${CLIENT_NUM}"
    local DB_HOST="db${CLIENT_NUM}"
    local DB_USER="odoo${CLIENT_NUM}"
    local DB_PASSWORD="odoo${CLIENT_NUM}"
    local WEB_PORT=$((8000 + CLIENT_NUM))
    local LONGPOLLING_PORT=$((9000 + CLIENT_NUM))
    local DB_PORT=$((5400 + CLIENT_NUM))

    # 检查目录是否已存在
    if [ -d "${CLIENT}" ]; then
        echo "Error: ${CLIENT} already exists"
        exit 1
    fi

    # 创建目录结构
    mkdir -p ${CLIENT}/{config,data,logs,postgresql,db}
    chmod -R 777 ${CLIENT}

    # 创建配置文件
    sed "s/{CLIENT}/${CLIENT_NUM}/g; s/{DB_HOST}/${DB_HOST}/g; s/{DB_USER}/${DB_USER}/g; s/{DB_PASSWORD}/${DB_PASSWORD}/g" odoo.conf.template > ${CLIENT}/config/odoo.conf

    # 添加服务到 docker-compose.yml
    local CONFIG="  # Client${CLIENT_NUM} 服務\n"
    CONFIG+="  web${CLIENT_NUM}:\n"
    CONFIG+="    build: .\n"
    CONFIG+="    image: custom-odoo:16.0\n"
    CONFIG+="    depends_on:\n"
    CONFIG+="      - db${CLIENT_NUM}\n"
    CONFIG+="    volumes:\n"
    CONFIG+="      - ./${CLIENT}/config:/etc/odoo\n"
    CONFIG+="      - ./${CLIENT}/data:/var/lib/odoo/${CLIENT}\n"
    CONFIG+="      - ./${CLIENT}/logs:/var/log/odoo\n"
    CONFIG+="      - ./addons:/mnt/addons\n"
    CONFIG+="      - ./custom-addons:/mnt/custom-addons\n"
    CONFIG+="    ports:\n"
    CONFIG+="      - \"${WEB_PORT}:8069\"\n"
    CONFIG+="      - \"${LONGPOLLING_PORT}:8072\"\n"
    CONFIG+="    environment:\n"
    CONFIG+="      - LANG=zh_TW.UTF-8\n"
    CONFIG+="      - TZ=Asia/Taipei\n"
    CONFIG+="    command: -- --init=base,dtsc\n"
    CONFIG+="    networks:\n"
    CONFIG+="      - odoo_net\n"
    CONFIG+="    restart: unless-stopped\n\n"
    CONFIG+="  db${CLIENT_NUM}:\n"
    CONFIG+="    image: postgres:15\n"
    CONFIG+="    environment:\n"
    CONFIG+="      - POSTGRES_DB=postgres\n"
    CONFIG+="      - POSTGRES_PASSWORD=${DB_PASSWORD}\n"
    CONFIG+="      - POSTGRES_USER=${DB_USER}\n"
    CONFIG+="      - PGDATA=/var/lib/postgresql/data/pgdata\n"
    CONFIG+="    volumes:\n"
    CONFIG+="      - ./${CLIENT}/postgresql:/var/lib/postgresql/data\n"
    CONFIG+="    ports:\n"
    CONFIG+="      - \"${DB_PORT}:5432\"\n"
    CONFIG+="    networks:\n"
    CONFIG+="      - odoo_net\n"
    CONFIG+="    restart: unless-stopped\n"
    CONFIG+="    command: postgres -c 'max_connections=200'\n\n"

    # 使用临时文件来避免多次插入
    awk -v config="$CONFIG" '
    /^networks:/ { print config }
    { print }
    ' docker-compose.yml > docker-compose.yml.tmp
    mv docker-compose.yml.tmp docker-compose.yml

    echo "Client ${CLIENT} created successfully"
    echo "Web port: ${WEB_PORT}"
    echo "Longpolling port: ${LONGPOLLING_PORT}"
    echo "Database port: ${DB_PORT}"

    # 启动新创建的服务
    echo "Starting services..."
    docker-compose up -d web${CLIENT_NUM} db${CLIENT_NUM}
}

function delete_client() {
    local CLIENT_NUM=$1
    local CLIENT="client${CLIENT_NUM}"

    # 检查客户端是否存在（检查配置或目录）
    if ! grep -q "# Client${CLIENT_NUM} 服務" docker-compose.yml && ! [ -d "${CLIENT}" ]; then
        echo "Error: ${CLIENT} does not exist"
        exit 1
    fi

    # 停止并删除容器
    echo "Stopping and removing containers..."
    docker-compose stop web${CLIENT_NUM} db${CLIENT_NUM} 2>/dev/null || true
    docker-compose rm -f web${CLIENT_NUM} db${CLIENT_NUM} 2>/dev/null || true

    # 删除目录
    echo "Removing client directory..."
    sudo rm -rf ${CLIENT}

    # 从 docker-compose.yml 中删除服务配置
    echo "Removing service configuration..."
    # 使用 sed 更精确地删除配置块
    sed -i "/# Client${CLIENT_NUM} 服務/,/^$/d" docker-compose.yml
    sed -i "/^[[:space:]]*web${CLIENT_NUM}:/,/^$/d" docker-compose.yml
    sed -i "/^[[:space:]]*db${CLIENT_NUM}:/,/^$/d" docker-compose.yml
    # 删除多余的空行，但保留文件结构
    sed -i '/^[[:space:]]*$/N;/^\n[[:space:]]*$/D' docker-compose.yml
    
    echo "Client ${CLIENT} deleted successfully"
}

function list_clients() {
    echo "Current clients:"
    grep -n "# Client[0-9]* 服務" docker-compose.yml | cut -d':' -f2- | sed 's/# Client\([0-9]*\) 服務/  Client \1/'
}

# 主程序
case "$1" in
    create)
        if [ -z "$2" ]; then
            CLIENT_NUM=$(get_next_available_number)
            echo "Using next available number: ${CLIENT_NUM}"
        else
            CLIENT_NUM=$2
        fi
        create_client ${CLIENT_NUM}
        ;;
    delete)
        [ -z "$2" ] && show_usage
        delete_client $2
        ;;
    list)
        list_clients
        ;;
    *)
        show_usage
        ;;
esac 