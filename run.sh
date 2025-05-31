#!/bin/bash

# Halo 开发服务器启动脚本
# 此脚本将启动 Halo 后端服务器和主题开发环境

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Java 环境
check_java() {
    log_info "检查 Java 环境..."
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -n1 | awk -F '"' '{print $2}')
        log_success "找到 Java 版本: $JAVA_VERSION"
        
        # 检查是否是 Java 11 或更高版本
        JAVA_MAJOR_VERSION=$(echo $JAVA_VERSION | cut -d'.' -f1)
        if [ "$JAVA_MAJOR_VERSION" -ge 11 ]; then
            log_success "Java 版本满足要求 (需要 Java 11+)"
        else
            log_error "Java 版本不满足要求，需要 Java 11 或更高版本"
            exit 1
        fi
    else
        log_error "未找到 Java，请先安装 Java 11 或更高版本"
        exit 1
    fi
}

# 检查 Node.js 和 pnpm
check_nodejs() {
    log_info "检查 Node.js 环境..."
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        log_success "找到 Node.js 版本: $NODE_VERSION"
    else
        log_warning "未找到 Node.js，主题开发功能可能无法使用"
        return 1
    fi
    
    if command -v pnpm &> /dev/null; then
        PNPM_VERSION=$(pnpm --version)
        log_success "找到 pnpm 版本: $PNPM_VERSION"
        return 0
    elif command -v npm &> /dev/null; then
        NPM_VERSION=$(npm --version)
        log_warning "未找到 pnpm，将使用 npm 版本: $NPM_VERSION"
        log_warning "建议安装 pnpm 以获得更好的性能: npm install -g pnpm"
        return 2
    else
        log_warning "未找到 npm 或 pnpm，主题开发功能无法使用"
        return 1
    fi
}

# 构建后端
build_backend() {
    log_info "构建 Halo 后端..."
    
    # 检查 Gradle Wrapper
    if [ ! -f "./gradlew" ]; then
        log_error "未找到 gradlew，请确保在 Halo 项目根目录中运行此脚本"
        exit 1
    fi
    
    # 清理并构建
    log_info "执行 Gradle 清理和构建..."
    ./gradlew clean build -x test
    
    if [ $? -eq 0 ]; then
        log_success "后端构建成功"
    else
        log_error "后端构建失败"
        exit 1
    fi
}

# 启动后端服务器
start_backend() {
    log_info "启动 Halo 后端服务器..."
    
    # 创建日志目录
    mkdir -p logs
    
    # 启动后端服务器
    log_info "正在启动后端服务器，日志输出到 logs/backend.log"
    nohup ./gradlew bootRun > logs/backend.log 2>&1 &
    BACKEND_PID=$!
    
    # 保存 PID
    echo $BACKEND_PID > logs/backend.pid
    log_success "后端服务器已启动，PID: $BACKEND_PID"
    
    # 等待服务器启动
    log_info "等待后端服务器启动..."
    for i in {1..30}; do
        if curl -s http://localhost:8090/actuator/health > /dev/null 2>&1; then
            log_success "后端服务器启动成功！访问地址: http://localhost:8090"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    
    log_error "后端服务器启动超时，请检查日志文件 logs/backend.log"
    return 1
}

# 设置主题开发环境
setup_theme_dev() {
    local theme_dir="themes/theme-halo-kuohao"
    
    if [ ! -d "$theme_dir" ]; then
        log_warning "未找到主题目录 $theme_dir"
        return 1
    fi
    
    log_info "设置主题开发环境..."
    cd "$theme_dir"
    
    # 检查 package.json
    if [ ! -f "package.json" ]; then
        log_warning "未找到 package.json，跳过主题开发环境设置"
        cd - > /dev/null
        return 1
    fi
    
    # 安装依赖
    log_info "安装主题依赖..."
    if command -v pnpm &> /dev/null; then
        pnpm install
    elif command -v npm &> /dev/null; then
        npm install
    else
        log_warning "未找到包管理器，跳过依赖安装"
        cd - > /dev/null
        return 1
    fi
    
    # 启动开发服务器
    log_info "启动主题开发服务器..."
    if command -v pnpm &> /dev/null; then
        nohup pnpm dev > ../../logs/theme-dev.log 2>&1 &
    else
        nohup npm run dev > ../../logs/theme-dev.log 2>&1 &
    fi
    
    THEME_PID=$!
    echo $THEME_PID > ../../logs/theme-dev.pid
    log_success "主题开发服务器已启动，PID: $THEME_PID"
    
    cd - > /dev/null
    return 0
}

# 显示服务状态
show_status() {
    echo ""
    log_success "============ 开发服务器状态 ============"
    
    # 检查后端状态
    if [ -f "logs/backend.pid" ]; then
        BACKEND_PID=$(cat logs/backend.pid)
        if ps -p $BACKEND_PID > /dev/null 2>&1; then
            log_success "✓ 后端服务器运行中 (PID: $BACKEND_PID)"
            log_info "  - 管理后台: http://localhost:8090/console"
            log_info "  - 博客首页: http://localhost:8090"
            log_info "  - API 文档: http://localhost:8090/swagger-ui.html"
        else
            log_error "✗ 后端服务器未运行"
        fi
    else
        log_error "✗ 后端服务器 PID 文件不存在"
    fi
    
    # 检查主题开发状态
    if [ -f "logs/theme-dev.pid" ]; then
        THEME_PID=$(cat logs/theme-dev.pid)
        if ps -p $THEME_PID > /dev/null 2>&1; then
            log_success "✓ 主题开发服务器运行中 (PID: $THEME_PID)"
        else
            log_warning "✗ 主题开发服务器未运行"
        fi
    else
        log_warning "✗ 主题开发服务器未启动"
    fi
    
    echo ""
    log_info "============ 使用说明 ============"
    log_info "• 查看后端日志: tail -f logs/backend.log"
    log_info "• 查看主题开发日志: tail -f logs/theme-dev.log"
    log_info "• 停止所有服务: ./stop_halo_dev.sh"
    echo ""
}

# 主函数
main() {
    log_info "开始启动 Halo 开发环境..."
    
    # 检查环境
    check_java
    check_nodejs
    
    # 构建和启动后端
    build_backend
    start_backend
    
    if [ $? -eq 0 ]; then
        # 设置主题开发环境
        setup_theme_dev
        
        # 显示状态
        show_status
        
        log_success "Halo 开发环境启动完成！"
        log_info "按 Ctrl+C 退出监控，服务器将继续在后台运行"
        
        # 监控服务状态
        while true; do
            sleep 10
            
            # 检查后端服务器
            if [ -f "logs/backend.pid" ]; then
                BACKEND_PID=$(cat logs/backend.pid)
                if ! ps -p $BACKEND_PID > /dev/null 2>&1; then
                    log_error "后端服务器意外停止！"
                    break
                fi
            fi
        done
        
    else
        log_error "后端服务器启动失败！"
        exit 1
    fi
}

# 捕获 Ctrl+C 信号
trap 'log_info "监控已停止，服务器继续在后台运行"; exit 0' INT

# 执行主函数
main "$@"
