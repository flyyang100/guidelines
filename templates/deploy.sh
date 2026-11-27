#!/bin/bash
# 公司级部署脚本模板(来自 guidelines/templates/deploy.sh)
# 使用方法:复制到项目根目录,只改「Configuration」一节,其余尽量不动。
# 用法: ./deploy.sh [qa|product] [commit_id]
#   ./deploy.sh qa            # 部署 HEAD 到 QA
#   ./deploy.sh qa 75c34a0    # 部署指定 commit/branch/tag 到 QA
#
# 流程: git archive 归档 → scp 上传 → 解压到 /opt/<应用> → 重启 systemd
#       → /ping 探活 → 检查日志新增 ERROR → 服务器端记录部署日志
#
# 注意:
# - config.toml 不入库,git archive 不会带上它。新机器首次部署需手工放置 config.toml。
# - 对 agent:部署 product 属于「必须人工确认」操作,
#   不要在无人确认的情况下执行 ./deploy.sh product。
#
# 回滚:
# - 每次部署会在服务器 /opt/<应用>/logs/deploy.log 中写入一条记录，格式为:
#     [2024-01-01 12:00:00] Deployer: xxx | Commit Author: xxx | Version: 75c34a0 (commit message)
# - 需要回滚时，SSH 到服务器查看该文件找到上一个正常版本的 Version（短 commit SHA）:
#     ssh root@<qa|legacy>.example.com "tail -20 /opt/<应用>/logs/deploy.log"
# - 然后在本地执行部署脚本指定该 commit 即可回滚:
#     ./deploy.sh qa <旧commit>
#   本质上就是一次普通部署，只是把代码退回到旧版本。

set -e

# ===== Configuration(每个项目只改这一节)=====
PROJECT_NAME="myapp"            # 应用名 = /opt 目录名 = systemd service 名(见 server.md)
PING_PATH="/$PROJECT_NAME/ping" # 探活路径,返回体应为应用名(见 app.md 健康检查约定)
BACKEND_DIR=""                  # monorepo 项目:设为 "backend"(只归档后端子树); 旧布局:留空(归档整个仓库)
# =============================================

PROJECT_FILE_NAME="$PROJECT_NAME.tar.gz"

# Servers(域名约定见 server.md)
# ssh 主机与探活域名分开:三个域名(example.com/app/api)指向同一台 product 服务器,
# 但健康检查接口只在 api.* 域名下可访问。
QA_SSH_HOST="qa.example.com"
QA_API_HOST="api.qa.example.com"
PRODUCT_SSH_HOST="app.example.com"
PRODUCT_API_HOST="api.example.com"

# Remote
REMOTE_USER="root"              # ssh 用 root(需要重启服务),应用文件归 app 用户
APP_USER="app"                  # 应用运行用户(见 server.md)
REMOTE_DIR="/opt/$PROJECT_NAME"
SERVICE_NAME="$PROJECT_NAME"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
ENV="$1"
COMMIT_ID="${2:-HEAD}"

if [ "$ENV" != "qa" ] && [ "$ENV" != "product" ]; then
    echo "Usage: $0 [qa|product] [commit_id]"
    exit 1
fi

# Verify commit ID
if ! git rev-parse --verify "$COMMIT_ID" >/dev/null 2>&1; then
    echo -e "${RED}Error: Invalid commit ID, branch, or tag: '$COMMIT_ID'${NC}"
    exit 1
fi

# Resolve commit information
DEPLOY_TIME=$(date "+%Y-%m-%d %H:%M:%S")
GIT_COMMIT_USER=$(git log -1 --format="%an" $COMMIT_ID 2>/dev/null || echo "Unknown")
GIT_CONFIG_USER=$(git config user.name 2>/dev/null || whoami 2>/dev/null || echo "Unknown")
COMMIT_SHA=$(git rev-parse --short $COMMIT_ID 2>/dev/null || echo "Unknown")
COMMIT_MSG=$(git log -1 --format="%s" $COMMIT_ID 2>/dev/null || echo "Unknown")

LOG_RECORD="[$DEPLOY_TIME] Deployer: $GIT_CONFIG_USER | Commit Author: $GIT_COMMIT_USER | Version: $COMMIT_SHA ($COMMIT_MSG)"

# Select Environment
if [ "$ENV" == "qa" ]; then
    SSH_HOST="$QA_SSH_HOST"
    API_HOST="$QA_API_HOST"
    ENV_NAME="QA"
    echo -e "${GREEN}Deploying to QA environment ($SSH_HOST)...${NC}"
else
    SSH_HOST="$PRODUCT_SSH_HOST"
    API_HOST="$PRODUCT_API_HOST"
    ENV_NAME="PRODUCT"
    echo -e "${RED}Deploying to PRODUCTION environment ($SSH_HOST)...${NC}"
    read -p "Are you sure? [Y/n] " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# 1. Archive
echo "1. Archiving project (commit: $COMMIT_SHA)..."
if [ -n "$BACKEND_DIR" ]; then
    ARCHIVE_REF="$COMMIT_ID:$BACKEND_DIR"
else
    ARCHIVE_REF="$COMMIT_ID"
fi
git archive --format=tar.gz --output=$PROJECT_FILE_NAME $ARCHIVE_REF

# 2. Upload
echo "2. Uploading to $ENV_NAME server..."
scp $PROJECT_FILE_NAME $REMOTE_USER@$SSH_HOST:/tmp/

# 3. Deploy on server
echo "3. Executing remote commands..."
ssh -T $REMOTE_USER@$SSH_HOST << EOF
    mkdir -p $REMOTE_DIR
    echo "Extracting tar.gz..."
    tar -zxf /tmp/$PROJECT_FILE_NAME -C $REMOTE_DIR
    rm /tmp/$PROJECT_FILE_NAME

    # 应用文件归 app 用户(server.md:应用以 app 用户启动,注意权限)
    chown -R $APP_USER:$APP_USER $REMOTE_DIR

    echo "Restarting service..."
    systemctl restart $SERVICE_NAME
    echo "Remote file distribution and restart complete."
EOF

# 4. Verify: ping
echo "4. Verifying deployment..."
MAX_RETRIES=3
SLEEP_TIME=2
SUCCESS="false"

echo "Checking https://$API_HOST$PING_PATH ..."
for ((i=1; i<=MAX_RETRIES; i++)); do
    RESPONSE=$(curl -s -k --max-time 5 "https://$API_HOST$PING_PATH")
    if [ "$RESPONSE" == "$PROJECT_NAME" ]; then
        echo -e "${GREEN}Application started successfully!${NC}"
        SUCCESS="true"
        break
    fi
    echo -ne "Waiting for application to start... ($i/$MAX_RETRIES)\r"
    sleep $SLEEP_TIME
done
echo ""

if [ "$SUCCESS" == "false" ]; then
    echo -e "${RED}Error: Application failed to start or is not reachable.${NC}"
    echo -e "${RED}Last response: $RESPONSE${NC}"
    exit 1
fi

# 5. Verify: new ERRORs in app log since deploy (冒烟检查要求)
echo "5. Checking app log for new ERRORs since deploy..."
NEW_ERRORS=$(ssh -T $REMOTE_USER@$SSH_HOST \
    "awk -v t=\"$DEPLOY_TIME\" '\$0 >= t' $REMOTE_DIR/logs/app.log 2>/dev/null | grep -c ' ERROR ' || true")
if [ "$NEW_ERRORS" != "0" ] && [ -n "$NEW_ERRORS" ]; then
    echo -e "${RED}Warning: $NEW_ERRORS new ERROR line(s) in app.log since deploy. Check $REMOTE_DIR/logs/app.log${NC}"
    # 不直接失败:服务已探活成功,ERROR 交由部署者判断(agent 须将此结果记入 PROGRESS 并报告)
else
    echo -e "${GREEN}No new ERRORs in app.log.${NC}"
fi

# 6. Log deployment on server
echo "6. Logging deployment..."
ssh -T $REMOTE_USER@$SSH_HOST << EOF
    mkdir -p $REMOTE_DIR/logs
    echo "$LOG_RECORD" >> $REMOTE_DIR/logs/deploy.log
EOF

# Cleanup local
rm $PROJECT_FILE_NAME
echo -e "${GREEN}Deploy finished.${NC}"
