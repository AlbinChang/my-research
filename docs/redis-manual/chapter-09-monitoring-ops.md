# 第九章：Redis 监控与运维实战

> **本章核心**：掌握 Redis 的核心监控指标、告警体系搭建方法、常见故障排查流程，以及数据迁移和版本升级的生产操作规范。

---

## 9.1 Redis Info 指标解读

### 9.1.1 核心指标分类

```bash
# 查看所有指标
INFO ALL

# 按类别查看
INFO SERVER
INFO CLIENTS
INFO MEMORY
INFO PERSISTENCE
INFO STATS
INFO REPLICATION
INFO CPU
INFO COMMANDSTATS
INFO CLUSTER
```

### 9.1.2 关键指标详解

**① memory（内存）**

```bash
# 重点关注指标
INFO memory

# used_memory: 1048576000        # Redis 实际使用的内存（字节）
# used_memory_rss: 1200000000   # 操作系统视角的物理内存占用
# used_memory_peak: 1500000000  # 历史峰值
# used_memory_lua: 37888        # Lua 引擎使用内存
# maxmemory: 2147483648          # 配置的内存上限
# maxmemory_policy: allkeys-lru # 淘汰策略
# mem_fragmentation_ratio: 1.14 # 内存碎片率 【核心告警指标】

# 解读 mem_fragmentation_ratio：
# < 1.0: 内存不足，触发了 swap（严重告警！）
# 1.0 - 1.5: 正常范围
# 1.5 - 2.0: 碎片较多，建议重启或迁移
# > 2.0: 严重碎片，必须处理
```

**② stats（统计）**

```bash
# 重点关注指标
INFO stats

# total_connections_received: 100000  # 累计连接数（监控增长速度）
# total_commands_processed: 50000000  # 累计命令数
# instantaneous_ops_per_sec: 85000    # 当前 QPS 【核心指标】
# total_net_input_bytes: 1073741824  # 总网络输入
# total_net_output_bytes: 2147483648 # 总网络输出
# instantaneous_input_kbps: 12500     # 当前网络输入（KB/s）
# instantaneous_output_kbps: 25000    # 当前网络输出（KB/s）
# rejected_connections: 0            # 拒绝的连接数
# expired_keys: 5000                  # 已过期 key 数量
# evicted_keys: 0                     # 被淘汰的 key 数量【核心告警指标】
# keyspace_hits: 950000              # 缓存命中次数
# keyspace_misses: 50000             # 缓存未命中次数
# hit_rate: 95%                      # 命中率 = hits / (hits + misses)
```

**③ persistence（持久化）**

```bash
# 重点关注指标
INFO persistence

# rdb_last_save_time: 1704067200     # 最后一次 RDB 保存时间
# rdb_last_bgsave_status: ok         # 最后一次 BGSAVE 状态
# rdb_last_bgsave_time_sec: 12       # 最后一次 BGSAVE 耗时
# rdb_current_bgsave_time_sec: -1    # 当前 BGSAVE 耗时（-1=没有进行中）
# aof_enabled: 1                     # AOF 是否开启
# aof_last_rewrite_time_sec: 5       # 最后一次 AOF 重写耗时
# aof_last_bgrewrite_status: ok      # 最后一次 AOF 重写状态
# aof_current_size: 524288000        # 当前 AOF 文件大小（字节）
```

**④ replication（复制）**

```bash
# 主节点视角
INFO replication
# role: master
# connected_slaves: 2
# slave0: ip=192.168.1.11,port=6379,state=online,offset=123456,lag=0
# slave1: ip=192.168.1.12,port=6379,state=online,offset=123456,lag=1

# 从节点视角
# role: slave
# master_host: 192.168.1.10
# master_port: 6379
# master_link_status: up               # 主从连接状态
# master_last_io_seconds_ago: 0        # 距离上次与主节点通信的秒数
# master_sync_in_progress: 0           # 是否正在进行全量复制
# slave_repl_offset: 123456            # 从节点复制偏移量
# slave_priority: 100                  # 哨兵晋升优先级
```

### 9.1.3 监控指标一览表

| 分类 | 告警指标 | 阈值 | 严重级别 |
|------|---------|------|---------|
| 内存 | `mem_fragmentation_ratio` | > 1.5 告警，> 2.0 严重 | 🔴 |
| 内存 | `used_memory / maxmemory` | > 80% 告警，> 90% 严重 | 🔴 |
| 统计 | `instantaneous_ops_per_sec` | 接近理论峰值 | 🟡 |
| 统计 | `evicted_keys`（持续增长）| > 0 即有淘汰 | 🔴 |
| 统计 | `hit_rate` | < 90% | 🟡 |
| 持久化 | `rdb_last_bgsave_status` | not ok | 🔴 |
| 持久化 | `aof_last_bgrewrite_status` | not ok | 🔴 |
| 复制 | `master_link_status` | not up | 🔴 |
| 复制 | `master_last_io_seconds_ago` | > 10（秒） | 🟡 |
| 客户端 | `connected_clients` | 突然增长或下降 | 🟡 |
| 客户端 | `rejected_connections` | > 0 | 🔴 |

---

## 9.2 监控告警体系搭建

### 9.2.1 架构方案

```
[Redis Exporter] → 采集 Redis 指标
        ↓
[Prometheus] → 时序数据库，存储指标
        ↓
[Alertmanager] → 根据规则触发告警
        ↓
[钉钉/企微/邮件] → 通知运维人员

[Grafana] → 可视化面板，展示趋势
```

### 9.2.2 Prometheus + Grafana 方案

**① 部署 Redis Exporter**

```bash
# Docker 部署
docker run -d --name redis-exporter \
  -p 9121:9121 \
  oliver006/redis_exporter \
  --redis.addr redis://192.168.1.10:6379 \
  --redis.password yourpassword
```

**② Prometheus 配置**

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'redis'
    static_configs:
      - targets:
        - '192.168.1.10:9121'  # Redis 实例1
        - '192.168.1.11:9121'  # Redis 实例2
        - '192.168.1.12:9121'  # Redis 实例3
```

**③ 告警规则**

```yaml
# alert_rules.yml
groups:
  - name: redis_alerts
    rules:
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        annotations:
          summary: "Redis 实例 {{ $labels.instance }} 不可达"
      
      - alert: RedisMemoryHigh
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.8
        for: 5m
        annotations:
          summary: "Redis {{ $labels.instance }} 内存使用超过 80%"
      
      - alert: RedisFragmentationHigh
        expr: redis_mem_fragmentation_ratio > 1.5
        for: 10m
        annotations:
          summary: "Redis {{ $labels.instance }} 内存碎片率过高"
      
      - alert: RedisEvictions
        expr: rate(redis_evicted_keys_total[5m]) > 0
        for: 1m
        annotations:
          summary: "Redis {{ $labels.instance }} 正在淘汰 key"
      
      - alert: RedisReplicationBroken
        expr: redis_connected_slaves < 1
        for: 1m
        annotations:
          summary: "Redis 主节点 {{ $labels.instance }} 没有从节点连接"
      
      - alert: RedisHitRateLow
        expr: rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) < 0.9
        for: 10m
        annotations:
          summary: "Redis {{ $labels.instance }} 缓存命中率低于 90%"
```

**④ Grafana 关键面板**

| 面板名称 | 指标 | 说明 |
|---------|------|------|
| QPS 趋势 | `rate(redis_commands_processed_total[1m])` | 实时吞吐量 |
| 内存使用率 | `redis_memory_used_bytes / redis_memory_max_bytes` | 内存占比 |
| 热点命令 | `topk(10, rate(redis_commands_total[1m]))` | 命令分布 |
| 慢查询 | `rate(redis_slowlog_len[1m])` | 慢查询数量 |
| 网络IO | `rate(redis_net_input_bytes_total[1m])` | 入口带宽 |
| 命中率 | 见上 | 缓存效果 |

### 9.2.3 关键告警的响应策略

**内存告警（used_memory > 80%）**
```
1. 确认是否设置了合理的 maxmemory
2. 检查是否有 Big Key（执行 --bigkeys）
3. 检查是否有异常流量导致缓存暴增
4. 临时扩容 maxmemory（如果硬件支持）
5. 长期：增加节点、优化数据结构
```

**命中率告警（hit_rate < 90%）**
```
1. 确认缓存 TTL 是否过短
2. 检查是否有大量新 key 进入（数据倾斜）
3. 确认缓存是否被意外清空（FLUSHALL/FLUSHDB）
4. 检查是否有缓存穿透情况
```

**淘汰告警（evicted_keys > 0）**
```
1. 说明内存已满，新数据写入导致旧数据被淘汰
2. 检查 QPS 是否突增
3. 增加 maxmemory 或扩容
4. 检查是否需要调整淘汰策略
```

---

## 9.3 故障排查方法论

### 9.3.1 场景1：Redis 响应变慢

```bash
# 排查步骤：

# 1. 检查慢查询
SLOWLOG GET 10

# 2. 检查是否有 Big Key（阻塞操作）
redis-cli --bigkeys

# 3. 检查内存是否不足（触发淘汰）
INFO memory | grep -E "(used_memory|maxmemory|evicted)"

# 4. 检查是否有 Fork 操作（BGSAVE/BGREWRITEAOF）
INFO persistence | grep -E "(rdb_bgsave|aof_rewrite)"

# 5. 检查系统层面
# 查看 CPU 使用率：top
# 查看磁盘 IO：iostat -x 1
# 查看网络：sar -n DEV 1
# 查看内存：free -h
# 查看是否触发 swap：vmstat 1
```

**🔥 实战排查脚本：**

```bash
#!/bin/bash
# redis_diagnose.sh

REDIS_CLI="redis-cli -h 127.0.0.1 -p 6379"

echo "====== Redis 诊断报告 ======"
echo ""

echo "1. 基本信息"
$REDIS_CLI INFO SERVER | grep -E "(redis_version|uptime_in_seconds|process_id)"

echo ""
echo "2. 内存状态"
$REDIS_CLI INFO memory | grep -E "(used_memory_human|used_memory_rss_human|maxmemory_human|mem_fragmentation_ratio|evicted_keys)"

echo ""
echo "3. 持久化状态"
$REDIS_CLI INFO persistence | grep -E "(rdb_last_bgsave_status|aof_last_bgrewrite_status|aof_current_size_human)"

echo ""
echo "4. 复制状态"
$REDIS_CLI INFO replication | grep -E "(role|connected_slaves|master_link_status)"

echo ""
echo "5. 慢查询（最近5条）"
$REDIS_CLI SLOWLOG GET 5

echo ""
echo "6. 当前客户端连接"
$REDIS_CLI INFO clients | grep -E "(connected_clients|blocked_clients|client_biggest_input_buf)"

echo ""
echo "7. 操作系统状态"
top -bn1 | head -5
```

### 9.3.2 场景2：Redis OOM 或进程被 Kill

```bash
# 1. 查看系统日志
# Linux
dmesg | grep -i "oom"
/var/log/messages | grep -i "redis"

# 2. 确认是否启用了 maxmemory
CONFIG GET maxmemory

# 3. 检查内存增长趋势（使用 MONITOR 时慎用）
redis-cli --stat  # 实时查看内存变化

# 4. 如果 maxmemory 设置正确但仍然 OOM
# 检查是否 fork 子进程导致 COW 内存翻倍
# 减少 BGSAVE 频率/错开时间
```

### 9.3.3 场景3：主从延迟过大

```bash
# 1. 查看延迟时间
INFO replication | grep lag

# 2. 检查从节点是否在进行全量复制
INFO replication | grep in_progress

# 3. 检查网络带宽
# 如果网络带宽不够，复制会产生积压
sar -n DEV 1 10 | grep eth0

# 4. 调整 backlog 大小（使增量复制能重连）
CONFIG SET repl-backlog-size 256mb
```

---

## 9.4 数据迁移与升级

### 9.4.1 使用 Redis-Shake 迁移

Redis-Shake 是阿里云开源的 Redis 数据同步工具：

```bash
# 下载 redis-shake
wget https://github.com/tair-opensource/RedisShake/releases/download/v4.0.0/redis-shake-linux-amd64.tar.gz

# 配置文件 shake.toml
[source]
type = "standalone"
address = "192.168.1.10:6379"
password = "oldpassword"

target.type = "cluster"
target.address = "192.168.1.20:6379"
target.password = "newpassword"

[filter]
# 排除特定 db
exclude_dbs = ["1", "2"]
# 只迁移特定前缀的 key
include_key_prefixes = ["user:", "order:"]

[advanced]
# 并行度
task_parallelism = 32

# 执行迁移
./redis-shake shake.toml
```

### 9.4.2 热升级（从 6.x 到 7.x）

```bash
# 1. 先升级从节点（逐个升级）
# 1.1 停止 Redis 6.x 从节点
redis-cli -p 6380 SHUTDOWN

# 1.2 启动 Redis 7.x 从节点
redis-server /path/to/redis7.conf

# 1.3 确认从节点同步正常
redis-cli -p 6380 INFO replication | grep master_link_status
# 直到 master_link_status: up

# 2. 主从切换
redis-cli -p 6379 FAILOVER  # 触发主从切换（Redis 6.2+）
# 或者手动在 Sentinel 中切换

# 3. 升级旧主节点
# 3.1 确认新主节点运行正常
# 3.2 停止旧主节点的 Redis 6.x
# 3.3 启动 Redis 7.x 并配置为从节点
redis-cli -p 6379 REPLICAOF 192.168.1.10 6380

# 4. 全部升级完成
```

---

## 本章小结

1. **监控指标**：掌握 INFO 命令的核心指标，重点关注 `hit_rate`、`evicted_keys`、`mem_fragmentation_ratio`、`instantaneous_ops_per_sec`
2. **告警体系**：Prometheus + Redis Exporter + Grafana 是业界标准方案
3. **故障排查**：慢查询 → Big Key → 内存 → Fork → 系统资源，逐层排查
4. **数据迁移**：Redis-Shake 是主流工具，支持全量+增量迁移
5. **热升级**：采用从节点逐台升级 → 主从切换 → 升级旧主节点的滚动升级策略

> **一句话记住**：监控不是目的，发现问题是手段，快速恢复是根本——建立「发现问题 → 定位根因 → 修复恢复 → 复盘改进」的完整运维闭环。
