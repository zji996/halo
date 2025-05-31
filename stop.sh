#!/bin/bash

# 停止 Halo 开发服务器脚本

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

# 停止进程函数
stop_process() {
    local pid_file=$1
    local service_name=$2
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p $pid > /dev/null 2>&1; then
            log_info "正在停止 $service_name (PID: $pid)..."
            kill $pid
            
            # 等待进程停止
            for i in {1..10}; do
                if ! ps -p $pid > /dev/null 2>&1; then
                    log_success "$service_name 已停止"
                    rm -f "$pid_file"
                    return 0
                fi
                sleep 1
            done
            
            # 强制杀死进程
            log_warning "正在强制停止 $service_name..."
            kill -9 $pid 2>/dev/null || true
            
            # 再次检查
            if ! ps -p $pid > /dev/null 2>&1; then
                log_success "$service_name 已强制停止"
                rm -f "$pid_file"
            else
                log_error "无法停止 $service_name"
                return 1
            fi
        else
            log_warning "$service_name 进程不存在，清理 PID 文件"
            rm -f "$pid_file"
        fi
    else
        log_warning "$service_name PID 文件不存在"
    fi
}

# 停止 Gradle 相关进程
stop_gradle_processes() {
    log_info "查找并停止 Gradle 相关进程..."
    
    # 查找 Gradle daemon 进程
    GRADLE_PIDS=$(pgrep -f "gradle" | head -10) || true
    
    if [ -n "$GRADLE_PIDS" ]; then
        for pid in $GRADLE_PIDS; do
            # 检查是否是我们项目的进程
            if ps -p $pid -o args= | grep -q "halo"; then
                log_info "发现 Halo Gradle 进程 (PID: $pid)，正在停止..."
                kill $pid 2>/dev/null || true
                sleep 1
                
                if ps -p $pid > /dev/null 2>&1; then
                    log_warning "强制停止 Gradle 进程 (PID: $pid)"
                    kill -9 $pid 2>/dev/null || true
                fi
            fi
        done
    fi
    
    # 停止 Gradle daemon
    if command -v ./gradlew &> /dev/null; then
        log_info "停止 Gradle Daemon..."
        ./gradlew --stop || true
    fi
}

# 停止端口占用的进程
stop_port_processes() {
    local port=$1
    local service_name=$2
    
    log_info "检查端口 $port 的占用情况..."
    
    # 查找占用端口的进程
    local pid=$(lsof -ti:$port 2>/dev/null) || true
    
    if [ -n "$pid" ]; then
        log_info "发现端口 $port 被进程 $pid 占用，正在停止..."
        kill $pid 2>/dev/null || true
        sleep 2
        
        # 检查是否还在运行
        if kill -0 $pid 2>/dev/null; then
            log_warning "强制停止占用端口 $port 的进程 (PID: $pid)"
            kill -9 $pid 2>/dev/null || true
        fi
        
        log_success "端口 $port 已释放"
    else
        log_info "端口 $port 未被占用"
    fi
}

# 清理日志函数
cleanup_logs() {
    if [ "$1" = "--clean-logs" ]; then
        log_info "清理日志文件..."
        rm -f logs/*.log
        log_success "日志文件已清理"
    fi
}

# 主函数
main() {
    log_info "开始停止 Halo 开发服务器..."
    
    # 创建日志目录（如果不存在）
    mkdir -p logs
    
    # 停止后端服务器
    stop_process "logs/backend.pid" "Halo 后端服务器"
    
    # 停止主题开发服务器
    stop_process "logs/theme-dev.pid" "主题开发服务器"
    
    # 停止 Gradle 相关进程
    stop_gradle_processes
    
    # 停止端口占用的进程
    stop_port_processes 8090 "Halo 后端服务"
    stop_port_processes 3000 "主题开发服务"
    stop_port_processes 5173 "Vite 开发服务"
    
    # 清理日志（如果指定）
    cleanup_logs "$1"
    
    echo ""
    log_success "============ 服务器停止完成 ============"
    log_info "所有 Halo 开发服务器已停止"
    
    # 最终检查
    if ! pgrep -f "halo" > /dev/null 2>&1; then
        log_success "✓ 所有 Halo 相关进程已停止"
    else
        log_warning "⚠ 仍有 Halo 相关进程在运行："
        pgrep -f "halo" -l || true
        echo ""
        log_info "如需强制清理，请手动执行："
        log_info "  pkill -f halo"
    fi
    echo ""
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --clean-logs    停止服务器后清理日志文件"
    echo "  --help         显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                # 停止所有服务器"
    echo "  $0 --clean-logs   # 停止服务器并清理日志"
}

# 检查参数
case "$1" in
    --help|-h)
        show_help
        exit 0
        ;;
    --clean-logs)
        main --clean-logs
        ;;
    "")
        main
        ;;
    *)
        log_error "未知参数: $1"
        show_help
        exit 1
        ;;
esac
