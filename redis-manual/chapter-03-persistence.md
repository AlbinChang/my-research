# 第三章：Redis 持久化原理与生产配置

> **本章核心**：理解 RDB 和 AOF 两种持久化机制的原理、配置和优劣，掌握生产环境中最优的持久化策略，以及从真实数据丢失事故中吸取教训。

---

## 3.1 RDB 快照原理与配置优化

### 3.1.1 触发机制

RDB（Redis Database）是 Redis 的默认持久化方式，它生成一个经过压缩的二进制快照文件（dump.rdb）。

**触发方式有三种：**

**① 自动触发（按配置策略）**
```bash
# redis.conf 配置：在满足以下任一条件时自动生成 RDB
save 900 1      # 900秒（15分钟）内至少1个key变化
save 300 10     # 300秒（5分钟）内至少10个key变化
save 60 10000   # 60秒内至少10000个key变化

# 可以关闭自动保存
save ""
```

**② 手动触发**
```bash
# 同步生成 RDB（阻塞主进程，不推荐生产环境使用）
SAVE

# 异步生成 RDB（fork子进程处理，不阻塞主进程，推荐）
BGSAVE
```

**③ 其他触发场景**
- 执行 `SHUTDOWN` 时自动生成
- 主从全量复制时，主节点自动生成 RDB 传给从节点
- `DEBUG RELOAD` 命令触发

### 3.1.2 RDB 的 fork 与 Copy-On-Write 原理

RDB 的核心机制是 fork + COW（Copy-On-Write，写时复制）：

```
┌─────────────┐          fork()          ┌─────────────┐
│  Redis 主进程 │ ──────────────────────→   │  子进程      │
│  (处理请求)   │                         │  (写RDB文件)  │
│              │                         │              │
│  内存页表     │ ←──── 共享内存页 ───→    │  内存页表     │
└─────────────┘                         └─────────────┘
```

**关键流程：**

1. Redis 主进程调用 `fork()` 创建子进程
2. 子进程和父进程共享同一份内存页表（虚拟内存）
3. 子进程开始将内存数据写入临时 RDB 文件
4. **如果在子进程写 RDB 期间，父进程要修改某个内存页**
   - 父进程会复制一份该内存页的副本（Copy-On-Write）
   - 父进程修改的是副本，子进程看到的是原始页
5. 子进程写完后用临时文件原子替换旧 RDB 文件

**🔥 生产至关重要的结论：**

📊 **内存占用公式**：
```
RDB 期间总内存 ≈ 原始数据集 + 写操作量 × 修改的页数 × 4KB
```

如果 RDB 生成期间有大量写操作（尤其是更新 Big Key），COW 会导致内存翻倍增长：

```bash
# 假设 Redis 占用 8GB 内存，RDB 生成期间有 50% 的数据被修改
# 额外内存 ≈ 8GB × 50% = 4GB
# 总内存占用 ≈ 12GB
```

**⚠️ 生产事故案例**：某团队在内存仅 10GB 的机器上运行了 8GB 数据的 Redis，每秒大量写入。BGSAVE 时 COW 导致内存飙升至 14GB，触发 OOM Killer，Redis 进程被杀死。

**💡 解决方案**：
1. 预留足够的内存余量（建议内存使用率 ≤ 60%）
2. 配置 `stop-writes-on-bgsave-error yes`（BGSAVE失败时自动拒绝写入，防止数据不一致）
3. 避免在业务高峰期执行 BGSAVE

### 3.1.3 RDB 配置最佳实践

```bash
# 生产环境推荐配置（redis.conf）

save 3600 1       # 1小时内有1次变更才保存（低频业务）
# 或
save 300 100      # 5分钟100次变更（高频业务）
# 或
save ""           # 完全禁用RDB，只用AOF

stop-writes-on-bgsave-error yes  # BGSAVE失败时拒绝写入
rdbcompression yes               # 启用压缩（LZF算法）
rdbchecksum yes                  # 启用校验（增加约10%开销，但防止文件损坏）
dbfilename "dump-6379.rdb"       # 建议文件名包含端口（多实例时区分）
dir "/data/redis"                # 建议使用独立目录
```

### 3.1.4 RDB 的优缺点

| 优点 | 缺点 |
|------|------|
| 文件紧凑，适合备份和跨网络传输 | 数据丢失风险大（两次快照之间的数据全丢） |
| 加载速度快（直接内存加载） | Fork 阻塞主进程（数据量大时明显） |
| 从节点初始化时加载快 | COW 导致内存暴增 |
| 性能影响小（子进程写文件） | 无法做到实时持久化 |

---

## 3.2 AOF 日志原理与 Rewrite 机制

### 3.2.1 AOF 的写回策略

AOF（Append Only File）以日志形式记录每个写操作，Redis 重启时通过重放 AOF 来恢复数据。

**三种写回策略（appendfsync）：**

| 策略 | 写回时机 | 数据安全性 | 性能 |
|------|---------|-----------|------|
| **always** | 每个命令执行后立即 fsync | 最多丢 1 个操作 | 最慢（约 500 QPS） |
| **everysec（推荐）** | 每秒 fsync 一次 | 最多丢 1 秒数据 | 约 10 万 QPS |
| **no** | 由操作系统决定写入时机 | 可能丢大量数据 | 最快 |

**💡 深入理解 write 和 fsync 的差异：**

```
应用层写 AOF：
  write() → 写入内核缓冲区（Page Cache）→ 立即返回
  fsync() → 强制将 Page Cache 刷到磁盘 → 阻塞等待完成
```

- `appendfsync always`：**每个命令**执行 `write()` + `fsync()`，性能极差
- `appendfsync everysec`：**每个命令**执行 `write()`，每 1 秒执行一次 `fsync()`，兼顾安全和性能
- `appendfsync no`：**每个命令**执行 `write()`，由 OS 决定何时刷盘（通常 30 秒），崩溃时丢大量数据

### 3.2.2 AOF 文件格式

AOF 文件是纯文本格式，可读性强：

```
$ cat appendonly-6379.aof | head -20
*2               # 数组长度（2个参数）
$6               # 下一个参数长度 6
SELECT           # 命令
$1
0
*3
$3
SET
$4
user1
$5
hello
*3
$3
SET
$4
user2
$5
world
```

可以直接用 `redis-check-aof` 工具检查和修复 AOF 文件：

```bash
# 检查 AOF 文件完整性
redis-check-aof --fix appendonly-6379.aof
```

### 3.2.3 AOF Rewrite 重写机制

AOF 记录了所有写操作，随着时间的推移，文件会无限增长。AOF Rewrite 就是压缩过程：

**举例：**
```bash
# 原始 AOF 内容（1000 条 INCR）
INCR counter
INCR counter
... x 1000 次

# Rewrite 后只保留最终状态
SET counter 1000
```

**Rewrite 触发条件：**

```bash
# redis.conf 配置
auto-aof-rewrite-percentage 100    # AOF文件比上一次重写后增长100%时触发
auto-aof-rewrite-min-size 64mb     # AOF文件至少达到64MB才触发
```

**手动触发：**
```bash
BGREWRITEAOF   # 异步重写（推荐）
```

**Rewrite 内部流程：**

```
1. 主进程 fork 出子进程
2. 子进程将当前内存数据转换为 AOF 格式写入临时文件
3. 同时主进程将新收到的写操作写入 AOF 重写缓冲区
4. 子进程完成后通知主进程
5. 主进程将重写缓冲区的内容追加到临时文件
6. 原子替换旧 AOF 文件
```

**⚠️ 和 RDB 同样的陷阱**：AOF Rewrite 也会 fork 子进程，同样存在 COW 内存膨胀问题。

### 3.2.4 AOF 配置最佳实践

```bash
# 生产环境推荐配置
appendonly yes                 # 开启 AOF
appendfilename "appendonly-6379.aof"  # 包含端口号
appendfsync everysec           # 每秒刷盘（黄金平衡点）
no-appendfsync-on-rewrite yes  # 重写期间不进行 fsync，防止磁盘 IO 阻塞

auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 256mb  # 大一点，避免频繁重写

aof-load-truncated yes        # 加载时截断最后一条不完整命令（容错）
aof-use-rdb-preamble yes      # 混合持久化（Redis 4.0+ 推荐）
```

---

## 3.3 混合持久化（Redis 4.0+）

### 3.3.1 原理

混合持久化结合了 RDB 和 AOF 的优点：AOF 文件的开头是 RDB 格式的全量数据，后面追加增量 AOF 日志。

```
┌─────────────────────────────────────────────────┐
│  RDB 格式（全量快照）     │   AOF 格式（增量命令）    │
│  文件大小：约 200MB       │   文件大小：约 5MB       │
│  加载时间：约 3 秒        │   追加写入：实时          │
└─────────────────────────────────────────────────┘
```

**加载速度对比：**

| 持久化方式 | 10GB 数据加载时间 | 数据安全性 |
|-----------|-----------------|-----------|
| 纯 RDB | ~30 秒 | 可能丢大量数据 |
| 纯 AOF | ~5 分钟 | 最多丢 1 秒 |
| **混合持久化** | **~35 秒** | **最多丢 1 秒** |

### 3.3.2 配置开启

```bash
# redis.conf 中设置（Redis 4.0+）
aof-use-rdb-preamble yes
```

**推荐方案：** 混合持久化 + appendfsync everysec，这是目前 Redis 最推荐的持久化方案。

---

## 3.4 🔥 生产事故：未配置持久化导致全量数据丢失

### 事故背景

某社交 APP 使用 Redis 存储用户关系数据（关注列表、粉丝列表），Redis 部署在单机上，使用默认配置。

**当时的配置：**
```bash
# 使用的默认配置（仅 RDB）
save 900 1
save 300 10
save 60 10000
# 没有开启 AOF！
appendonly no
```

### 事故经过

```
23:30  线上出现流量高峰（用户晚高峰）
23:45  触发 RDB 快照，数据量约 6GB
23:45  服务器内存压力增大，触发 swap
23:48  Redis 进程 OOM，被内核杀死
23:50  运维重启 Redis 进程
23:50  Redis 读取最后的 dump.rdb 文件
23:51  加载完成，但数据是 23:30 的快照
       —— 15分钟的用户关系数据全部丢失！
```

**影响范围：**
- 约 23 万条新关注关系丢失
- 约 5 万用户的粉丝数回退
- 持续时间 3 小时才从数据库恢复完毕
- 被用户投诉「关注的人消失了」

### 根本原因分析

**三层失误：**

1. **没有开启 AOF**：RDB 只能做快照级别的持久化，两次快照之间的数据在 Redis 崩溃时彻底丢失
2. **RDB 配置不合理**：`save 60 10000` 在高并发下很快触发 RDB，大内存 RDB 拖垮服务器
3. **没有设置 `maxmemory`**：Redis 使用无限制的内存，直到 OOM

### 事后改进方案

**第 1 步：开启混合持久化**
```bash
# 新的持久化配置
appendonly yes
appendfsync everysec
aof-use-rdb-preamble yes
save 3600 1    # 减少 RDB 频率
```

**第 2 步：限制 Redis 内存**
```bash
# 防止 OOM
maxmemory 6gb
maxmemory-policy allkeys-lru  # 内存满时淘汰最近最少使用的 key
```

**第 3 步：定期备份 RDB**
```bash
# crontab 每小时备份一次 RDB 到远程存储
0 * * * * cp /data/redis/dump-6379.rdb /backup/redis/dump-$(date +\%Y\%m\%d\%H).rdb
```

**第 4 步：主从高可用**

部署一个从节点：
```bash
# 从节点配置
replicaof 192.168.1.10 6379
# 从节点只用于数据冗余，不发生主从切换
```

---

## 本章小结

1. **RDB**：适合全量备份和快速灾难恢复，但存在数据丢失窗口
2. **AOF**：提供秒级数据安全，但文件大、恢复慢
3. **混合持久化（推荐）**：兼具 RDB 的快速恢复和 AOF 的高安全性
4. **核心建议**：生产环境务必开启 `appendonly yes` + `appendfsync everysec` + `aof-use-rdb-preamble yes`
5. **内存规划**：预留 30-50% 的内存余量给 fork 时的 COW 使用
6. **备份策略**：RDB 用于冷备（每小时备份到远程），AOF 用于实时持久化

> **一句话记住**：没有持久化的 Redis 就是一架没装降落伞的飞机——看起来飞得很快，但随时可能坠毁。
