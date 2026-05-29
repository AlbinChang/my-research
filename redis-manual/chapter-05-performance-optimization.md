# 第五章：Redis 性能优化实战

> **本章核心**：系统掌握 Redis 性能问题的发现、诊断和优化方法，涵盖慢查询、Big Key、热点 Key、内存管理、Pipeline 批量操作等核心实战话题。每个问题都提供「发现 → 分析 → 解决」的完整链路。

---

## 5.1 慢查询诊断与优化

### 5.1.1 慢查询日志配置

Redis 慢查询日志记录执行时间超过阈值的命令：

```bash
# redis.conf 配置
slowlog-log-slower-than 10000   # 单位微秒，10000μs = 10ms
slowlog-max-len 128             # 最多保留多少条慢日志
```

**💡 合理阈值的设定**：
- 内网环境（延迟 < 1ms）：建议 10ms（10000μs）
- 跨机房（延迟 10-50ms）：建议 50ms（50000μs）
- 排查问题时可临时调低：`CONFIG SET slowlog-log-slower-than 1000`（1ms）

```bash
# 常用慢查询操作命令

# 查看最近的慢查询（最多128条）
SLOWLOG GET 10

# 返回示例：
# 1) 1) (integer) 14          # 日志唯一ID
#    2) (integer) 1704067200  # Unix时间戳
#    3) (integer) 45678       # 执行耗时（微秒）
#    4) "KEYS"                # 执行的命令
#    5) "user:*"              # 命令参数
#    6) "127.0.0.1:6379"      # 客户端地址

# 查看慢查询数量
SLOWLOG LEN

# 清空慢查询日志
SLOWLOG RESET
```

### 5.1.2 常见慢命令及优化方案

| 慢命令 | 时间复杂度 | 风险等级 | 优化方案 |
|--------|-----------|---------|---------|
| `KEYS *` | O(N) | 🔴 极高 | 用 `SCAN` 替代 |
| `HGETALL` 大 Hash | O(N) | 🟡 中 | 用 `HSCAN` 或拆分 |
| `LRANGE` 大 List | O(N) | 🟡 中 | 限制范围，或用 Sorted Set |
| `SMEMBERS` 大 Set | O(N) | 🟡 中 | 用 `SSCAN` 替代 |
| `ZRANGE` 大 ZSet | O(logN+M) | 🟢 低 | 控制返回数量 |
| `SORT` | O(N+M*logM) | 🟡 中 | 由应用层排序 |
| `MGET` 大量 key | O(N) | 🟢 低（批量） | 控制每批数量 |

**🚫 绝对禁止命令：KEYS**

```bash
# ❌ 生产事故之源：千万级 key 时 KEYS * 会阻塞 Redis 数十秒
# 期间所有请求排队等待，系统完全不可用

# ✅ 正确替代：SCAN 分批遍历
SCAN 0 MATCH user:* COUNT 100
# 返回：1) "153"  (下次迭代的游标)
#      2) "user:10001", "user:10002", ...
# 持续迭代直到游标返回 0
```

**Java 使用 SCAN 安全遍历：**

```java
public Set<String> scanKeys(String pattern, int count) {
    Set<String> keys = new HashSet<>();
    
    RedisCallback<Set<String>> callback = (connection) -> {
        Cursor<byte[]> cursor = connection.scan(ScanOptions.scanOptions()
            .match(pattern)
            .count(count)
            .build());
        
        while (cursor.hasNext()) {
            keys.add(new String(cursor.next(), StandardCharsets.UTF_8));
        }
        return keys;
    };
    
    return redisTemplate.execute(callback);
}
```

### 5.1.3 慢查询优化实战

**案例：某社交平台动态列表慢查询**

现象：用户首页 Feed 流加载需要 3-5 秒，Redis 监控显示大量 `LRANGE` 慢查询。

**原因分析：**
```bash
# 使用 List 存储用户时间线
LPUSH user:10001:feed "post_1" "post_2" ... "post_10000"
# 用户翻到第 500 页时执行
LRANGE user:10001:feed 4990 4999  # 需要遍历5000个元素
```

**优化方案：**
```bash
# 方案1：限制 List 长度（只保留最近500条）
LPUSH user:10001:feed "post_5001"
LTRIM user:10001:feed 0 499

# 方案2：使用 Sorted Set 替代 List，按时间戳排序
ZADD user:10001:feed_ts 1704067200 "post_5001"
ZREVRANGE user:10001:feed_ts 0 19 WITHSCORES  # 最近20条，O(logN+M)

# 方案3：做冷热分离
# 热数据（最近7天）用 Redis Sorted Set
# 冷数据（更早的）用 MySQL 或归档存储
```

---

## 5.2 Big Key 发现与治理

### 5.2.1 什么是 Big Key

Big Key 指单个 key 包含大量元素或占用大量内存：

| 类型 | Big Key 判定标准 | 典型风险 |
|------|----------------|---------|
| **String** | 值 > 10MB | 网络传输慢，序列化开销大 |
| **Hash** | field > 10000 或 整体 > 100MB | HGETALL 阻塞 |
| **List** | 元素 > 10000 | LRANGE/删除 阻塞 |
| **Set** | 元素 > 10000 | SMEMBERS 阻塞 |
| **Sorted Set** | 元素 > 10000 | ZRANGE 阻塞 |

### 5.2.2 Big Key 的危害

```
1. 网络阻塞：Big Key 传输占用带宽，每秒10MB的key会占满千兆网卡
2. 操作阻塞：HGETALL/SMEMBERS 等操作耗时数十秒
3. 内存不均：Cluster 下某个节点内存远高于其他节点（数据倾斜）
4. 删除阻塞：DEL 删除大 key 会阻塞主进程（需用 UNLINK）
```

### 5.2.3 发现 Big Key

**方法1：`redis-cli --bigkeys`（推荐）**

```bash
# 遍历所有 key，统计各类结构中最大的 key
redis-cli --bigkeys -h 127.0.0.1 -p 6379

# 输出示例：
# Biggest string found 'config:app_cache' has 523321 bytes
# Biggest hash  found 'user:session:online' has 1523327 fields
# Biggest set   found 'ip:blacklist' has 568912 members
```

**方法2：`MEMORY USAGE` 命令**

```bash
# 查看指定 key 的内存占用
MEMORY USAGE user:session:online
# (integer) 125829120  # 约 120MB
```

**方法3：`DEBUG OBJECT` 命令**

```bash
DEBUG OBJECT user:session:online
# Value at: 0x7f2e3c0fa4c0 refcount:1 encoding:hashtable serializedlength:523321 lru:12345 lru_seconds_idle:10
# serializedlength 表示序列化后的字节数
```

**方法4：定期扫描脚本**

```bash
# 使用 SCAN 配合 STRLEN/HLEN/LLEN 等命令检查
redis-cli --scan --pattern '*' | while read key; do
    type=$(redis-cli type "$key")
    case $type in
        "string")
            size=$(redis-cli strlen "$key")
            if [ "$size" -gt 10485760 ]; then
                echo "BIG STRING: $key ($size bytes)"
            fi
            ;;
        "hash")
            len=$(redis-cli hlen "$key")
            if [ "$len" -gt 10000 ]; then
                echo "BIG HASH: $key ($len fields)"
            fi
            ;;
    esac
done
```

### 5.2.4 Big Key 治理策略

**策略1：拆分（最常用）**

```java
// 将一个大 Hash 拆分为多个小 Hash
// 原始设计：一个 Hash 存储 100 万用户状态
// HSET user:status:all "user_10001" "online"  ← Big Key!

// 优化设计：按用户ID范围拆分（分桶）
public String getUserStatusKey(Long userId) {
    int bucket = (int)(userId / 10000);  // 每10000个用户一个桶
    return "user:status:bucket:" + bucket;
}

// 写入
String key = getUserStatusKey(userId);
redisTemplate.opsForHash().put(key, String.valueOf(userId), "online");
```

**策略2：压缩**

```java
// 对大 String 进行压缩后再存储
public void setCompressed(String key, String value) {
    try {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        GZIPOutputStream gzip = new GZIPOutputStream(baos);
        gzip.write(value.getBytes(StandardCharsets.UTF_8));
        gzip.close();
        byte[] compressed = baos.toByteArray();
        redisTemplate.opsForValue().set(key.getBytes(), compressed);
    } catch (IOException e) {
        throw new RuntimeException("GZIP压缩失败", e);
    }
}

public String getCompressed(String key) {
    byte[] compressed = redisTemplate.opsForValue().get(key.getBytes());
    if (compressed == null) return null;
    try {
        GZIPInputStream gzip = new GZIPInputStream(new ByteArrayInputStream(compressed));
        return new String(gzip.readAllBytes(), StandardCharsets.UTF_8);
    } catch (IOException e) {
        throw new RuntimeException("GZIP解压失败", e);
    }
}
```

**策略3：删除大 key 的正确姿势**

```bash
# ❌ 错误：直接 DEL（会阻塞主进程）
DEL user:session:online  # 如果这个 hash 有 100 万字段，可能阻塞 10 秒+

# ✅ 正确：使用 UNLINK（异步删除）
UNLINK user:session:online  # 后台线程删除，立即返回

# 或者在低峰期逐步删除
SCAN 0 MATCH user:session:bucket:* COUNT 100
# 然后分批 UNLINK
```

---

## 5.3 热点 Key 解决方案

### 5.3.1 热点 Key 的发现

热点 Key 指短时间内被大量请求访问的 key，极端情况下可达每秒数十万次访问。

**发现方法：**

```bash
# 方法1：Redis 6.x+ 开启 hotkey 检测（需要调整内核参数）
redis-cli --hotkeys

# 方法2：客户端收集统计
# 在 Jedis/Lettuce 的拦截器中记录 key 的访问频率

# 方法3：Redis Monitor 命令（谨慎使用，高并发下会消耗大量 CPU）
redis-cli monitor | grep "热门商品" | head -100
```

**Java 客户端热点统计：**

```java
@Component
public class HotKeyDetector {
    // 本地计数器（使用 ConcurrentHashMap）
    private final ConcurrentHashMap<String, AtomicLong> counter = new ConcurrentHashMap<>();
    
    public void recordAccess(String key) {
        counter.computeIfAbsent(key, k -> new AtomicLong()).incrementAndGet();
    }
    
    @Scheduled(fixedDelay = 60000) // 每分钟统计一次
    public void reportHotKeys() {
        List<Map.Entry<String, AtomicLong>> sorted = counter.entrySet().stream()
            .sorted((a, b) -> Long.compare(b.getValue().get(), a.getValue().get()))
            .limit(10)
            .collect(Collectors.toList());
        
        log.info("===== Hot Key TOP 10 =====");
        sorted.forEach(entry -> 
            log.info("Key: {}, AccessCount: {}", entry.getKey(), entry.getValue().get()));
        
        counter.clear(); // 清空计数器
    }
}
```

### 5.3.2 热点 Key 解决方案

**方案1：本地缓存（最有效）**

```java
// 对于读多写少的场景，将热点 key 缓存到本地
@Bean
public Cache<String, Object> caffeineCache() {
    return Caffeine.newBuilder()
        .maximumSize(10000)
        .expireAfterWrite(5, TimeUnit.SECONDS)  // 5秒过期
        .recordStats()
        .build();
}

public Object getWithLocalCache(String key) {
    // 先查本地缓存
    Object value = localCache.getIfPresent(key);
    if (value != null) {
        return value;
    }
    
    // 加锁防止缓存击穿（本地锁）
    synchronized (key.intern()) {
        value = localCache.getIfPresent(key);
        if (value != null) {
            return value;
        }
        
        // 查 Redis
        value = redisTemplate.opsForValue().get(key);
        if (value != null) {
            localCache.put(key, value);
        }
        return value;
    }
}
```

**方案2：副本扩散**

```java
// 将同一个热点 key 复制为多个副本，分散到不同 Redis 节点
// 原始 key: hot_product:10001
// 副本 key: hot_product:10001:0, hot_product:10001:1, ..., hot_product:10001:9

public class HotKeySharding {
    private static final int REPLICA_COUNT = 10;
    
    public String getShardedKey(String originalKey) {
        int replica = ThreadLocalRandom.current().nextInt(REPLICA_COUNT);
        return originalKey + ":" + replica;
    }
    
    public void setWithReplicas(String originalKey, Object value, long ttlSeconds) {
        for (int i = 0; i < REPLICA_COUNT; i++) {
            String shardKey = originalKey + ":" + i;
            redisTemplate.opsForValue().set(shardKey, value, ttlSeconds, TimeUnit.SECONDS);
        }
    }
    
    public Object getWithSharding(String originalKey) {
        String shardKey = getShardedKey(originalKey);
        return redisTemplate.opsForValue().get(shardKey);
    }
}
```

**方案3：读写分离 + 从节点负载均衡**

```java
@Configuration
public class RedisReadWriteConfig {
    @Bean
    public RedisTemplate<String, Object> redisTemplate() {
        // Lettuce 支持从节点读取
        LettuceClientConfiguration config = LettuceClientConfiguration.builder()
            .readFrom(ReadFrom.REPLICA_PREFERRED)  // 优先读取从节点
            .build();
        
        RedisStandaloneConfiguration server = new RedisStandaloneConfiguration();
        return new RedisTemplate<>(new LettuceConnectionFactory(server, config));
    }
}
```

**方案4：限流降级**

当热点 key 的访问超过阈值时，直接返回旧值或降级数据：

```java
@Component
public class HotKeyCircuitBreaker {
    private final RateLimiter rateLimiter = RateLimiter.create(5000); // 每秒5000个请求
    
    public Object getWithCircuitBreaker(String key) {
        if (rateLimiter.tryAcquire()) {
            return redisTemplate.opsForValue().get(key);
        } else {
            log.warn("热点Key被限流: {}", key);
            return localCache.getIfPresent(key); // 返回本地缓存（可能过期但可以接受）
        }
    }
}
```

---

## 5.4 内存淘汰策略

### 5.4.1 Redis 内存分析

```bash
# 查看内存使用情况
INFO memory

# 关键指标：
# used_memory: 1048576000        # 实际使用的内存（字节）
# used_memory_rss: 1200000000   # 操作系统看到的内存（含碎片）
# used_memory_peak: 1500000000  # 历史峰值
# mem_fragmentation_ratio: 1.14 # 内存碎片率
# maxmemory: 2147483648          # 配置的内存上限（2GB）
# maxmemory_policy: allkeys-lru # 淘汰策略
```

### 5.4.2 八种淘汰策略详解

| 策略 | 作用域 | 淘汰算法 | 适用场景 |
|------|--------|---------|---------|
| `noeviction` | - | 不淘汰，写入时报错 | 严禁数据丢失的纯缓存场景 |
| `allkeys-lru` | 所有 key | LRU | ✅ **最常用，通用缓存** |
| `allkeys-lfu` | 所有 key | LFU | 访问频率差异大的场景 |
| `allkeys-random` | 所有 key | 随机 | 缓存数据分布均匀 |
| `volatile-lru` | 带TTL的key | LRU | TTL明确的业务缓存 |
| `volatile-lfu` | 带TTL的key | LFU | TTL明确且频率差异大 |
| `volatile-random` | 带TTL的key | 随机 | TTL明确 |
| `volatile-ttl` | 带TTL的key | TTL最短优先 | 优先淘汰即将过期的 |

**🔥 最佳实践：**

```bash
# 通用缓存场景（最推荐）
maxmemory-policy allkeys-lru

# 业务数据有时效性（如Session）
maxmemory-policy volatile-ttl

# 完全不允许删除数据的场景
maxmemory-policy noeviction
#（但必须配合监控，一旦接近上限就报警）
```

**LRU 近似算法**：Redis 的 LRU 并非严格的 LRU，而是采样（sample）5-10 个 key 后淘汰最久未使用的那个：

```bash
# 调整 LRU 采样数（默认 5）
maxmemory-samples 10  # 采样越多越精确，但越耗CPU
```

### 5.4.3 内存优化技巧

```bash
# 1. 使用更短但可读的 key 名
# ❌ user:profile:information:1000001
# ✅ u:profile:1000001  （节省45%的key内存）

# 2. 设置合理的 TTL
EXPIRE session:abc123 1800  # 30分钟过期

# 3. 使用小编码（ziplist/intset）
# 4. 控制 key 的数量（一个 hash 替代多个 string）

# 5. 调整内存碎片（大版本重启时）
# 查看碎片率
INFO memory | grep fragmentation
# 如果 fragmentation_ratio > 1.5，建议重启
```

---

## 5.5 Pipeline 批量操作优化

### 5.5.1 批量读写性能对比

Pipeline 将多个命令打包一次性发送，大幅减少网络往返：

```bash
# 非 Pipeline：1000 次 SET = 1000 次网络往返
for i in {1..1000}; do
    redis-cli SET key:$i value:$i
done
# 耗时：约 500ms（同机房）

# Pipeline：1000 次 SET = 1 次网络往返
redis-cli --pipe <<EOF
SET key:1 value:1
SET key:2 value:2
...
SET key:1000 value:1000
EOF
# 耗时：约 5ms（提升 100 倍）
```

### 5.5.2 Java Pipeline 实现

```java
@Service
public class BatchService {
    @Autowired
    private RedisTemplate<String, Object> redisTemplate;
    
    /**
     * 批量写入（Pipeline 模式）
     */
    public void batchWrite(Map<String, Object> dataMap) {
        redisTemplate.executePipelined((RedisCallback<Object>) connection -> {
            dataMap.forEach((key, value) -> {
                byte[] rawKey = key.getBytes(StandardCharsets.UTF_8);
                byte[] rawValue = serialize(value);
                connection.set(rawKey, rawValue);
            });
            return null;
        });
    }
    
    /**
     * 批量读取
     */
    public List<Object> batchRead(List<String> keys) {
        List<Object> results = redisTemplate.executePipelined(
            (RedisCallback<Object>) connection -> {
                for (String key : keys) {
                    byte[] rawKey = key.getBytes(StandardCharsets.UTF_8);
                    connection.get(rawKey);
                }
                return null;
            });
        return results;
    }
    
    /**
     * Pipeline + 事务
     */
    public void batchWriteWithTransaction(Map<String, Object> dataMap) {
        redisTemplate.executePipelined(new SessionCallback<Object>() {
            @Override
            public <K, V> Object execute(RedisOperations<K, V> operations) {
                operations.multi();  // 开启事务
                dataMap.forEach((key, value) -> 
                    operations.opsForValue().set((K) key, (V) value));
                operations.exec();   // 提交事务
                return null;
            }
        });
    }
}
```

**⚠️ Pipeline 注意事项：**

```
1. Pipeline 打包命令数不要过多（建议 100-500 一批）
   过多会占用大量内存拼接请求，且单次 TCP 传输过大会导致网络分片

2. Pipeline 不保证原子性（和事务不同）
   中间某条命令失败不会影响其他命令的执行

3. Pipeline 机制在所有 Redis 版本中均可用；Redis 6.x+ 引入的 RESP3 协议主要改进是支持更丰富的数据类型返回（Map、Set、Push 等），与 Pipeline 机制无关
```

---

## 5.6 连接池最佳实践

### 5.6.1 连接池配置

```yaml
# application.yml (Lettuce 连接池)
spring:
  redis:
    lettuce:
      pool:
        max-active: 16        # 最大连接数（默认8）
        max-idle: 8           # 最大空闲连接
        min-idle: 4           # 最小空闲连接（预热）
        max-wait: -1ms        # 最大等待时间（-1=无限等待）
        time-between-eviction-runs: 100ms  # 空闲连接检查间隔
```

```java
@Configuration
public class RedisPoolConfig {
    @Bean
    public RedisConnectionFactory redisConnectionFactory() {
        RedisStandaloneConfiguration config = new RedisStandaloneConfiguration();
        config.setHostName("192.168.1.10");
        config.setPort(6379);
        config.setPassword("yourpassword");
        
        // 泛型连接池配置
        GenericObjectPoolConfig<?> poolConfig = new GenericObjectPoolConfig<>();
        poolConfig.setMaxTotal(32);        // 生产环境建议 16-32
        poolConfig.setMaxIdle(16);
        poolConfig.setMinIdle(8);
        poolConfig.setMaxWaitMillis(3000); // 获取连接超时3秒
        poolConfig.setTestOnBorrow(true);  // 获取连接时校验有效性
        poolConfig.setTestOnReturn(false);
        
        LettucePoolingClientConfiguration lettuceConfig = 
            LettucePoolingClientConfiguration.builder()
                .poolConfig(poolConfig)
                .commandTimeout(Duration.ofMillis(500))
                .build();
        
        return new LettuceConnectionFactory(config, lettuceConfig);
    }
}
```

### 5.6.2 连接池参数调优

**连接数计算公式：**

```
最大连接数 ≈ (业务期望 QPS × 单次操作耗时(秒)) + 冗余

举例：
期望 QPS = 50000
单次 GET 操作耗时 = 0.5ms = 0.0005s
计算结果 = 50000 × 0.0005 = 25 个连接
加上 50% 冗余 = 38 个连接
```

但注意：每个连接在 Redis 端都有一个对应的客户端对象，连接数过多（> 1000）会导致 Redis 端 CPU 开销增大（处理大量 TCP 连接的事件轮询）。

**🔥 推荐阈值：**

| 并发场景 | 推荐 max-active | 说明 |
|---------|----------------|------|
| 低并发（< 1000 QPS） | 8-16 | 默认配置即可 |
| 中等并发（1K-10K QPS） | 16-32 | 适当调大 |
| 高并发（10K-100K QPS） | 32-64 | 配合 Pipeline 效果更好 |
| 超高并发（> 100K QPS） | 64-128 | 需要关注 Redis 端连接数 |

### 5.6.3 常见连接问题排查

```bash
# 查看 Redis 当前的客户端连接
INFO clients
# connected_clients: 50
# maxclients: 10000
# client_recent_max_input_buffer: 20480
# client_recent_max_output_buffer: 0

# 列出所有客户端详情
CLIENT LIST
# id=12345 addr=192.168.1.100:54321 fd=8 name= age=15 idle=0 flags=N ...
# 重点关注：idle 时间长的连接可能是泄漏

# 杀掉异常连接
CLIENT KILL addr 192.168.1.100:54321

# 设置最大连接数
CONFIG SET maxclients 5000
```

**🔥 连接泄漏排查：**

```java
// 常见的连接泄漏场景：try-catch 中未释放连接

// ❌ 错误：获取连接后未归还
RedisConnection conn = null;
try {
    conn = redisTemplate.getConnectionFactory().getConnection();
    conn.set("key", "value".getBytes());
    // 忘记 finally 中 close()
} catch (Exception e) {
    // 异常时也没归还
}

// ✅ 正确：使用 RedisTemplate 的 API（自动管理连接）
redisTemplate.opsForValue().set("key", "value");

// 或者用 try-with-resources
// 但 Spring Data Redis 的 RedisTemplate 已经封装好了连接管理
// 直接使用 opsForXxx 即可，无需手动获取连接
```

---

## 本章小结

1. **慢查询**：开启 `slowlog-log-slower-than 10000`，用 `SCAN` 替代 `KEYS`，用 `HSCAN/SSCAN` 替代 `HGETALL/SMEMBERS`
2. **Big Key**：用 `--bigkeys` 扫描，用 `UNLINK` 异步删除，对大数据集进行分桶拆分
3. **热点 Key**：本地缓存 + 副本扩散 + 读写分离 + 限流降级，四管齐下
4. **内存淘汰**：`allkeys-lru` 是通用最佳选择，合理设置 `maxmemory` 避免 OOM
5. **Pipeline**：批量操作提升 100 倍性能，但注意每批 100-500 条为佳
6. **连接池**：根据 QPS 和延迟计算合理连接数，关注 `connected_clients` 指标

> **一句话记住**：性能优化的本质是「减少等待」——减少网络等待（Pipeline）、减少命令等待（慢查询优化）、减少锁等待（无锁设计）。
