# 第六章：缓存设计与常见问题

> **本章核心**：全面掌握缓存设计中的三大经典问题（穿透/击穿/雪崩）、缓存一致性难题，以及多级缓存架构的设计方案。每个问题都提供「问题复现 → 原因分析 → 解决方案」的完整链路，并配有生产事故复盘。

---

## 6.1 缓存穿透、缓存击穿、缓存雪崩

这是缓存领域的「三大经典问题」，每个开发者必须牢牢掌握。

### 6.1.1 缓存穿透

**定义**：请求的数据在缓存和数据库中都不存在，每次请求都直接打到数据库。

```
[用户] → [查询Redis] → 未命中（key不存在）
    → [查询数据库] → 未命中（数据不存在）
    → 不缓存结果，下次又来...
```

**恶意攻击场景**：攻击者使用不存在的 ID（如 `-1`、`999999999`）持续请求，导致数据库负载飙升。

**解决方案：**

**方案1：缓存空值（最简单有效）**

```java
@Component
public class CacheService {
    private static final long NULL_VALUE_TTL = 60; // 空值缓存60秒
    
    public Object getWithNullCache(String key) {
        // 1. 查缓存
        Object value = redisTemplate.opsForValue().get(key);
        if (value != null) {
            return value;
        }
        
        // 2. 缓存未命中，查数据库
        value = queryFromDatabase(key);
        
        // 3. 缓存结果（无论是否为空）
        if (value != null) {
            redisTemplate.opsForValue().set(key, value, 3600, TimeUnit.SECONDS);
        } else {
            // 缓存空值，防止穿透
            redisTemplate.opsForValue().set(key, "NULL", NULL_VALUE_TTL, TimeUnit.SECONDS);
        }
        
        return value;
    }
}
```

**方案2：布隆过滤器（Bloom Filter，大规模场景）**

```java
@Component
public class BloomFilterService {
    @Autowired
    private RedissonClient redissonClient;
    
    // 使用 Redisson 的布隆过滤器
    private RBloomFilter<String> bloomFilter;
    
    @PostConstruct
    public void init() {
        // 初始化：预计元素 1000 万，误判率 1%
        bloomFilter = redissonClient.getBloomFilter("bloom:user:id");
        bloomFilter.tryInit(10_000_000L, 0.01);
        
        // 加载所有存在的用户ID（可以从数据库加载）
        // loadAllUserIds();
    }
    
    public Object getUserById(Long userId) {
        String key = "user:" + userId;
        
        // 布隆过滤器判断：如果不存在则一定不存在
        if (!bloomFilter.contains(key)) {
            return null;  // 直接返回，无需查缓存和数据库
        }
        
        // 可能存在，继续查缓存
        return getWithNullCache(key);
    }
}
```

**方案3：参数校验（第一道防线）**

```java
public Object getOrderById(String orderId) {
    // 参数校验：ID格式不对直接拒绝
    if (orderId == null || !orderId.matches("^\\d{10}$")) {
        throw new IllegalArgumentException("无效的订单ID");
    }
    // ...
}
```

### 6.1.2 缓存击穿

**定义**：一个 **热点 key** 在缓存过期的瞬间，大量并发请求同时打到数据库。

```
[热点key "hot_product:1001" 在 T 时刻过期]
    T+0ms: 请求1 查到缓存未命中，开始查数据库
    T+1ms: 请求2 查到缓存未命中，也开始查数据库
    T+2ms: 请求3 同样查到缓存未命中，继续查数据库
    ...（5000个请求同时打到数据库）
    T+5000ms: Redis 写入新缓存，后续请求命中
```

**解决方案：**

**方案1：互斥锁（Mutex Lock）**

```java
public Object getWithMutex(String key) {
    // 1. 查缓存
    Object value = redisTemplate.opsForValue().get(key);
    if (value != null) {
        return value;
    }
    
    // 2. 缓存未命中，尝试获取分布式锁
    String lockKey = "lock:" + key;
    String lockValue = UUID.randomUUID().toString();
    
    Boolean locked = redisTemplate.opsForValue()
        .setIfAbsent(lockKey, lockValue, 10, TimeUnit.SECONDS);
    
    if (Boolean.TRUE.equals(locked)) {
        // 3. 拿到锁的线程查数据库
        try {
            // 双重检查（防止拿到锁之前已经被其他线程更新了缓存）
            value = redisTemplate.opsForValue().get(key);
            if (value != null) {
                return value;
            }
            
            value = queryFromDatabase(key);
            redisTemplate.opsForValue().set(key, value, 3600, TimeUnit.SECONDS);
            return value;
        } finally {
            // 释放锁（使用Lua脚本保证原子性）
            String lua = """
                if redis.call('GET', KEYS[1]) == ARGV[1] then
                    redis.call('DEL', KEYS[1])
                    return 1
                end
                return 0
                """;
            redisTemplate.execute(new DefaultRedisScript<>(lua, Long.class),
                Collections.singletonList(lockKey), lockValue);
        }
    } else {
        // 4. 没拿到锁的线程等待重试
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return getWithMutex(key);  // 递归重试
    }
}
```

**方案2：逻辑过期（不设置物理 TTL，由业务代码控制）**

```java
@Data
public class CacheWrapper<T> {
    private T data;
    private long expireTime;  // 逻辑过期时间戳
}

public T getWithLogicalExpire(String key) {
    // 1. 查缓存
    CacheWrapper<T> wrapper = (CacheWrapper<T>) redisTemplate.opsForValue().get(key);
    
    if (wrapper == null) {
        // 缓存不存在（可能是第一次加载）
        return loadAndCache(key);
    }
    
    // 2. 判断逻辑是否过期
    if (wrapper.getExpireTime() > System.currentTimeMillis()) {
        // 未过期，直接返回
        return wrapper.getData();
    }
    
    // 3. 已过期：异步刷新缓存，先返回旧数据（避免等待）
    asyncRefreshCache(key, wrapper);
    return wrapper.getData();  // 返回旧数据，不阻塞请求
}

private void asyncRefreshCache(String key, CacheWrapper<T> oldWrapper) {
    String lockKey = "lock:" + key;
    // 尝试获取锁，只让一个线程去刷新
    Boolean locked = redisTemplate.opsForValue()
        .setIfAbsent(lockKey, "1", 10, TimeUnit.SECONDS);
    
    if (Boolean.TRUE.equals(locked)) {
        CompletableFuture.runAsync(() -> {
            try {
                T newData = queryFromDatabase(key);
                CacheWrapper<T> newWrapper = new CacheWrapper<>();
                newWrapper.setData(newData);
                newWrapper.setExpireTime(System.currentTimeMillis() + 3600_000);
                redisTemplate.opsForValue().set(key, newWrapper);
            } finally {
                redisTemplate.delete(lockKey);
            }
        });
    }
}
```

### 6.1.3 缓存雪崩

**定义**：大量缓存 key **在同一时间集体过期**，导致请求全部落到数据库。

**与击穿的区别**：击穿是单个热点 key 过期，雪崩是大批 key 集中过期。

**解决方案：**

**方案1：过期时间分散（加随机偏移）**

```java
public void setWithRandomExpire(String key, Object value, long baseTtl) {
    // 在基础 TTL 上增加 10-30% 的随机偏移
    long randomOffset = (long) (baseTtl * 0.1 * ThreadLocalRandom.current().nextDouble()
        + baseTtl * 0.1);
    long ttl = baseTtl + randomOffset;
    redisTemplate.opsForValue().set(key, value, ttl, TimeUnit.SECONDS);
}
```

**方案2：互斥锁或队列**

与缓存击穿的互斥锁方案相同，但作用于所有 key 而不是单个热点 key。

**方案3：缓存预热 + 双缓存**

```java
// 主缓存（TTL 短，承载读取）
String primaryKey = "cache:v1:" + key;
// 备用缓存（TTL 长，主缓存过期时兜底）
String backupKey = "cache:backup:" + key;

public Object getWithBackup(String key) {
    // 先读主缓存
    Object value = redisTemplate.opsForValue().get("cache:v1:" + key);
    if (value != null) {
        return value;
    }
    
    // 主缓存未命中，读备用缓存
    value = redisTemplate.opsForValue().get("cache:backup:" + key);
    if (value != null) {
        // 异步刷新主缓存
        asyncRefreshPrimary(key);
        return value;
    }
    
    // 都未命中，查数据库
    return loadFromDatabase(key);
}
```

**方案4：高可用兜底（限流 + 降级）**

```java
@Component
public class CacheDegradationService {
    private final RateLimiter dbRateLimiter = RateLimiter.create(500); // 数据库QPS上限
    
    public Object getWithDegradation(String key) {
        // 1. 查缓存
        Object value = redisTemplate.opsForValue().get(key);
        if (value != null) {
            return value;
        }
        
        // 2. 限流：控制查库的速率
        if (dbRateLimiter.tryAcquire()) {
            value = queryFromDatabase(key);
            if (value != null) {
                redisTemplate.opsForValue().set(key, value, 300 + randomOffset(), TimeUnit.SECONDS);
            }
            return value;
        } else {
            // 3. 降级：返回旧数据或默认值
            log.warn("缓存雪崩降级, key: {}", key);
            return getDefaultValue(key);
        }
    }
}
```

---

## 6.2 缓存一致性方案

### 6.2.1 问题分析

缓存一致性是指 **缓存中的数据与数据库中的数据保持一致**。这个问题在「先写数据库，再更新缓存」或「先删缓存，再写数据库」的场景中一直存在。

**经典问题：写数据库+更新缓存的并发冲突**

```
线程A: 写数据库（新值=100）
线程B: 写数据库（新值=200）
线程B: 更新缓存（200）  ← 先完成
线程A: 更新缓存（100）  ← 后完成，覆盖了B的更新
最终缓存=100，数据库=200 → 不一致！
```

### 6.2.2 方案对比

| 方案 | 一致性强度 | 复杂度 | 适用场景 |
|------|-----------|-------|---------|
| Cache Aside（旁路缓存） | 最终一致 | 低 | ✅ 通用场景 |
| 延迟双删 | 最终一致 | 中 | 对一致性有中等要求 |
| 读写锁 | 强一致 | 高 | 读多写少，要求强一致 |
| Canal + MQ 异步同步 | 最终一致 | 高 | 数据异构场景 |

### 6.2.3 方案一：Cache Aside Pattern（推荐）

这是最经典的缓存模式，核心思想：**读的时候先读缓存，写的时候先写数据库再删缓存**。

```java
@Service
public class CacheAsideService {
    
    // 读：先查缓存，再查数据库，最后回填缓存
    public Object read(String key) {
        Object value = redisTemplate.opsForValue().get(key);
        if (value != null) {
            return value;
        }
        value = queryFromDatabase(key);
        if (value != null) {
            redisTemplate.opsForValue().set(key, value, 3600, TimeUnit.SECONDS);
        }
        return value;
    }
    
    // 写：先写数据库，再删缓存（不是更新缓存！）
    @Transactional
    public void write(String key, Object newValue) {
        // 1. 先更新数据库
        updateDatabase(key, newValue);
        
        // 2. 删除缓存（下次读时会重新加载）
        redisTemplate.delete(key);
    }
}
```

**💡 为什么是「删缓存」而不是「更新缓存」？**

- 删缓存实现简单，不会有并发写入覆盖的 race condition
- 删缓存是幂等的，删多少次结果一样
- 「懒加载」策略：缓存直到被「读」时才重建，不会浪费资源更新不常用的数据

### 6.2.4 方案二：延迟双删

在 Cache Aside 的基础上，增加一次延迟删除，解决「删缓存 → 写数据库 → 另一个线程读旧数据写缓存」的问题：

```java
@Transactional
public void writeWithDelayedDelete(String key, Object newValue) {
    // 1. 先删缓存（第一次删除）
    redisTemplate.delete(key);
    
    // 2. 更新数据库
    updateDatabase(key, newValue);
    
    // 3. 延迟 N 毫秒再次删除缓存
    //    目的是让并发读取的线程在此期间把旧数据写入缓存后，再次被删除
    Executors.newSingleThreadScheduledExecutor().schedule(() -> {
        redisTemplate.delete(key);
    }, 500, TimeUnit.MILLISECONDS);
}
```

**⚠️ 延迟时间的设置**：延迟时间需要大于「读数据库 + 写缓存」的总耗时。通常 500ms-1s 可以覆盖 99% 的场景。

### 6.2.5 方案三：基于 Binlog 的最终一致性（Canal）

使用阿里巴巴 Canal 监听 MySQL Binlog，将数据变更自动同步到 Redis：

```
[应用] → 写 MySQL
              ↓ (MySQL Binlog)
         [Canal] → 解析 Binlog
              ↓
         [MQ] → 异步消费
              ↓
         [消费者] → 更新 Redis
```

**优点**：
- 完全解耦，应用层只需关心数据库写入
- Binlog 顺序保证，不会乱序
- 适合数据异构（如从 MySQL 同步到 Redis、ES 等多个存储）

**缺点**：
- 引入 Canal + MQ，运维复杂度高
- 有秒级延迟，不是实时同步

### 6.2.6 🔥 最终推荐：Cache Aside + 可接受的短暂不一致

```
对于 90% 的业务系统，Cache Aside 已经足够。

关键认知：缓存一致性 ≠ 强一致性

- 缓存允许短时间的「最终一致」（通常 1-5 秒）
- 如果业务真的要求强一致 → 不要用缓存
- 如果业务要求严格有序 → 使用数据库
- 如果系统需要高并发 → 接受最终一致，用 Cache Aside
```

---

## 6.3 多级缓存架构

### 6.3.1 四级缓存模型

```
[用户请求]
     ↓ 第1级：CDN（静态资源）
     ↓ 第2级：Nginx Lua 缓存（动态页面/API）
     ↓ 第3级：本地缓存（Caffeine/Guava）
     ↓ 第4级：Redis 集群
     ↓ 第5级：数据库
```

**各级缓存的特性：**

| 级别 | 延迟 | QPS 容量 | 存储容量 | 成本 |
|------|------|---------|---------|------|
| CDN | ~10ms | 10M+ | GB | 高 |
| Nginx Lua | ~1ms | 100K+ | MB | 低 |
| 本地缓存 | ~0.01ms | 500K+ | MB | 极低 |
| Redis | ~1ms | 100K+ | TB | 中 |
| 数据库 | ~10ms | 10K | 无限 | 高 |

### 6.3.2 多级缓存实现

```java
@Component
public class MultiLevelCacheService {
    // 第3级：Caffeine 本地缓存
    private final Cache<String, Object> localCache;
    
    // 第4级：Redis 远程缓存
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    public MultiLevelCacheService() {
        this.localCache = Caffeine.newBuilder()
            .maximumSize(10000)
            .expireAfterWrite(5, TimeUnit.SECONDS)  // 5秒过期
            .recordStats()
            .build();
    }
    
    public Object get(String key) {
        // 1. 查本地缓存
        Object localValue = localCache.getIfPresent(key);
        if (localValue != null) {
            return localValue;
        }
        
        // 2. 查 Redis
        String redisValue = redisTemplate.opsForValue().get(key);
        if (redisValue != null) {
            // 回填本地缓存
            localCache.put(key, redisValue);
            return redisValue;
        }
        
        // 3. 查数据库（实际项目中需要加互斥锁防止击穿）
        Object dbValue = queryFromDatabase(key);
        if (dbValue != null) {
            // 回填 Redis
            redisTemplate.opsForValue().set(key, serialize(dbValue), 
                300 + randomOffset(), TimeUnit.SECONDS);
            // 回填本地缓存
            localCache.put(key, dbValue);
        }
        
        return dbValue;
    }
    
    /**
     * 写入时，需要逐级失效
     */
    public void evict(String key) {
        localCache.invalidate(key);   // 失效本地缓存
        redisTemplate.delete(key);    // 删除Redis缓存
    }
}
```

**🔥 多级缓存的核心原则：**

1. **TTL 逐级递减**：CDN（1h）> Redis（5-10min）> 本地缓存（1-5s）
2. **更新时逐级失效**：写操作必须让所有级别的缓存失效
3. **监控命中率**：每级缓存的命中率都要监控，命中率突降说明有问题

---

## 6.4 🔥 生产案例：双写不一致引发的事故

### 事故背景

某电商平台的商品详情页缓存，采用「更新数据库 + 更新缓存」的方案（不是删缓存）。

### 事故经过

```
时间线：

10:00:00  运营人员修改商品A的价格（100元 → 80元）
           系统执行：
           ① UPDATE products SET price=80 WHERE id=1001;
           ② Redis SET cache:product:1001 '{"price":80}';

           正常情况下一切正常。

10:00:01  并发请求来了：
           请求X（用户下单）：读取商品A信息
           请求Y（库存扣减）：更新商品A的库存

           请求Y的执行序列：
           ① UPDATE products SET stock=stock-1 WHERE id=1001;  // 库存从100→99
           ② Redis SET cache:product:1001 '{"price":80,"stock":99}'  // 更新缓存

           但！请求X和Y交叉执行：
           [时间线]
           T0: Y执行①写入数据库（stock=99）
           T1: X执行①从数据库读取（price=80, stock=99）→ 正确
           T2: X执行②序列化后写入Redis（price=80, stock=99）→ 正确
           T3: Y执行②更新Redis（price=80, stock=99）→ 结果也是正确的

           这次没出事，但换个交叉顺序呢？

10:00:02  更糟糕的交叉：
           请求P（更新库存）：
           ① UPDATE products SET stock=100 WHERE id=1001;
           ② Redis SET cache:product:1001 '{"price":80,"stock":100}';

           请求Q（修改标题）：
           ① UPDATE products SET title="新标题" WHERE id=1001;
           ② Redis SET cache:product:1001 '{"price":80,"title":"新标题"}';

           如果交叉执行：
           T0: P执行①（数据库stock=100）
           T1: Q执行①（数据库title="新标题"）
           T2: Q执行②（缓存：price=80, title="新标题"）
           T3: P执行②（缓存：price=80, stock=100）
           → 缓存中丢失了 title 的更新！
```

这个案例表面上是「并发时序」问题，本质上是「缓存应该用删除而不是更新」的问题。

**后果**：
- 商品标题不一致持续了 30 分钟（缓存 TTL 为 30 分钟）
- 用户看到的是旧标题，但实际数据库已更新
- 造成运营投诉 + 用户体验下降

### 事故根因

```
1. 使用了「更新缓存」而非「删除缓存」
   → 并发更新会互相覆盖，导致部分字段丢失

2. 没有使用 Canal 等 Binlog 同步机制
   → 应用层双写在并发下必然不一致

3. 缓存 TTL 过长（30分钟）
   → 一旦不一致，需要 30 分钟才能自动修复
```

### 改进方案

```java
// 改进1：写数据库后删缓存（Cache Aside）
@Transactional
public void updateProduct(Product product) {
    // 1. 更新数据库
    productMapper.updateById(product);
    
    // 2. 删缓存（下次读取时重建）
    redisTemplate.delete("cache:product:" + product.getId());
}

// 改进2：即使使用 Cache Aside，也设置较短的 TTL 作为保底
redisTemplate.opsForValue().set(key, value, 600, TimeUnit.SECONDS); // 10分钟过期

// 改进3：对于极端重要数据，用 Canal 同步
// 见 6.2.5 节的 Binlog 方案
```

### 经验总结

```
🔥 缓存一致性的三条铁律：

1. 写操作：先写数据库，再删缓存（不是更新缓存！）
2. 读操作：先读缓存，未命中则读数据库并回写缓存
3. TTL 是兜底：哪怕逻辑上没删缓存，TTL 过期也会自动修复

例外情况：
- 如果数据更新非常频繁（如阅读数），用 INCR 直接操作 Redis
- 如果读多写少且一致要求高，用读写锁
- 如果写多读少，考虑直接不用缓存
```

---

## 本章小结

1. **缓存穿透**：布隆过滤器 + 缓存空值 + 参数校验，三层防御
2. **缓存击穿**：互斥锁 + 逻辑过期，两种方案各有优劣
3. **缓存雪崩**：TTL 随机化 + 双缓存 + 限流降级，多管齐下
4. **缓存一致性**：Cache Aside（写DB删缓存）是最实用的方案，不要追求完美一致
5. **多级缓存**：CDN → Nginx → 本地 → Redis → DB，TTL 逐级递减
6. **核心教训**：永远「删缓存」而不是「更新缓存」——删缓存是幂等的、无状态的

> **一句话记住**：缓存设计最大的敌人不是性能，是不一致。而最大的不一致来源，是「更新缓存」这四个字。
