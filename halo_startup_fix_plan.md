# Halo 启动问题修复方案

## 问题概述

在运行 Halo 项目时遇到以下问题：
1. Node.js 弃用警告：`fs.Stats constructor is deprecated`
2. Gradle bootRun 在 92% 阶段卡住

## 问题分析

### Node.js 弃用警告
- **原因**：Node.js 版本较新，某些依赖包使用了已弃用的 `fs.Stats` 构造函数
- **影响**：虽然不影响功能，但会产生警告信息，影响开发体验
- **涉及组件**：主要是 Vite 和相关构建工具

### Gradle bootRun 卡住
- **原因分析**：
  - UI 服务（端口 4000）和后端服务（端口 8090）启动时序问题
  - 当前脚本等待时间可能不足
  - 缺乏有效的健康检查机制
- **当前配置**：
  - UI 服务：Vite 开发服务器，端口 4000
  - 后端服务：Spring Boot，端口 8090
  - 等待时间：固定 10 秒

## 解决方案

### 阶段一：修复 Node.js 弃用警告

#### 1.1 环境变量配置
在启动脚本中添加以下环境变量：
```bash
# 抑制 Node.js 弃用警告
export NODE_OPTIONS="--no-deprecation"
# 或者更具体地抑制 fs.Stats 警告
export NODE_OPTIONS="--no-deprecation --disable-warning=DEP0180"
```

#### 1.2 更新 package.json 脚本
修改 UI 项目的启动脚本，添加环境变量：
```json
{
  "scripts": {
    "dev:uc": "NODE_OPTIONS='--no-deprecation' vite --host --config ./vite.uc.config.ts",
    "dev:console": "NODE_OPTIONS='--no-deprecation' vite --host --config ./vite.config.ts"
  }
}
```

#### 1.3 Vite 配置优化
在 `vite.config.ts` 和 `vite.uc.config.ts` 中添加配置以减少警告：
```typescript
export default defineConfig({
  // ... 其他配置
  build: {
    rollupOptions: {
      onwarn(warning, warn) {
        // 忽略特定的弃用警告
        if (warning.code === 'DEPRECATED_FEATURE') return;
        warn(warning);
      }
    }
  }
});
```

### 阶段二：优化启动脚本

#### 2.1 改进的启动脚本结构
```bash
#!/bin/bash

# 配置环境变量
export NODE_OPTIONS="--no-deprecation"

# 颜色输出函数
print_info() {
    echo -e "\033[34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

# 检查端口是否可用
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        return 1
    else
        return 0
    fi
}

# 等待服务启动
wait_for_service() {
    local url=$1
    local timeout=${2:-60}
    local interval=${3:-2}
    local elapsed=0
    
    print_info "等待服务启动: $url"
    
    while [ $elapsed -lt $timeout ]; do
        if curl -s --connect-timeout 1 "$url" >/dev/null 2>&1; then
            print_success "服务已启动: $url"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    print_error "服务启动超时: $url"
    return 1
}

# 清理函数
cleanup() {
    print_info "正在停止所有服务..."
    if [ ! -z "$UI_PID" ]; then
        kill $UI_PID 2>/dev/null
        print_info "UI 服务已停止"
    fi
    exit 0
}

# 设置信号处理
trap cleanup SIGINT SIGTERM
```

#### 2.2 UI 服务启动优化
```bash
# 启动 UI 服务
start_ui_service() {
    print_info "检查 UI 服务端口 (4000)..."
    if ! check_port 4000; then
        print_warning "端口 4000 已被占用，尝试终止现有进程..."
        lsof -ti:4000 | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
    
    print_info "正在启动 UI 服务..."
    cd ui
    
    # 检查依赖
    if [ ! -d "node_modules" ]; then
        print_info "安装依赖..."
        pnpm install
    fi
    
    # 构建包
    print_info "构建包..."
    pnpm build:packages
    
    # 启动开发服务器
    print_info "启动开发服务器..."
    pnpm dev:uc &
    UI_PID=$!
    
    cd ..
    
    # 等待 UI 服务启动
    if wait_for_service "http://localhost:4000" 30; then
        print_success "UI 服务启动成功"
        return 0
    else
        print_error "UI 服务启动失败"
        return 1
    fi
}
```

#### 2.3 后端服务启动优化
```bash
# 启动后端服务
start_backend_service() {
    print_info "检查后端服务端口 (8090)..."
    if ! check_port 8090; then
        print_warning "端口 8090 已被占用，尝试终止现有进程..."
        lsof -ti:8090 | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
    
    print_info "正在启动 Halo 后端服务..."
    
    # 检查 Java 环境
    if ! command -v java &> /dev/null; then
        print_error "Java 未安装或不在 PATH 中"
        return 1
    fi
    
    # 启动后端服务
    ./gradlew bootRun --args="--spring.profiles.active=dev" &
    BACKEND_PID=$!
    
    # 等待后端服务启动
    if wait_for_service "http://localhost:8090/actuator/health" 120; then
        print_success "后端服务启动成功"
        return 0
    else
        print_error "后端服务启动失败"
        return 1
    fi
}
```

#### 2.4 主启动流程
```bash
# 主启动流程
main() {
    print_info "开始启动 Halo 开发环境..."
    
    # 启动 UI 服务
    if ! start_ui_service; then
        print_error "UI 服务启动失败，退出"
        exit 1
    fi
    
    # 启动后端服务
    if ! start_backend_service; then
        print_error "后端服务启动失败，退出"
        cleanup
        exit 1
    fi
    
    print_success "所有服务启动成功！"
    print_info "前端地址: http://localhost:4000"
    print_info "后端地址: http://localhost:8090"
    print_info "控制台地址: http://localhost:8090/console"
    
    print_info "按 Ctrl+C 停止所有服务..."
    
    # 等待用户中断
    wait
}

# 执行主函数
main
```

### 阶段三：额外优化

#### 3.1 添加配置文件支持
创建 `.env` 文件支持自定义配置：
```bash
# UI 服务配置
UI_PORT=4000
UI_HOST=localhost

# 后端服务配置
BACKEND_PORT=8090
BACKEND_PROFILE=dev

# 启动超时配置
UI_STARTUP_TIMEOUT=30
BACKEND_STARTUP_TIMEOUT=120
```

#### 3.2 添加日志记录
```bash
# 日志配置
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/startup.log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}
```

#### 3.3 健康检查增强
```bash
# 详细健康检查
health_check() {
    local service_name=$1
    local url=$2
    
    print_info "检查 $service_name 健康状态..."
    
    response=$(curl -s -w "%{http_code}" "$url" -o /dev/null)
    
    if [ "$response" = "200" ]; then
        print_success "$service_name 健康检查通过"
        return 0
    else
        print_warning "$service_name 健康检查失败 (HTTP $response)"
        return 1
    fi
}
```

## 实施步骤

### 步骤 1：修复 Node.js 警告
1. 修改 `run_halo.sh` 添加环境变量
2. 更新 `ui/package.json` 中的脚本
3. 测试 UI 服务启动是否还有警告

### 步骤 2：优化启动脚本
1. 重写 `run_halo.sh` 脚本
2. 添加端口检查和健康检查
3. 改进错误处理和用户反馈

### 步骤 3：测试验证
1. 测试完整启动流程
2. 验证服务间通信
3. 测试错误场景处理

## 预期效果

### 修复后的效果
1. **Node.js 警告消除**：不再显示 `fs.Stats constructor is deprecated` 警告
2. **启动成功率提升**：通过健康检查确保服务正常启动
3. **用户体验改善**：清晰的状态反馈和错误信息
4. **稳定性增强**：更好的错误处理和恢复机制

### 性能指标
- UI 服务启动时间：< 30 秒
- 后端服务启动时间：< 120 秒
- 整体启动成功率：> 95%

## 故障排除

### 常见问题
1. **端口占用**：自动检测并清理占用的端口
2. **依赖缺失**：自动检查并提示安装依赖
3. **启动超时**：提供详细的超时信息和建议

### 调试选项
```bash
# 启用调试模式
DEBUG=1 ./run_halo.sh

# 查看详细日志
tail -f logs/startup.log
```

## 维护建议

1. **定期更新依赖**：保持 Node.js 和相关依赖的最新版本
2. **监控启动时间**：定期检查启动性能
3. **日志分析**：定期分析启动日志，发现潜在问题
4. **文档更新**：保持文档与实际配置同步

---

*此文档记录了 Halo 项目启动问题的完整解决方案，包括问题分析、解决方案和实施步骤。*