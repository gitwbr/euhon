# Odoo 16.0 多客戶端開發環境

# Odoo 16.0 多客戶端開發環境

這個項目提供了一個基於 Docker 的 Odoo 16.0 多客戶端開發環境，支持同時運行多個獨立的 Odoo 實例。

## 環境配置

### 系統要求
- Docker
- Docker Compose
- Git

### 自定義功能
系統使用自定義的 Dockerfile 構建鏡像，包含以下增強功能：
- wkhtmltopdf 支持
- 中文語言環境支持
- Python 額外依賴：
  - python-barcode
  - Pillow
  - pdfkit

### 安裝步驟

1. 克隆項目：
```bash
cd /home/bryant
#git clone [repository_url] odoo16
cd odoo16
```

2. 創建必要的目錄結構：
```bash
# 創建共享目錄
mkdir -p addons custom-addons

# 創建客戶端特定目錄
for i in {1..3}; do
    mkdir -p custom-addons-client$i
    mkdir -p client$i/config client$i/logs
done
```

3. 設置目錄權限：
```bash
# 設置目錄權限
chmod -R 777 client*/logs addons custom-addons custom-addons-client*
```

4. 創建配置文件：
```bash
# 為每個客戶端創建配置文件
for i in {1..3}; do
    cat > client$i/config/odoo.conf << EOF
[options]
addons_path = /mnt/addons,/mnt/custom-addons,/mnt/custom-addons-client$i
http_port = $((8068 + i))
longpolling_port = $((9068 + i))
db_host = db$i
db_port = $((5431 + i))
db_user = odoo$i
db_password = odoo$i
admin_passwd = admin
EOF
done
```

5. 啟動服務：
```bash
# 啟動所有服務
docker-compose up -d
```

6. 驗證安裝：
```bash
# 檢查服務狀態
docker-compose ps

# 檢查日誌
docker-compose logs
```

7. 訪問 Odoo：
   - Client1: http://localhost:8069
   - Client2: http://localhost:8070
   - Client3: http://localhost:8071

### 目錄結構
```
odoo16/
├── docker-compose.yml
├── Dockerfile                # 自定義 Odoo 鏡像配置
├── addons/                   # 共享的 Odoo 模組
├── custom-addons/            # 共享的自定義模組
├── custom-addons-client1/    # Client1 專用的自定義模組
├── custom-addons-client2/    # Client2 專用的自定義模組
├── custom-addons-client3/    # Client3 專用的自定義模組
└── client1/
    ├── config/              # Client1 配置文件
    └── logs/               # Client1 日誌文件
└── client2/
    ├── config/              # Client2 配置文件
    └── logs/               # Client2 日誌文件
└── client3/
    ├── config/              # Client3 配置文件
    └── logs/               # Client3 日誌文件
```

## 服務配置

### 端口配置
- Client1: 
  - Web: 8069
  - Longpolling: 9069
  - Database: 5432
- Client2:
  - Web: 8070
  - Longpolling: 9070
  - Database: 5433
- Client3:
  - Web: 8071
  - Longpolling: 9071
  - Database: 5434

## 使用說明

### 命令執行位置
所有 docker-compose 命令都必須在 `docker-compose.yml` 文件所在的目錄執行：
```bash
# 首先切換到正確的目錄
cd /home/bryant/odoo16  # 或你的項目實際路徑

# 然後執行 docker-compose 命令
docker-compose ps        # 查看服務狀態
docker-compose up -d     # 啟動服務
docker-compose down      # 停止服務
```

### 停止服務
```bash
# 停止所有服務
docker-compose down

# 停止單個服務
docker-compose stop web1  # 停止 Client1
docker-compose stop web2  # 停止 Client2
docker-compose stop web3  # 停止 Client3
docker-compose stop db1   # 停止 Client1 的數據庫
docker-compose stop db2   # 停止 Client2 的數據庫
docker-compose stop db3   # 停止 Client3 的數據庫
```

### 重啟服務
```bash
# 重啟所有服務
docker-compose restart

# 重啟單個服務
docker-compose restart web1  # 重啟 Client1
docker-compose restart web2  # 重啟 Client2
docker-compose restart web3  # 重啟 Client3
docker-compose restart db1   # 重啟 Client1 的數據庫
docker-compose restart db2   # 重啟 Client2 的數據庫
docker-compose restart db3   # 重啟 Client3 的數據庫

# 啟動單個已停止的服務
docker-compose start web1    # 啟動 Client1
docker-compose start web2    # 啟動 Client2
docker-compose start web3    # 啟動 Client3
```

### 查看日誌
```bash
# 查看所有服務日誌
docker-compose logs

# 查看特定服務日誌
docker-compose logs web1  # Client1
docker-compose logs web2  # Client2
docker-compose logs web3  # Client3

# 查看最近的日誌（顯示最後 50 行）
docker-compose logs --tail=50 web1

# 實時查看日誌
docker-compose logs -f web1

# 查看特定時間段的日誌
docker-compose logs --since 2024-01-20T00:00:00 web1

# 查看數據庫日誌
docker-compose logs db1   # Client1 數據庫
docker-compose logs db2   # Client2 數據庫
docker-compose logs db3   # Client3 數據庫
```

### 查看服務狀態
```bash
# 查看所有容器狀態
docker-compose ps

# 查看容器詳細信息
docker-compose ps web1
docker inspect odoo16_web1_1

# 查看容器資源使用情況
docker stats odoo16_web1_1 odoo16_db1_1

# 查看容器網絡配置
docker network inspect odoo_net

# 查看容器掛載的卷
docker volume ls
```

### 服務管理命令
```bash
# 啟動新的客戶端（使用腳本）
./create_client.sh 4  # 創建 client4

# 刪除特定客戶端
docker-compose rm -sf web4 db4  # 刪除容器
rm -rf client4/                 # 刪除目錄

# 重建並重啟特定服務
docker-compose up -d --force-recreate web1

# 進入容器內部（調試用）
docker-compose exec web1 bash
docker-compose exec db1 bash

# 查看容器日誌文件
ls -l client1/logs/

# 清理未使用的 Docker 資源
docker system prune -a  # 清理所有未使用的容器、鏡像和網絡
```
# 重建並重啟特定服務（使用自定義鏡像）
docker-compose build web1       # 重新構建鏡像
docker-compose up -d --force-recreate web1  # 使用新鏡像重啟服務

### 數據庫備份和恢復
```bash
# 備份數據庫
docker-compose exec db1 pg_dump -U odoo1 postgres > backup.sql

# 恢復數據庫
docker-compose exec -T db1 psql -U odoo1 postgres < backup.sql

# 查看數據庫大小
docker-compose exec db1 psql -U odoo1 -c "SELECT pg_size_pretty(pg_database_size('postgres'));"
```

### 數據庫管理
- Client1: http://localhost:8069/web/database/manager
- Client2: http://localhost:8070/web/database/manager
- Client3: http://localhost:8071/web/database/manager

## 開發指南

### 添加新模組
1. 共享模組：放置在 `custom-addons/` 目錄
2. 客戶端特定模組：放置在對應的 `custom-addons-client{N}/` 目錄

### 服務重啟說明
不同類型的修改需要不同的重啟方式：

1. Python 文件修改（模型、控制器等）：
   - 需要重啟 Odoo 服務（web 容器）
   ```bash
   docker-compose restart web1  # 重啟 Client1 的 Odoo 服務
   ```

2. XML 文件修改（視圖、數據等）：
   - 只需要更新模組，無需重啟服務
   - 在 Odoo 界面中：應用程序 > 更新模組列表 > 升級指定模組

3. JavaScript/CSS 文件修改：
   - 清除瀏覽器緩存即可
   - 或按住 Ctrl + F5 強制刷新
   - 無需重啟服務

4. 配置文件修改（odoo.conf）：
   - 需要重啟 Odoo 服務
   ```bash
   docker-compose restart web1  # 重啟 Client1 的 Odoo 服務
   ```

5. 數據庫服務重啟情況：
   - PostgreSQL 配置修改（postgresql.conf, pg_hba.conf）
   - 數據庫性能調優（如修改共享內存、連接數等）
   - 數據庫版本升級
   - 數據庫出現異常或死鎖時
   ```bash
   docker-compose restart db1  # 重啟 Client1 的數據庫
   ```
   注意：重啟數據庫會導致所有當前連接中斷，應在系統維護時間進行

### 常見問題處理
1. 數據庫連接問題：
   - 檢查數據庫服務是否正常運行
   ```bash
   docker-compose ps db1
   ```
   - 查看數據庫日誌
   ```bash
   docker-compose logs db1
   ```

2. 數據庫性能問題：
   - 檢查數據庫連接數
   - 檢查慢查詢日誌
   - 考慮調整 PostgreSQL 配置參數

### 為什麼 Web 和 DB 要分開？
1. 獨立擴展：
   - Web 服務和數據庫可以根據需求獨立擴展
   - 可以根據負載情況單獨調整資源分配

2. 維護便利：
   - 可以單獨重啟 Web 服務而不影響數據庫
   - 數據庫維護時不必停止所有服務

3. 安全性：
   - 數據庫和應用服務隔離
   - 可以對數據庫施加更嚴格的訪問控制

4. 靈活性：
   - 方便進行數據庫備份和恢復
   - 可以輕鬆遷移或更換任一組件

### 配置文件
每個客戶端的配置文件位於 `client{N}/config/odoo.conf`

### 模組路徑
- 標準模組：`/mnt/addons`
- 共享自定義模組：`/mnt/custom-addons`
- 客戶端特定模組：`/mnt/custom-addons-client{N}`

## 注意事項
1. 確保所有目錄具有適當的權限
2. 修改配置文件後需要重啟對應的服務
3. 數據庫備份建議定期執行
4. 開發時注意不同客戶端之間的隔離 