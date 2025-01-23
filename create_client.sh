#!/bin/bash

# 检查参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <client_number>"
    exit 1
fi

# 确保在正确的目录中
cd "$(dirname "$0")" || exit 1

CLIENT_NUM=$1
CLIENT="client${CLIENT_NUM}"
DB_HOST="db${CLIENT_NUM}"
DB_USER="odoo${CLIENT_NUM}"
DB_PASSWORD="odoo${CLIENT_NUM}"
WEB_PORT=$((8068 + CLIENT_NUM))
LONGPOLLING_PORT=$((9068 + CLIENT_NUM))
DB_PORT=$((5431 + CLIENT_NUM))

# 检查目录是否已存在
if [ -d "${CLIENT}" ] || [ -d "custom-addons-${CLIENT}" ]; then
    echo "Error: ${CLIENT} or custom-addons-${CLIENT} already exists"
    exit 1
fi

# 创建必要的目录
mkdir -p ${CLIENT}/{config,data,logs,postgresql}
mkdir -p custom-addons-${CLIENT}

# 从模板创建配置文件
sed "s/{CLIENT}/${CLIENT}/g; s/{DB_HOST}/${DB_HOST}/g; s/{DB_USER}/${DB_USER}/g; s/{DB_PASSWORD}/${DB_PASSWORD}/g" odoo.conf.template > ${CLIENT}/config/odoo.conf

# 设置目录权限
chmod -R 777 ${CLIENT}
chmod -R 777 custom-addons-${CLIENT}

# 检查服务是否已存在
if ! grep -q "# Client${CLIENT_NUM} 服務" docker-compose.yml; then
    # 在 networks 部分之前插入新的服务定义
    sed -i "/^networks:/i\  # Client${CLIENT_NUM} 服務\n  web${CLIENT_NUM}:\n    build: .\n    image: custom-odoo:16.0\n    depends_on:\n      - db${CLIENT_NUM}\n    volumes:\n      - ./${CLIENT}/config:/etc/odoo\n      - ./${CLIENT}/data:/var/lib/odoo\n      - ./${CLIENT}/logs:/var/log/odoo\n      - ./addons:/mnt/addons\n      - ./custom-addons:/mnt/custom-addons\n      - ./custom-addons-${CLIENT}:/mnt/custom-addons-${CLIENT}\n    ports:\n      - \"${WEB_PORT}:8069\"\n      - \"${LONGPOLLING_PORT}:8072\"\n    environment:\n      - LANG=zh_TW.UTF-8\n      - TZ=Asia/Taipei\n    networks:\n      - odoo_net\n    restart: unless-stopped\n\n  db${CLIENT_NUM}:\n    image: postgres:15\n    environment:\n      - POSTGRES_DB=postgres\n      - POSTGRES_PASSWORD=${DB_PASSWORD}\n      - POSTGRES_USER=${DB_USER}\n      - PGDATA=/var/lib/postgresql/data/pgdata\n    volumes:\n      - ./${CLIENT}/postgresql:/var/lib/postgresql/data\n    ports:\n      - \"${DB_PORT}:5432\"\n    networks:\n      - odoo_net\n    restart: unless-stopped\n\n" docker-compose.yml
fi

# 添加初始化命令到 docker-compose.yml
sed -i "/web${CLIENT_NUM}:/,/restart:/ s/    environment:/    command: -- --init=base\n    environment:/g" docker-compose.yml

echo "Client ${CLIENT} has been created successfully!"
echo "Starting services with database initialization..."

# 启动新的服务
docker-compose up -d db${CLIENT_NUM}

echo "Waiting for database to start..."

# 等待数据库就绪
max_attempts=30
attempt=1
while ! docker-compose exec -T db${CLIENT_NUM} pg_isready -h localhost -U ${DB_USER} > /dev/null 2>&1; do
    if [ $attempt -gt $max_attempts ]; then
        echo "Error: Database failed to start after $max_attempts attempts"
        # 删除初始化命令
        sed -i "/^[[:space:]]*command: -- --init=base$/d" docker-compose.yml
        exit 1
    fi
    echo "Waiting for database... attempt $attempt/$max_attempts"
    sleep 2
    ((attempt++))
done

echo "Database is ready"

# 启动 web 服务
docker-compose up -d web${CLIENT_NUM}

# 等待数据库初始化完成
echo "Waiting for database initialization..."
max_attempts=60
attempt=1
while ! docker-compose exec -T db${CLIENT_NUM} psql -U ${DB_USER} -d postgres -c "SELECT 1 FROM ir_module_module LIMIT 1" > /dev/null 2>&1; do
    if [ $attempt -gt $max_attempts ]; then
        echo "Error: Database initialization failed after $max_attempts attempts"
        # 删除初始化命令
        sed -i "/^[[:space:]]*command: -- --init=base$/d" docker-compose.yml
        exit 1
    fi
    echo "Waiting for initialization... attempt $attempt/$max_attempts"
    sleep 2
    ((attempt++))
done

echo "Database initialization completed"

# 停止服务
echo "Stopping services..."
docker-compose stop web${CLIENT_NUM}

# 删除初始化命令
echo "Updating configuration..."
sed -i "/^[[:space:]]*command: -- --init=base$/d" docker-compose.yml

# 重新启动服务
echo "Starting services..."
docker-compose up -d web${CLIENT_NUM}

echo "Client ${CLIENT} initialization completed successfully!" 