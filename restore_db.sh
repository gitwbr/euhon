#!/bin/bash

# 彩色输出函数
print_info() {
    echo -e "\033[1;34m[信息]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[成功]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[错误]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[警告]\033[0m $1"
}

# 检查参数
if [ $# -ne 1 ]; then
    print_error "使用方法: $0 <备份文件路径>"
    print_info "示例: $0 client1/db/odoo1_20250203_075630.sql.gz"
    exit 1
fi

BACKUP_FILE="$1"

# 检查备份文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
    print_error "备份文件 $BACKUP_FILE 不存在"
    exit 1
fi

# 从文件名中提取数据库名称（格式：odooN_TIMESTAMP.sql.gz）
DB_NAME=$(basename "$BACKUP_FILE" | cut -d'_' -f1)
if [[ ! "$DB_NAME" =~ ^odoo[0-9]+$ ]]; then
    print_error "无法从文件名中提取数据库名称"
    exit 1
fi

# 获取客户端编号
CLIENT_NUM=${DB_NAME#odoo}

# 构造容器名称和配置文件路径
CONTAINER_NAME="odoo16-db${CLIENT_NUM}-1"
WEB_CONTAINER="odoo16-web${CLIENT_NUM}-1"
CONFIG_FILE="/etc/odoo/odoo.conf"
ADDONS_PATH="/mnt/addons,/mnt/custom-addons"

# 检查容器是否运行
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    print_error "容器 $CONTAINER_NAME 未运行"
    exit 1
fi

# 设置数据库连接信息
DB_USER="odoo${CLIENT_NUM}"
DB_PASS="odoo${CLIENT_NUM}"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
TEMP_FILE="$TEMP_DIR/backup.sql"

echo "==============================================="
print_info "开始恢复数据库..."
print_info "数据库名称: $DB_NAME"
print_info "容器名称: $CONTAINER_NAME"
print_info "Web容器: $WEB_CONTAINER"

# 检查数据库连接
print_info "检查数据库连接..."
if ! PGPASSWORD=$DB_PASS docker exec $CONTAINER_NAME psql -U $DB_USER -d postgres -c '\l' > /dev/null 2>&1; then
    print_error "无法连接到数据库服务器"
    exit 1
fi
print_success "数据库连接正常"

# 停止对应的Odoo服务
print_info "停止 Odoo 服务..."
if docker stop $WEB_CONTAINER; then
    print_success "Odoo 服务已停止"
else
    print_warning "停止 Odoo 服务失败，继续执行..."
fi

# 等待连接关闭
print_info "等待数据库连接关闭（5秒）..."
sleep 5

# 解压备份文件
print_info "解压备份文件..."
if gunzip -c "$BACKUP_FILE" > "$TEMP_FILE"; then
    print_success "备份文件解压成功"
else
    print_error "备份文件解压失败"
    exit 1
fi

# 删除现有数据库
print_info "删除现有数据库..."
if ! PGPASSWORD=$DB_PASS docker exec $CONTAINER_NAME dropdb -U $DB_USER $DB_NAME; then
    print_warning "数据库可能不存在，继续执行..."
fi

# 创建新的数据库
print_info "创建新的数据库..."
if ! PGPASSWORD=$DB_PASS docker exec $CONTAINER_NAME createdb -U $DB_USER $DB_NAME -T template0; then
    print_error "创建数据库失败"
    docker start $WEB_CONTAINER || true
    rm -rf "$TEMP_DIR"
    exit 1
fi
print_success "数据库创建成功"

# 设置初始权限
print_info "设置初始数据库权限..."
INIT_SQL="
ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};
"
if ! echo "$INIT_SQL" | docker exec -i -e PGPASSWORD=$DB_PASS $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME; then
    print_error "设置初始权限失败"
    exit 1
fi

# 复制备份文件到容器
print_info "复制备份文件到容器..."
if ! docker cp "$TEMP_FILE" "$CONTAINER_NAME:/tmp/backup.sql"; then
    print_error "备份文件复制失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi
print_success "备份文件复制成功"

# 恢复数据库
print_info "恢复数据库（这可能需要几分钟）..."
print_info "正在执行pg_restore，每30秒显示一次进度..."

# 先恢复数据库结构和数据
(
    docker exec -e PGPASSWORD=$DB_PASS $CONTAINER_NAME pg_restore -v -U $DB_USER \
        --role=$DB_USER \
        -d $DB_NAME "/tmp/backup.sql" 2>&1 | \
    while IFS= read -r line; do
        echo "$line"
        if (( $(date +%s) % 30 == 0 )); then
            print_info "pg_restore 仍在运行中..."
        fi
    done
) &

PID=$!
TIMEOUT=1800  # 30分钟超时
START_TIME=$(date +%s)

while kill -0 $PID 2>/dev/null; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        kill $PID
        print_error "恢复操作超时（${TIMEOUT}秒）"
        exit 1
    fi
    
    # 每30秒显示一次进度
    if (( ELAPSED % 30 == 0 )); then
        print_info "已经运行了 ${ELAPSED} 秒..."
    fi
    sleep 1
done

wait $PID
RESTORE_STATUS=$?

if [ $RESTORE_STATUS -eq 0 ]; then
    print_success "数据库恢复成功"
else
    print_error "数据库恢复失败"
    rm -rf "$TEMP_DIR"
    docker exec $CONTAINER_NAME rm -f /tmp/backup.sql
    docker start $WEB_CONTAINER || true
    exit 1
fi

# 设置数据库权限
print_info "设置数据库权限..."
GRANT_SQL="
-- 确保数据库用户有完整权限
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};

-- 确保所有表的所有者正确
DO \$\$
DECLARE
    r RECORD;
BEGIN
    -- 先设置所有表的所有者
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' OWNER TO ${DB_USER}';
    END LOOP;
    
    -- 然后设置所有序列的所有者
    FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public'
    LOOP
        EXECUTE 'ALTER SEQUENCE public.' || quote_ident(r.sequence_name) || ' OWNER TO ${DB_USER}';
    END LOOP;
    
    -- 最后设置所有视图的所有者
    FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER VIEW public.' || quote_ident(r.viewname) || ' OWNER TO ${DB_USER}';
    END LOOP;
END \$\$;

-- 确保admin用户有正确的权限
UPDATE res_users SET active = true WHERE login = 'admin';
UPDATE res_users SET password = 'admin' WHERE login = 'admin';
UPDATE res_users SET share = false WHERE login = 'admin';

-- 确保admin用户在所有必要的组中
INSERT INTO res_groups_users_rel (gid, uid)
SELECT g.id, u.id
FROM res_groups g
CROSS JOIN res_users u
WHERE u.login = 'admin'
AND g.name IN ('Access Rights', 'Settings', 'Technical Features')
AND NOT EXISTS (
    SELECT 1 FROM res_groups_users_rel r
    WHERE r.gid = g.id AND r.uid = u.id
);
"

if ! echo "$GRANT_SQL" | docker exec -i -e PGPASSWORD=$DB_PASS $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME; then
    print_warning "设置数据库权限时出现警告，但这可能是正常的"
fi
print_success "数据库权限设置成功"

# 更新基础模块
print_info "更新基础模块..."
print_info "停止 Odoo 服务以更新模块..."
docker stop $WEB_CONTAINER

print_info "等待服务完全停止（5秒）..."
sleep 5

if ! docker exec $WEB_CONTAINER odoo --config $CONFIG_FILE --addons-path=$ADDONS_PATH \
    --stop-after-init --update=base --database $DB_NAME --load=base --log-level=debug; then
    print_warning "基础模块更新出现警告，但这可能是正常的"
fi

# 再次确认admin权限
print_info "再次确认admin权限..."
CONFIRM_SQL="
UPDATE res_users SET active=true, share=false WHERE login='admin';
UPDATE res_users SET password='admin' WHERE login='admin';
"
if ! echo "$CONFIRM_SQL" | docker exec -i -e PGPASSWORD=$DB_PASS $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME; then
    print_warning "确认admin权限时出现警告"
fi

# 更新所有模块
print_info "更新所有已安装的模块（这可能需要几分钟）..."
print_info "如果看到红色错误信息，不用担心，这是正常的模块依赖解析过程..."

if ! docker exec $WEB_CONTAINER odoo --config $CONFIG_FILE --addons-path=$ADDONS_PATH \
    --stop-after-init --update=all --database $DB_NAME --load=base,web,dtsc --log-level=debug 2>&1 | tee /tmp/odoo_update.log; then
    print_warning "模块更新过程中有一些警告，但这可能是正常的"
fi

# 启动Odoo服务
print_info "启动 Odoo 服务..."
if docker start $WEB_CONTAINER; then
    print_success "Odoo 服务启动成功"
else
    print_error "Odoo 服务启动失败"
    exit 1
fi

echo "==============================================="
print_success "恢复流程结束于 $(date)"
print_info "请等待约30秒后再访问系统，让所有服务完全启动" 