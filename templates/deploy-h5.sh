#!/bin/bash
# 公司级 H5 部署脚本模板(来自 guidelines/templates/deploy-h5.sh)
# 使用方法:复制到 frontend 目录,只改「Configuration」一节,其余尽量不动。
# 用法: ./deploy.sh [qa|product]
#   ./deploy.sh qa            # 部署到 QA
#   ./deploy.sh product       # 部署到生产环境(需人工确认)
#
# 流程: 本地构建 → 打包 dist → scp 上传 → rsync 到 /opt/h5/<app_name> → 清理
#
# 注意:
# - 按 server.md H5 规范:部署路径为 /opt/h5/<app_name>
# - 访问地址: qa 环境 https://h5.qa.example.com/<app_name>, product 环境 https://h5.example.com/<app_name>
# - 部署 product 属于「必须人工确认」操作

set -e

# ===== Configuration(每个项目只改这一节)=====
PROJECT_NAME="myapp"             # 项目名(用于日志)
APP_NAME="myapp-h5"              # 应用名 = /opt/h5/ 目录名(见 server.md H5 规范)
UI_DIR="."                     # 前端代码目录(相对于 deploy.sh 位置)
BUILD_CMD="npm run build:prod" # 构建命令
# =============================================

PACKAGE_NAME="$APP_NAME.tar.gz"

# Servers(域名约定见 server.md)
QA_SSH_HOST="qa.example.com"
PRODUCT_SSH_HOST="edge.example.com"

# Remote
REMOTE_USER="root"
DEPLOY_PATH="/opt/h5/$APP_NAME"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
ENV="$1"

if [ "$ENV" != "qa" ] && [ "$ENV" != "product" ]; then
    echo "Usage: $0 [qa|product]"
    exit 1
fi

# Resolve commit information
DEPLOY_TIME=$(date "+%Y-%m-%d %H:%M:%S")
COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "Unknown")
COMMIT_MSG=$(git log -1 --format="%s" HEAD 2>/dev/null || echo "Unknown")
GIT_CONFIG_USER=$(git config user.name 2>/dev/null || whoami 2>/dev/null || echo "Unknown")

LOG_RECORD="[$DEPLOY_TIME] Deployer: $GIT_CONFIG_USER | Version: $COMMIT_SHA ($COMMIT_MSG)"

# Select Environment
if [ "$ENV" == "qa" ]; then
    SSH_HOST="$QA_SSH_HOST"
    ENV_NAME="QA"
    echo -e "${GREEN}Deploying H5 to QA environment ($SSH_HOST)...${NC}"
else
    SSH_HOST="$PRODUCT_SSH_HOST"
    ENV_NAME="PRODUCT"
    echo -e "${RED}Deploying H5 to PRODUCTION environment ($SSH_HOST)...${NC}"
    read -p "Are you sure? [Y/n] " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# 1. Build locally
echo "1. Building H5 project..."
cd "$UI_DIR" || exit
$BUILD_CMD
cd - >/dev/null || exit

# 2. Package
echo "2. Packaging dist..."
COPYFILE_DISABLE=1 tar -czf "$PACKAGE_NAME" "$UI_DIR/dist"

# 3. Upload
echo "3. Uploading to $ENV_NAME server..."
scp "$PACKAGE_NAME" "$REMOTE_USER@$SSH_HOST":~/

# 4. Deploy on server
echo "4. Deploying to $DEPLOY_PATH..."
ssh -T "$REMOTE_USER@$SSH_HOST" << EOF
    mkdir -p $DEPLOY_PATH
    echo "Extracting tar.gz..."
    tar -zxf ~/$PACKAGE_NAME -C ~/ --warning=no-unknown-keyword
    rm ~/$PACKAGE_NAME

    echo "Syncing dist to $DEPLOY_PATH..."
    rsync -a --delete ~/$UI_DIR/dist/ $DEPLOY_PATH/

    echo "Cleaning up..."
    rm -rf ~/$UI_DIR

    mkdir -p /var/log/$PROJECT_NAME
    echo "$LOG_RECORD" >> /var/log/$PROJECT_NAME/deploy.log
    echo "H5 deployed successfully."
EOF

# 5. Cleanup local
rm "$PACKAGE_NAME"
echo -e "${GREEN}H5 deploy finished.${NC}"
if [ "$ENV" == "qa" ]; then
    echo -e "${GREEN}Access URL: https://h5.qa.example.com/$APP_NAME${NC}"
else
    echo -e "${GREEN}Access URL: https://h5.example.com/$APP_NAME${NC}"
fi