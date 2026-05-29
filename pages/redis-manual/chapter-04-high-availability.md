# 第四章：Redis 高可用架构设计

> **本章核心**：深入理解主从复制、Sentinel 哨兵和 Redis Cluster 三种高可用架构的原理与实战配置，以及从脑裂等生产事故中学习如何避免数据丢失。

---

## 4.1 主从复制原理与延迟问题

### 4.1.1 复制流程（6.x+）

Redis 的主从复制经历了多次演进，以 6.x 版本的流程为例：

```
┌───────────┐      连接握手      ┌───────────┐
│  主节点    │ ←────────────────→  │  从节点    │
│  Master    │                    │  Slave    │
└─────┬─────┘                    └─────┬─────┘
      │                               │
      │ ① PSYNC {replid, offset}      │
      │ ←────────────────────────────  │
      │                               │
      │ ② 判断：全量复制或增量复制    │
      │                               │
      │ ③ 全量复制：生成RDB + 发送    │
      │ ────────────────────────────→  │
      │   增量复制：发送 backlog 数据  │
      │ ────────────────────────────→  │
      │                               │
      │ ④ 后续写命令实时传播           │
      │ ────────────────────────────→  │
```

**详细步骤：**

```bash
# 从节点视角
127.0.0.1:6379> REPLICAOF 192.168.1.10 6379
OK
# 此时从节点会：
# 1. 向主节点发送 PSYNC 命令
# 2. 主节点回复 FULLRESYNC（全量复制）或 CONTINUE（增量复制）
# 3. 接收 RDB 文件并加载到内存
# 4. 开始接收并执行主节点后续的所有写命令
```

### 4.1.2 核心复制机制

**复制积压缓冲区（Replication Backlog）：**

- 主节点维护一个 **固定大小** 的环形缓冲区（默认 1MB）
- 记录最近执行的所有写命令
- 从节点断开重连后，如果 offset 还在 backlog 范围内 → **增量复制**（秒级完成）
- 如果 offset 不在 backlog 范围内（断开太久）→ **全量复制**（可能耗时数分钟）

```bash
# 调整 backlog 大小（根据网络稳定性）
repl-backlog-size 100mb    # 网络不稳定时调大
repl-backlog-ttl 3600       # 无从节点时保留3600秒
```

### 4.1.3 主从延迟问题

**延迟来源：**

| 延迟阶段 | 原因 | 典型耗时 |
|---------|------|---------|
| 主节点写 | 执行命令本身 | 0.1ms |
| 网络传输 | TCP 发送命令到从节点 | 0.5-5ms（同机房） |
| 从节点处理 | 从节点执行命令 | 0.1ms |
| **总延迟** |  | **0.7-5ms（同机房）** |

**跨机房部署时延迟可达 50-100ms**

**🔴 延迟带来的风险：**

```java
// 竞争条件（Race Condition）示例
@Service
public class OrderService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    // 从 Redis 写后立即读到过期数据
    public void createOrder(Order order) {
        // 写入主节点
        redisTemplate.opsForValue().set("order:" + order.getId(), "paid");
        
        // 如果读的是从节点，可能读到旧值！
        // 但这里读的是主节点，没问题
        
        // 但如果是「先删缓存再更新DB」的一致性方案：
        redisTemplate.delete("order:" + order.getId());  // 删缓存
        // 此时 MySQL 还未更新，其他请求打到从节点
        // 从节点可能还有旧缓存数据！
    }
}
```

**🔥 解决方案：**

```bash
# 方案1：从节点只做冷备，读写都在主节点
# 方案2：强制主节点读取（读写分离时）
SET ReadFromMaster=true

# 方案3：使用 WAIT 命令等待从节点确认（牺牲性能换一致性）
# 在执行写命令后等待至少1个从节点确认
SET key value
WAIT 1 1000    # 等待1个从节点确认，超时1000ms
```

### 4.1.4 复制配置最佳实践

```bash
# 主节点配置
replica-serve-stale-data yes       # 从节点与主节点断开后是否继续响应
repl-diskless-sync yes             # 无磁盘复制（Redis 2.8.18+），子进程直接发送给从节点
repl-diskless-sync-delay 5         # 等待5秒，等更多从节点一起复制
repl-backlog-size 100mb            # 调大 backlog，减少全量复制概率
min-replicas-to-write 1            # 最少1个从节点在线才接受写
min-replicas-max-lag 10            # 从节点延迟超过10秒视为离线

# 从节点配置
replica-read-only yes              # 从节点只读（防止误写）
replica-priority 100               # 优先级（越低越优先成为主节点）
```

---

## 4.2 Sentinel 哨兵模式

### 4.2.1 架构与工作原理

Sentinel 是 Redis 的高可用解决方案，提供 **自动故障转移** 能力：

```
        ┌──────────────────┐
        │  Sentinel 集群   │ (3个或5个实例)
        │  监视 + 选主     │
        └──────┬──────┬────┘
               │      │
          ┌────┘      └────┐
          │                │
    ┌─────▼─────┐    ┌─────▼─────┐
    │  Master   │    │  Slave1   │
    │  (主)     │ ←──│  (从)     │
    └───────────┘    └───────────┘
                           │
                     ┌─────▼─────┐
                     │  Slave2   │
                     │  (从)     │
                     └───────────┘
```

**核心机制：**

1. **监控（Monitor）**：Sentinel 每秒向所有节点发送 PING，检测存活状态
2. **主观下线（SDOWN）**：一个 Sentinel 发现节点无响应（`down-after-milliseconds` 内未回复 PING）
3. **客观下线（ODOWN）**：多个 Sentinel（根据 quorum 配置）都认为主节点下线
4. **故障转移（Failover）**：Sentinel 集群选举出一个 Leader，执行故障转移
5. **通知（Notification）**：通知应用端新的主节点地址

### 4.2.2 故障转移流程详解

```
时间线：

T0:  主节点 Master 宕机
T1:  Sentinel1 检测到 Master 无响应 → 标记 SDOWN
T2:  Sentinel2、Sentinel3 也检测到 → 达到 quorum → 标记 ODOWN
T3:  Sentinel 集群选举 Leader（Raft 协议）
T4:  Leader 从从节点中选出新主节点（根据优先级、复制偏移量等）
T5:  Leader 向新主节点发送 SLAVEOF NO ONE（变成主节点）
T6:  Leader 通知其他从节点 REPLICAOF 新主节点
T7:  旧主节点恢复后，自动成为新主节点的从节点

总耗时：通常 10-30 秒
```

### 4.2.3 Sentinel 配置实战

```bash
# sentinel.conf（3个 Sentinel 实例）

#  Sentinel 1 (端口 26379)
sentinel monitor mymaster 192.168.1.10 6379 2  # 至少2个Sentinel同意才判定下线
sentinel down-after-milliseconds mymaster 5000      # 5秒无响应即判下线
sentinel failover-timeout mymaster 30000            # 故障转移超时30秒
sentinel parallel-syncs mymaster 1                  # 并发同步数（1个1个来）
sentinel auth-pass mymaster yourpassword            # 如果有密码

#  Sentinel 2 (端口 26380)
sentinel monitor mymaster 192.168.1.10 6379 2
# ... 其他配置同上

#  Sentinel 3 (端口 26381)
sentinel monitor mymaster 192.168.1.10 6379 2
# ... 其他配置同上
```

**Spring Boot 集成 Sentinel：**

```yaml
# application.yml
spring:
  redis:
    sentinel:
      master: mymaster
      nodes:
        - 192.168.1.10:26379
        - 192.168.1.11:26380
        - 192.168.1.12:26381
    password: yourpassword
```

### 4.2.4 Sentinel 的坑与最佳实践

**🔴 坑1：Sentinel 不是 VIP/SLB**

应用端需要监听 Sentinel 的通知来切换连接，或者使用 Redis 客户端内置的 Sentinel 支持（如 Lettuce、Jedis Sentinel）。

**🔴 坑2：quorum 设置**

```bash
# 3个 Sentinel 实例时，quorum=2 表示至少2个同意才判定下线
# 5个 Sentinel 实例时，quorum=3
# 原则：quorum ≤ N/2 + 1
```

**🔴 坑3：故障转移期间的写入丢失**

故障转移需要 10-30 秒，在此期间写入旧主节点的数据可能丢失（因为旧主节点已经宕机，未同步给从节点）。

**🔥 最佳实践：**

```
1. Sentinel 部署奇数个（3或5个），不能是1个（单点故障）
2. Sentinel 和 Redis 实例分开部署在不同的机器上
3. 至少部署 3 个 Sentinel 实例
4. 设置 min-replicas-to-write 避免主节点在无从节点时还写入
```

---

## 4.3 Redis Cluster 集群分片

### 4.3.1 架构设计

Redis Cluster（Redis 3.0+）提供 **自动分片 + 高可用** 的一体化方案：

```
          ┌── 客户端 ──┐
          │  JedisCluster │
          └──────┬──────┘
                  │
    ┌──────┬──────┼──────┬──────┐
    │      │      │      │      │
┌───▼──┐ ┌▼───┐ ┌▼───┐ ┌▼───┐ ┌▼───┐
│Node1 │ │Node2│ │Node3│ │Node4│ │Node5│
│主    │ │主   │ │主   │ │从  1│ │从  1│
│0-5460│ │5461-│ │10923│ │     │ │     │
│      │ │10922│ │-16383│ │     │ │     │
└──────┘ └─────┘ └─────┘ └─────┘ └─────┘
```

**核心概念：**

| 概念 | 说明 |
|------|------|
| **Slot（槽）** | 16384 个槽，`CRC16(key) % 16384` 决定 key 归属 |
| **节点** | 每个主节点负责一段连续的 slot 范围 |
| **从节点** | 每个主节点可以有 1-N 个从节点用于故障转移 |
| **Gossip 协议** | 节点间通过 Gossip 传播状态信息 |
| **MOVED 重定向** | 客户端请求的 slot 不在当前节点，节点返回 MOVED 指令 |
| **ASK 重定向** | 迁移期间，slot 正在移动，节点返回 ASK 指令 |

### 4.3.2 集群搭建实战

```bash
# 1. 修改每个节点的 redis.conf
# 端口 7000-7005
port 7000
cluster-enabled yes
cluster-config-file nodes-7000.conf
cluster-node-timeout 5000
appendonly yes
appendfsync everysec

# 2. 启动所有节点
redis-server /path/to/7000/redis.conf
redis-server /path/to/7001/redis.conf
# ...

# 3. 创建集群（3主3从）
redis-cli --cluster create \
    192.168.1.10:7000 192.168.1.10:7001 192.168.1.10:7002 \
    192.168.1.10:7003 192.168.1.10:7004 192.168.1.10:7005 \
    --cluster-replicas 1
# --cluster-replicas 1：每个主节点有1个从节点
```

**Java 客户端连接：**

```java
@Configuration
public class RedisConfig {
    @Bean
    public RedisConnectionFactory redisConnectionFactory() {
        RedisClusterConfiguration config = new RedisClusterConfiguration();
        config.clusterNode("192.168.1.10", 7000);
        config.clusterNode("192.168.1.10", 7001);
        config.clusterNode("192.168.1.10", 7002);
        // 只需要配置部分节点，客户端会自动发现所有节点
        
        return new LettuceConnectionFactory(config);
    }
}
```

### 4.3.3 集群扩缩容

**扩容（添加新节点）：**

```bash
# 1. 启动新节点（7006）
redis-server /path/to/7006/redis.conf

# 2. 将新节点加入集群
redis-cli --cluster add-node 192.168.1.10:7006 192.168.1.10:7000

# 3. 迁移 slot 到新节点
redis-cli --cluster reshard 192.168.1.10:7000
# 输入要迁移的 slot 数量（如 4096）
# 输入目标节点 ID（7006 的 node-id）
# 输入源节点 ID（all 或指定节点）
```

**缩容（移除节点）：**

```bash
# 1. 先将被移除节点的 slot 迁移到其他节点
redis-cli --cluster reshard 192.168.1.10:7006

# 2. 从集群中移除节点
redis-cli --cluster del-node 192.168.1.10:7000 <node-id>
```

**⚠️ 扩缩容注意事项：**
```
1. 迁移期间性能会下降（数据拷贝 + 网络传输）
2. 建议在低峰期操作
3. 一次迁移的 slot 数不要太多（建议每次 100-500 个 slot）
4. 确保有足够的内存余量（迁移期间数据量翻倍）
```

### 4.3.4 Cluster vs Sentinel 选型对比

| 对比维度 | Sentinel | Cluster |
|---------|----------|---------|
| 数据分片 | ❌ 所有节点存全量 | ✅ 自动分片 |
| 节点数上限 | 通常 1+N | 理论 1000，推荐 ≤ 200 |
| 自动故障转移 | ✅ | ✅ |
| 写入扩展性 | ❌ 主节点单点写 | ✅ 多主节点写 |
| 事务支持 | ✅ MULTI/EXEC | ❌ 仅支持 slot 内事务 |
| 多 key 操作 | ✅ 无限制 | ❌ 需要 hash tag |
| 运维复杂度 | 低 | 高 |
| 客户端兼容性 | 高 | 需要 Cluster 兼容客户端 |

**🔥 选型建议：**

- **数据量 < 20GB，QPS < 10万** → **Sentinel**（简单可靠，主从全量数据）
- **数据量 > 50GB，QPS > 20万** → **Cluster**（分片扩展，突破单机瓶颈）
- **不需要自动分片，只需要高可用** → **Sentinel**
- **未来数据量可能快速增长** → **Cluster**（避免后续重构）

### 4.3.5 Hash Tag：让相关的 key 落在同一个 slot

Cluster 下多 key 操作受限（如 `SINTER`、`MSET`），但通过 **Hash Tag** 可以解决：

```bash
# 不使用 Hash Tag：两个 key 可能在不同 slot
SINTER user:10001:friends user:10001:followers  # 可能报错 CROSSSLOT

# 使用 Hash Tag：{user10001} 部分计算 CRC16
SINTER {user10001}:friends {user10001}:followers  # 保证在同一 slot
```

**规则**：key 中 `{...}` 部分的内容作为 CRC16 的输入，相同的 `{}` 内容落在同一 slot。

```java
// Java 示例
String key1 = "{user10001}:friends";
String key2 = "{user10001}:followers";
// 这两个 key 一定在同一个 slot
```

**⚠️ 注意**：Hash Tag 使用过多会导致数据倾斜（所有数据集中到少数 slot）。按业务维度合理规划 Hash Tag 的粒度。

---

## 4.4 🔥 生产案例：脑裂问题与数据丢失

### 事故背景

某金融系统使用 Redis Sentinel 架构（1 主 2 从），部署在阿里云上。使用了主节点持久化 + 从节点只读的配置。

### 事故经过

```
14:00:00  云平台网络发生抖动，主节点和 Sentinel 之间网络中断 12 秒
14:00:02  Sentinel 判定主节点主观下线（SDOWN）
14:00:05  Sentinel 达到 quorum，开始选举新主节点
14:00:08  Sentinel 将从节点 Slave1 提升为新的主节点（新主）
           客户端开始写入新主节点
14:00:10  旧主节点网络恢复（以为自己还是主节点）
           客户端仍然有连接在旧主节点上继续写入！
            → 脑裂发生！两个主节点同时接受写入！
14:00:15  旧主节点发现自己已经是 SLAVE 角色
           旧主节点执行 SLAVEOF 新主节点
           旧主节点清空自己的数据，开始从新主节点全量复制
           → 旧主节点上 10 秒内写入的全部数据丢失！
```

**影响：**
- 10 秒内写入旧主节点的 **约 800 笔交易记录** 丢失
- 丢失数据涉及用户余额变动、订单创建等核心金融数据
- 最终通过业务日志 + 数据库 Binlog 追回，耗时 6 小时

### 根本原因分析

```
问题1：min-replicas-to-write = 0（默认）
  → 主节点即使没有从节点也接受写操作
  → 脑裂后旧主节点成为孤岛，仍然接受写入

问题2：min-replicas-max-lag = 10
   → 但 Sentinel 故障转移期间，旧主节点的从节点角色并未被更新
  → 导致 min-replicas 机制没有生效

问题3：没有配置哨兵 consistent 策略
  → 旧主节点恢复后直接 SLAVEOF 清空数据
  → 没有「保留节点」来恢复脑裂期间的数据
```

### 解决方案

**方案1（核心）：配置严格控制**

```bash
# 主节点配置：至少 1 个从节点在线且延迟 < 10 秒才接受写入
min-replicas-to-write 1
min-replicas-max-lag 10
```

**方案2：调整 Sentinel 配置**

```bash
# 增加判定下线的等待时间，减少误判
sentinel down-after-milliseconds mymaster 10000  # 从5秒改为10秒
sentinel failover-timeout mymaster 60000          # 从30秒改为60秒
```

**方案3：使用 WAIT 命令（强一致性场景）**

```java
// 写入主节点后等待至少1个从节点确认
public boolean writeWithWait(String key, String value) {
    redisTemplate.opsForValue().set(key, value);
    
    // 执行 WAIT 命令：等待1个从节点确认，超时1000ms
    RedisCallback<Long> callback = connection -> {
        return connection.waitForReplication(1, 1000);
    };
    Long replicas = redisTemplate.execute(callback);
    
    return replicas != null && replicas >= 1;
}
```

**方案4：应用层兜底（最后一道防线）**

```java
// 每次写入 Redis 的同时，写入一个本地队列
@Component
public class SafeRedisWriter {
    // 本地队列，保存最近写入的 key
    private final Queue<WriteLog> recentWrites = new ConcurrentLinkedQueue<>();
    
    public void safeSet(String key, String value) {
        redisTemplate.opsForValue().set(key, value);
        recentWrites.add(new WriteLog(key, value, System.currentTimeMillis()));
        
        // 只保留最近 5 分钟的写入
        long cutoff = System.currentTimeMillis() - 300_000;
        while (!recentWrites.isEmpty() && recentWrites.peek().timestamp < cutoff) {
            recentWrites.poll();
        }
    }
    
    // 在发现数据丢失时，可以从本地队列恢复
    public List<WriteLog> getRecentWrites(long afterTimestamp) {
        return recentWrites.stream()
            .filter(w -> w.timestamp > afterTimestamp)
            .collect(Collectors.toList());
    }
}
```

---

## 本章小结

1. **主从复制**：Redis 高可用的基础，但存在复制延迟和数据不一致的风险
2. **Sentinel**：自动故障转移方案，适合数据量不大但需要 HA 的场景
3. **Cluster**：自动分片 + 高可用的一体化方案，适合大数据量场景
4. **脑裂**：是高可用架构最常见的「隐形杀手」，必须通过 `min-replicas-to-write` + WAIT 命令 + 应用层兜底来防范
5. **架构选型**：数据量 < 50GB 选 Sentinel，> 50GB 选 Cluster

> **一句话记住**：高可用不是「不出故障」，而是「出故障后数据不丢」——脑裂比宕机更可怕。
