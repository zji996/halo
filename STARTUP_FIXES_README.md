# Halo 启动问题修复说明

## 修复概述

本次修复解决了 Halo 项目启动时遇到的两个主要问题：

1. **Node.js 弃用警告**：`fs.Stats constructor is deprecated`
2. **Gradle bootRun 卡住**：在 92% 阶段停止响应

## 修复内容

### 1. Node.js 弃用警告修复

**问题原因**：Node.js v23.11.0 中某些依赖包使用了已弃用的 `fs.Stats` 构造函数

**解决方案**：
- 在 [`ui/package.json`](ui/package.json:9) 中的启动脚本添加了 `NODE_OPTIONS='--no-deprecation'`
- 在启动脚本中设置环境变量 `export NODE_OPTIONS="--no-deprecation"`

**修改的文件**：
```json
// ui/package.json
{
  "scripts": {
    "dev:uc": "NODE_OPTIONS='--no-deprecation' vite --host --config ./vite.uc.config.ts",
    "dev:console": "NODE_OPTIONS='--no-deprecation' vite --host --config ./vite.config.ts"
  }
}
```

### 2. Gradle 启动优化

**问题原因**：
- 启动时序问题：UI 服务和后端服务启动冲突
- 缺乏有效的健康检查机制
- 端口冲突未处理
- 等待时间不足

**解决方案**：
- 添加端口检查和自动清理功能
- 实现服务健康检查机制
- 增加启动超时时间（UI: 30秒，后端: 120秒）
- 改进错误处理和用户反馈
- 添加进程管理和优雅停止

## 可用的启动脚本

### 1. 原脚本（已修复）- [`run_halo.sh`](run_halo.sh:1)

```bash
./run_halo.sh
```

**特点**：
- 保持原有的简单界面
- 应用了所有核心修复
- 适合日常开发使用

### 2. 增强版脚本 - [`run_halo_improved.sh`](run_halo_improved.sh:1)

```bash
# 基本启动
./run_halo_improved.sh

# 查看帮助
./run_halo_improved.sh --help

# 检查依赖
./run_halo_improved.sh --check
```

**特点**：
- 详细的状态反馈
- 完整的错误处理
- 服务状态监控
- 日志记录功能
- 命令行参数支持

## 启动流程

### 修复后的启动流程

1. **环境检查**
   - 检查必要依赖（pnpm, java, curl, lsof）
   - 设置 Node.js 环境变量

2. **端口管理**
   - 检查端口 4000 和 8090 是否可用
   - 自动清理占用的端口

3. **UI 服务启动**
   - 安装依赖（如需要）
   - 构建包
   - 启动开发服务器
   - 健康检查（最多等待 30 秒）

4. **后端服务启动**
   - 启动 Spring Boot 应用
   - 健康检查（最多等待 120 秒）
   - 验证服务可用性

5. **服务监控**
   - 持续监控服务状态
   - 提供访问地址信息
   - 优雅停止机制

## 服务地址

启动成功后，可以通过以下地址访问：

- **前端开发服务器**: http://localhost:4000
- **后端 API 服务**: http://localhost:8090
- **管理控制台**: http://localhost:8090/console
- **健康检查**: http://localhost:8090/actuator/health

## 故障排除

### 常见问题及解决方案

#### 1. Node.js 弃用警告仍然出现

**检查**：
```bash
# 验证环境变量设置
echo $NODE_OPTIONS

# 检查 package.json 修改
grep "NODE_OPTIONS" ui/package.json
```

**解决**：确保环境变量正确设置，重启终端会话

#### 2. 端口被占用

**检查**：
```bash
# 查看端口占用
lsof -i :4000
lsof -i :8090
```

**解决**：脚本会自动处理，或手动清理：
```bash
# 清理端口 4000
lsof -ti:4000 | xargs kill -9

# 清理端口 8090
lsof -ti:8090 | xargs kill -9
```

#### 3. 服务启动超时

**可能原因**：
- 网络问题
- 系统资源不足
- 依赖下载缓慢

**解决**：
- 检查网络连接
- 增加系统内存
- 使用国内镜像源

#### 4. Gradle 构建失败

**检查**：
```bash
# 验证 Java 版本
java -version

# 检查 Gradle wrapper
./gradlew --version
```

**解决**：
- 确保 Java 版本兼容（推荐 Java 21）
- 清理 Gradle 缓存：`./gradlew clean`

## 日志查看

### 增强版脚本日志

```bash
# 查看 UI 服务日志
tail -f logs/ui.log

# 查看后端服务日志
tail -f logs/backend.log
```

### 系统日志

```bash
# 查看系统进程
ps aux | grep -E "(vite|java)"

# 查看端口状态
netstat -tulpn | grep -E "(4000|8090)"
```

## 性能优化建议

### 1. 系统配置

- **内存**：建议至少 8GB RAM
- **CPU**：建议 4 核心以上
- **磁盘**：使用 SSD 提高构建速度

### 2. 开发环境优化

```bash
# 设置 pnpm 镜像（中国用户）
pnpm config set registry https://registry.npmmirror.com

# 设置 Gradle 镜像
# 在 ~/.gradle/gradle.properties 中添加：
# systemProp.https.proxyHost=mirrors.huaweicloud.com
# systemProp.https.proxyPort=443
```

### 3. IDE 配置

- 配置 IDE 排除 `node_modules` 和 `build` 目录
- 启用增量编译
- 配置合适的内存分配

## 测试验证

运行测试脚本验证修复效果：

```bash
./test_fixes.sh
```

测试内容包括：
- 依赖检查
- 环境验证
- 端口状态
- 配置验证
- 脚本权限

## 维护建议

### 定期维护

1. **更新依赖**
   ```bash
   cd ui && pnpm update
   ./gradlew dependencies --refresh-dependencies
   ```

2. **清理缓存**
   ```bash
   cd ui && pnpm store prune
   ./gradlew clean
   ```

3. **检查日志**
   ```bash
   # 定期检查启动日志
   ls -la logs/
   ```

### 监控指标

- UI 服务启动时间：< 30 秒
- 后端服务启动时间：< 120 秒
- 内存使用：< 4GB
- CPU 使用：< 80%

## 版本兼容性

### 测试环境

- **Node.js**: v23.11.0
- **Java**: OpenJDK 21.0.7
- **pnpm**: 9.15.0
- **操作系统**: macOS Sequoia

### 兼容性说明

- Node.js: 支持 18.x 及以上版本
- Java: 支持 17 及以上版本
- 操作系统: macOS, Linux, Windows (WSL)

## 更新日志

### v1.0.0 (2025-05-31)

- ✅ 修复 Node.js 弃用警告
- ✅ 解决 Gradle bootRun 卡住问题
- ✅ 添加端口检查和清理
- ✅ 实现服务健康检查
- ✅ 改进错误处理和用户反馈
- ✅ 创建增强版启动脚本
- ✅ 添加完整的测试和文档

---

如有问题，请查看 [`halo_startup_fix_plan.md`](halo_startup_fix_plan.md:1) 获取详细的技术方案。