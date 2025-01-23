#!/bin/bash

# 获取当前目录
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查文件是否存在
if [ ! -f "$DIR/docker-compose.yml" ] || [ ! -f "$DIR/Dockerfile" ] || [ ! -f "$DIR/create_client.sh" ]; then
    echo "Error: Required files not found"
    exit 1
fi

# 从 docker-compose.yml 提取环境变量和配置
echo "Syncing changes from docker-compose.yml to create_client.sh..."

# 提取第一个 web 服务的完整配置块
WEB_CONFIG=$(sed -n '/web1:/,/db1:/p' "$DIR/docker-compose.yml")

# 提取并处理环境变量
ENV_VARS=$(echo "$WEB_CONFIG" | awk '/environment:/,/networks:/' | grep '^[[:space:]]*-' | sort -u)

# 从 Dockerfile 提取 ENV 配置
echo "Syncing changes from Dockerfile..."
DOCKERFILE_ENVS=""
while IFS= read -r line; do
    if [[ $line =~ ^ENV[[:space:]]+(.*) ]]; then
        env_setting="${BASH_REMATCH[1]}"
        var_name="${env_setting%% *}"
        var_value="${env_setting#* }"
        DOCKERFILE_ENVS+="      - $var_name=$var_value\n"
    fi
done < "$DIR/Dockerfile"

# 合并所有环境变量
ALL_ENVS="$ENV_VARS\n$DOCKERFILE_ENVS"

# 更新 create_client.sh 中的服务定义
echo "Updating create_client.sh..."
SERVICE_BLOCK=$(cat << EOF
    # 在 networks 部分之前插入新的服务定义
    sed -i "/^networks:/i\\  # Client\${CLIENT_NUM} 服務\\n  web\${CLIENT_NUM}:\\n    build: .\\n    image: custom-odoo:16.0\\n    depends_on:\\n      - db\${CLIENT_NUM}\\n    volumes:\\n      - ./\${CLIENT}/config:/etc/odoo\\n      - ./\${CLIENT}/data:/var/lib/odoo\\n      - ./\${CLIENT}/logs:/var/log/odoo\\n      - ./addons:/mnt/addons\\n      - ./custom-addons:/mnt/custom-addons\\n      - ./custom-addons-\${CLIENT}:/mnt/custom-addons-\${CLIENT}\\n    ports:\\n      - \"\${WEB_PORT}:8069\"\\n      - \"\${LONGPOLLING_PORT}:8072\"\\n    environment:\\n      - LANG=zh_TW.UTF-8\\n      - TZ=Asia/Taipei\\n    networks:\\n      - odoo_net\\n    restart: unless-stopped\\n\\n  db\${CLIENT_NUM}:\\n    image: postgres:15\\n    environment:\\n      - POSTGRES_DB=postgres\\n      - POSTGRES_PASSWORD=\${DB_PASSWORD}\\n      - POSTGRES_USER=\${DB_USER}\\n      - PGDATA=/var/lib/postgresql/data/pgdata\\n    volumes:\\n      - ./\${CLIENT}/postgresql:/var/lib/postgresql/data\\n    ports:\\n      - \"\${DB_PORT}:5432\"\\n    networks:\\n      - odoo_net\\n    restart: unless-stopped\\n\\n" docker-compose.yml
EOF
)

# 更新 create_client.sh
sed -i "/# 在 networks 部分之前插入新的服务定义/,/docker-compose.yml/c\\$SERVICE_BLOCK" "$DIR/create_client.sh"

echo "Sync completed successfully"

# 更新 odoo.conf 文件
echo "Updating odoo.conf files..."
for i in $(seq 1 4); do
    mkdir -p client$i/config
    sed -e "s/{CLIENT}/$i/g" \
        -e "s/{DB_HOST}/db$i/g" \
        -e "s/{DB_USER}/odoo$i/g" \
        -e "s/{DB_PASSWORD}/odoo$i/g" \
        -e "s/{LONGPOLLING_PORT}/$(expr 9068 + $i)/g" \
        odoo.conf.template > client$i/config/odoo.conf
done

echo "All changes applied successfully" 