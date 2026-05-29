# 第七章：分布式锁与并发控制

> **本章核心**：系统掌握分布式锁从简单实现到工业级方案的演进过程，理解 Redlock 的原理与争议，以及库存扣减、秒杀等场景下分布式锁的最佳实践。每个方案都有生产级代码和踩坑经验。

---

## 7.1 分布式锁的演进史

### 7.1.1 为什么需要分布式锁

在单机环境中，我们使用 `synchronized`、`ReentrantLock` 等 Java 锁机制来保证并发安全。但在分布式系统中，多个 JVM 进程之间的线程同步，必须使用分布式锁。

```
单机：
  [线程A] ←→ [synchronized] ←→ [共享资源]
  [线程B] ←→ [synchronized] ←→ [共享资源]
  ✓ JVM 内的锁可以互斥

分布式：
  [JVM1-线程A] ──→ 需要跨 JVM 互斥
  [JVM2-线程B] ──→ 需要跨 JVM 互斥
  [JVM3-线程C] ──→ 需要跨 JVM 互斥
                    ↓
              [分布式锁服务(Redis)]
```

**典型场景：**
- 库存扣减（防止超卖）
- 订单防重（防止重复下单）
- 分布式定时任务（只让一个节点执行）
- 资源互斥（如文件导出、报表生成）

### 7.1.2 第一版：SETNX + EXPIRE（基础方案）

```bash
# 加锁
SETNX lock:order:1001 "thread_A"  # 成功返回1，失败返回0
EXPIRE lock:order:1001 30          # 设置过期时间，防止死锁

# 解锁（需要确认是自己的锁）
DEL lock:order:1001
```

**问题：非原子操作**
```
SETNX 和 EXPIRE 是两个命令，中间可能崩溃：
  SETNX 成功 → 进程崩溃 → EXPIRE 没执行 → 锁永远不会释放 → 死锁！
```

### 7.1.3 第二版：SET NX EX（原子加锁）

Redis 2.8+ 引入了原子化的加锁命令：

```bash
# 原子加锁：NX=不存在时才设置，EX=过期时间（秒），PX=毫秒
SET lock:order:1001 "thread_A" NX EX 30
# 成功返回 OK，失败返回 nil
```

```java
public boolean tryLock(String key, String requestId, int expireSeconds) {
    Boolean result = redisTemplate.opsForValue()
        .setIfAbsent(key, requestId, expireSeconds, TimeUnit.SECONDS);
    return Boolean.TRUE.equals(result);
}
```

### 7.1.4 第三版：Lua 脚本原子解锁

```java
public boolean releaseLock(String key, String requestId) {
    // 使用 Lua 脚本确保「判断归属 → 删除」是原子的
    String lua = """
        if redis.call('GET', KEYS[1]) == ARGV[1] then
            return redis.call('DEL', KEYS[1])
        end
        return 0
        """;
    
    DefaultRedisScript<Long> script = new DefaultRedisScript<>();
    script.setScriptText(lua);
    script.setResultType(Long.class);
    
    Long result = redisTemplate.execute(script,
        Collections.singletonList(key), requestId);
    
    return Long.valueOf(1).equals(result);
}
```

**⚠️ 为什么解锁需要 LUA 脚本？**

不这样做的话，线程A可能误删线程B的锁：
```
线程A：GET lock → 返回 "thread_A"（锁是自己的，准备删除）
       线程A GC停顿了 10 秒...
       锁过期了...
线程B：SET lock NX → 成功拿到锁（"thread_B"）
线程A：DEL lock → 删了线程B的锁！

→ 没有 LUA 判断的解锁是不安全的！
```

### 7.1.5 第四版：看门狗（Watch Dog）防过期

```java
@Component
public class ReentrantRedisLock {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final long DEFAULT_EXPIRE = 30; // 30秒
    private final ConcurrentHashMap<String, ScheduledFuture<?>> watchdogFutures = new ConcurrentHashMap<>();
    
    /**
     * 加锁（带看门狗自动续期）
     */
    public boolean lock(String key, String requestId, long leaseTime, TimeUnit unit) {
        Boolean result = redisTemplate.opsForValue()
            .setIfAbsent(key, requestId, leaseTime, unit);
        
        if (Boolean.TRUE.equals(result)) {
            // 启动看门狗：每 leaseTime/3 秒续期一次
            ScheduledFuture<?> future = scheduledExecutor.scheduleAtFixedRate(() -> {
                String lua = """
                    if redis.call('GET', KEYS[1]) == ARGV[1] then
                        return redis.call('EXPIRE', KEYS[1], ARGV[2])
                    end
                    return 0
                    """;
                redisTemplate.execute(new DefaultRedisScript<>(lua, Long.class),
                    Collections.singletonList(key), requestId, 
                    String.valueOf(unit.toSeconds(leaseTime)));
            }, leaseTime / 3, leaseTime / 3, unit);
            
            watchdogFutures.put(key + ":" + requestId, future);
        }
        
        return Boolean.TRUE.equals(result);
    }
    
    /**
     * 解锁（同时停止看门狗）
     */
    public boolean unlock(String key, String requestId) {
        // 停止看门狗
        ScheduledFuture<?> future = watchdogFutures.remove(key + ":" + requestId);
        if (future != null) {
            future.cancel(false);
        }
        
        // 原子解锁
        return releaseLock(key, requestId);
    }
}
```

**为什么看门狗是必要的？**
```
不加看门狗：
  线程A 加锁（30秒过期）
  线程A 的业务执行了 40 秒... 
  30秒时锁过期了 → 线程B拿到了锁
  线程A 还在执行 → 两个线程同时操作 → 数据不一致！

加看门狗：
  线程A 加锁（30秒过期）
  看门狗每 10 秒续期一次
  即使业务执行 40 秒，锁一直在线程A手中
  线程A 执行完毕后解锁
```

### 7.1.6 分布式锁的完整实现

结合以上所有改进，一个生产级的分布式锁框架：

```java
@Component
public class DistributedLock {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private final ScheduledExecutorService scheduledExecutor = 
        Executors.newScheduledThreadPool(Runtime.getRuntime().availableProcessors());
    
    private static final String LOCK_PREFIX = "distlock:";
    private static final long DEFAULT_LEASE_TIME = 30;
    
    /**
     * 尝试获取锁
     */
    public boolean tryLock(String lockName, String requestId, long leaseTime, TimeUnit unit) {
        String key = LOCK_PREFIX + lockName;
        return Boolean.TRUE.equals(
            redisTemplate.opsForValue().setIfAbsent(key, requestId, leaseTime, unit));
    }
    
    /**
     * 阻塞式获取锁（带看门狗）
     */
    public LockResult lock(String lockName, String requestId, long waitTime, TimeUnit unit) {
        String key = LOCK_PREFIX + lockName;
        long deadline = System.currentTimeMillis() + unit.toMillis(waitTime);
        
        while (System.currentTimeMillis() < deadline) {
            Boolean acquired = redisTemplate.opsForValue()
                .setIfAbsent(key, requestId, DEFAULT_LEASE_TIME, TimeUnit.SECONDS);
            
            if (Boolean.TRUE.equals(acquired)) {
                // 启动看门狗
                ScheduledFuture<?> watchdog = startWatchdog(key, requestId);
                return new LockResult(true, key, requestId, watchdog);
            }
            
            // 等待重试（使用指数退避）
            try {
                Thread.sleep(Math.min(100, unit.toMillis(waitTime) / 10));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        
        return new LockResult(false, key, requestId, null);
    }
    
    /**
     * 解锁
     */
    public boolean unlock(LockResult lockResult) {
        if (lockResult == null || !lockResult.isAcquired()) {
            return false;
        }
        // 停止看门狗
        if (lockResult.getWatchdog() != null) {
            lockResult.getWatchdog().cancel(false);
        }
        // 原子解锁
        return releaseLock(lockResult.getKey(), lockResult.getRequestId());
    }
    
    private ScheduledFuture<?> startWatchdog(String key, String requestId) {
        return scheduledExecutor.scheduleAtFixedRate(() -> {
            String lua = """
                if redis.call('GET', KEYS[1]) == ARGV[1] then
                    redis.call('EXPIRE', KEYS[1], ARGV[2])
                end
                """;
            redisTemplate.execute(new DefaultRedisScript<>(lua, Long.class),
                Collections.singletonList(key), requestId, 
                String.valueOf(DEFAULT_LEASE_TIME));
        }, DEFAULT_LEASE_TIME / 3, DEFAULT_LEASE_TIME / 3, TimeUnit.SECONDS);
    }
    
    private boolean releaseLock(String key, String requestId) {
        String lua = """
            if redis.call('GET', KEYS[1]) == ARGV[1] then
                redis.call('DEL', KEYS[1])
                return 1
            end
            return 0
            """;
        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(lua, Long.class),
            Collections.singletonList(key), requestId);
        return Long.valueOf(1).equals(result);
    }
    
    @Data
    @AllArgsConstructor
    public static class LockResult {
        private boolean acquired;
        private String key;
        private String requestId;
        private ScheduledFuture<?> watchdog;
    }
}
```

---

## 7.2 Redlock 算法与争议

### 7.2.1 单点 Redis 锁的问题

上面的实现有一个根本问题：**Redis 是单点的**。

```
线程A 在 Master 上加锁成功：SET lock "thread_A" NX EX 30
Master 异步复制到 Slave 之前崩溃了...
Slave 升级为新的 Master
线程B 对新 Master 加锁成功：SET lock "thread_B" NX EX 30

→ 线程A 和 线程B 同时持有锁！
```

### 7.2.2 Redlock 算法原理

Redlock（Redis Distributed Lock）由 Redis 作者 antirez 提出，核心思想是「向多个独立的 Redis 实例请求锁，多数成功才算成功」：

```
┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐
│Redis1│  │Redis2│  │Redis3│  │Redis4│  │Redis5│
│独立   │  │独立   │  │独立   │  │独立   │  │独立   │
└──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘  └──┬───┘
   └─────┬──┘         │         └──┬────────┘
         │    N/2+1 成功 = 拿到锁   │
         └──────────┼──────────────┘
                    ↓
              [客户端获取到锁]
```

**加锁流程：**

```
1. 获取当前时间（毫秒）
2. 依次向 5 个独立的 Redis 实例请求锁（SET NX PX，超时时间很短）
3. 计算锁获取耗时 = 当前时间 - 步骤1的时间
4. 如果成功获取锁的实例数 ≥ N/2 + 1（即 ≥ 3），且总耗时 < 锁的 TTL
   → 认为锁获取成功
5. 锁的有效时间 = 原始 TTL - 获取耗时
6. 如果获取失败（不足多数），向所有实例发送解锁请求
```

### 7.2.3 Java 实现 Redlock

```java
@Component
public class Redlock {
    // 5个独立的Redis实例
    private final List<StringRedisTemplate> redisNodes;
    private static final int NODE_COUNT = 5;
    private static final int LOCK_TTL = 1000; // 1秒
    private static final int CLOCK_DRIFT_FACTOR = 3; // 时钟漂移系数
    
    public Redlock() {
        // 初始化5个独立的Redis连接
        this.redisNodes = Arrays.asList(
            createRedisTemplate("192.168.1.10", 6379),
            createRedisTemplate("192.168.1.11", 6379),
            createRedisTemplate("192.168.1.12", 6379),
            createRedisTemplate("192.168.1.13", 6379),
            createRedisTemplate("192.168.1.14", 6379)
        );
    }
    
    /**
     * Redlock 加锁
     */
    public boolean tryLock(String resource, String requestId) {
        long startTime = System.currentTimeMillis();
        int successCount = 0;
        int quorum = NODE_COUNT / 2 + 1;  // 需要至少3个节点成功
        
        // 向所有节点请求锁
        for (StringRedisTemplate node : redisNodes) {
            Boolean result = node.opsForValue()
                .setIfAbsent(resource, requestId, LOCK_TTL, TimeUnit.MILLISECONDS);
            if (Boolean.TRUE.equals(result)) {
                successCount++;
            }
            // 每个节点的请求超时时间要短（< TTL）
        }
        
        // 计算耗时
        long elapsed = System.currentTimeMillis() - startTime;
        long validity = LOCK_TTL - elapsed - (LOCK_TTL / CLOCK_DRIFT_FACTOR);
        
        // 判断是否获取成功
        if (successCount >= quorum && validity > 0) {
            return true;
        }
        
        // 失败：向所有节点解锁
        for (StringRedisTemplate node : redisNodes) {
            String lua = """
                if redis.call('GET', KEYS[1]) == ARGV[1] then
                    redis.call('DEL', KEYS[1])
                end
                """;
            node.execute(new DefaultRedisScript<>(lua, Long.class),
                Collections.singletonList(resource), requestId);
        }
        
        return false;
    }
}
```

### 7.2.4 Redlock 的争议

**Redlock 从诞生起就伴随着巨大争议。**

**支持方（antirez）：**
- Redlock 在大多数场景下提供安全的分布式锁
- 比单点锁有更高的可用性
- 实现简单，不需要引入其他组件

**反对方（Martin Kleppmann，《DDIA》作者）：**

Martin 提出了 Redlock 的几个根本性问题：

**问题1：时钟漂移（Clock Drift）**

```
Redlock 依赖于「所有节点的时钟是同步的」。
如果某个 Redis 节点的时钟发生跳跃（NTP同步、管理员手动修改等）：
  - 节点A: 时钟快了10秒
  - 其他节点: 正常
  - 客户端向节点A加锁（实际TTL少了10秒）
  - 锁提前过期 → 其他客户端拿到锁 → 不安全
```

**问题2：GC 停顿**

```
客户端拿到锁 → 发生 Full GC（停顿 5秒）→ 锁超时释放
→ 另一个客户端拿到锁
→ GC 恢复，第一个客户端认为自己还有锁
→ 两个客户端同时持有锁！

这是任何分布式锁都无法完全避免的，Redlock 也不例外。
```

**问题3：Redlock 的复杂性不值得**

```
基于 ZK 的锁实现更简单、更安全
（因为 ZK 有强一致性保证，不会出现脑裂）
```

### 7.2.5 🔥 最终建议

```
1. 如果只是防止重复执行（如定时任务、重复下单）：
   → 单点 Redis 锁 + 看门狗 已经足够
   → 因为最终有数据库兜底，Redis 锁只是第一道防线

2. 如果是操作物理资源（如文件互斥）、或真正要求互斥：
   → 使用 Redisson（红锁实现成熟）或 ZK 锁

3. 绝对不要自己实现 Redlock：
    → 使用 Redisson 的 RedissonMultiLock
   → 它已经处理了超时、重试、时钟漂移等边界情况

4. Redlock 并非银弹：
   → 它解决的是「Redis 主从切换导致的锁丢失」问题
   → 不解决「应用层 GC/暂停导致的锁超时」问题
```

---

## 7.3 分布式锁的最佳实践

### 7.3.1 锁的粒度控制

```java
// ❌ 错误：锁的粒度过粗
public void updateStock(Long productId, int quantity) {
    String lockKey = "lock:product";  // 所有商品共用一把锁！
    // 锁竞争激烈，性能极差
}

// ✅ 正确：按商品ID分片
public void updateStock(Long productId, int quantity) {
    String lockKey = "lock:product:" + productId;  // 每个商品独立锁
    // 锁的粒度细，并发能力高
}

// ✅ 更细粒度：按用户+商品组合
public void createOrder(Long userId, Long productId) {
    String lockKey = "lock:order:" + userId + ":" + productId;
    // 防止同一用户重复下单同一商品
}
```

### 7.3.2 可重入锁实现

```java
/**
 * 可重入锁：同一个线程可以多次获取同一把锁
 */
public boolean tryLockWithReentrant(String key, String requestId, int expireSeconds) {
    // 使用 Hash 结构：key = 锁名, field = 线程标识, value = 重入计数
    String lua = """
        local key = KEYS[1]
        local threadId = ARGV[1]
        local expire = ARGV[2]
        
        if redis.call('EXISTS', key) == 0 then
            redis.call('HINCRBY', key, threadId, 1)
            redis.call('EXPIRE', key, expire)
            return 1
        end
        
        if redis.call('HEXISTS', key, threadId) == 1 then
            redis.call('HINCRBY', key, threadId, 1)
            redis.call('EXPIRE', key, expire)
            return 1
        end
        
        return 0
        """;
    
    Long result = redisTemplate.execute(
        new DefaultRedisScript<>(lua, Long.class),
        Collections.singletonList(key), requestId, String.valueOf(expireSeconds));
    return Long.valueOf(1).equals(result);
}
```

### 7.3.3 阻塞 vs 非阻塞

| 模式 | 适用场景 | 实现 |
|------|---------|------|
| **非阻塞** | 一次性任务、不必须执行 | `tryLock()` 立即返回 |
| **阻塞（带超时）** | 用户请求、必须执行的业务 | `lock(waitTime)` 重试 |
| **自旋** | 短时间等待 | 循环尝试 + 指数退避 |

### 7.3.4 常见坑位总结

```bash
# 坑1：忘记设置过期时间 → 死锁
SETNX lock "thread_A"    # 成功后崩溃 → 锁永远不释放
# ✅ 必须 SET NX EX

# 坑2：解锁时没有判断持有者 → 误删别人的锁
DEL lock                  # 可能删的是别人刚获取的锁
# ✅ 必须 LUA 脚本判断

# 坑3：锁的过期时间小于业务时间 → 业务没执行完锁就释放
SET lock "thread_A" NX EX 1  # 1秒就过期，但业务需要5秒
# ✅ 使用看门狗自动续期

# 坑4：锁的粒度过大 → 性能瓶颈
lock:all_products          # 所有操作串行化
# ✅ 按业务维度拆分锁
```

---

## 7.4 🔥 生产案例：库存扣减超卖问题

### 背景

某电商平台使用 Redis 分布式锁来保证库存扣减的原子性。

### 第一版：有 Bug 的实现

```java
// 问题代码
public boolean deductStock(Long productId, int quantity) {
    String lockKey = "lock:stock:" + productId;
    String requestId = UUID.randomUUID().toString();
    
    try {
        // 加锁
        Boolean locked = redisTemplate.opsForValue()
            .setIfAbsent(lockKey, requestId, 10, TimeUnit.SECONDS);
        
        if (!Boolean.TRUE.equals(locked)) {
            return false;  // 拿不到锁直接返回失败
        }
        
        // 查库存
        Integer stock = (Integer) redisTemplate.opsForValue()
            .get("stock:" + productId);
        
        if (stock == null || stock < quantity) {
            return false;  // 库存不足
        }
        
        // 扣库存
        redisTemplate.opsForValue().decrement("stock:" + productId, quantity);
        
        return true;
    } finally {
        // 解锁
        redisTemplate.delete(lockKey);  // ❌ 没有判断持有者！
    }
}
```

**问题1**：解锁时没有判断是否是自己的锁
**问题2**：锁的粒度 + 业务操作不是原子的（查库存 → 扣库存 两步非原子）

### 第二版：优化实现

```java
public boolean deductStockWithLock(Long productId, int quantity) {
    String lockKey = "lock:stock:" + productId;
    String requestId = UUID.randomUUID().toString();
    
    try {
        Boolean locked = redisTemplate.opsForValue()
            .setIfAbsent(lockKey, requestId, 10, TimeUnit.SECONDS);
        if (!Boolean.TRUE.equals(locked)) {
            // 等待重试（阻塞模式）
            for (int i = 0; i < 50; i++) {
                Thread.sleep(50);
                locked = redisTemplate.opsForValue()
                    .setIfAbsent(lockKey, requestId, 10, TimeUnit.SECONDS);
                if (Boolean.TRUE.equals(locked)) break;
            }
            if (!Boolean.TRUE.equals(locked)) {
                return false;
            }
        }
        
        // 使用 Lua 脚本原子扣减
        String lua = """
            local stock = redis.call('GET', KEYS[1])
            if not stock then
                return -1  -- 商品不存在
            end
            if tonumber(stock) >= tonumber(ARGV[1]) then
                redis.call('DECRBY', KEYS[1], ARGV[1])
                return tonumber(stock) - tonumber(ARGV[1])
            end
            return -2  -- 库存不足
            """;
        
        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(lua, Long.class),
            Collections.singletonList("stock:" + productId),
            String.valueOf(quantity));
        
        return result >= 0;
    } finally {
        // 原子解锁
        String unlockLua = """
            if redis.call('GET', KEYS[1]) == ARGV[1] then
                redis.call('DEL', KEYS[1])
                return 1
            end
            return 0
            """;
        redisTemplate.execute(
            new DefaultRedisScript<>(unlockLua, Long.class),
            Collections.singletonList(lockKey), requestId);
    }
}
```

### 终极方案：Lua 脚本 + 乐观锁

```java
// 实际上，库存扣减完全不需要分布式锁！
// 使用 Lua 脚本 + Redis 单线程的原子性就够了

public long atomicDeductStock(Long productId, int quantity) {
    String lua = """
        local stock = redis.call('GET', KEYS[1])
        if not stock then
            return -1
        end
        if tonumber(stock) >= tonumber(ARGV[1]) then
            redis.call('DECRBY', KEYS[1], ARGV[1])
            return tonumber(stock) - tonumber(ARGV[1])
        end
        return -2
        """;
    
    Long result = redisTemplate.execute(
        new DefaultRedisScript<>(lua, Long.class),
        Collections.singletonList("stock:" + productId),
        String.valueOf(quantity));
    
    return result;
}
```

**💡 经验总结**：
> Redis 分布式锁是用来解决「多个客户端互斥访问」的问题。但如果只是对**单个 key** 的原子操作（如库存扣减），直接用 Lua 脚本或 INCRBY/DECRBY 就足够了 —— 不需要分布式锁。分布式锁适用于「跨多个 key 或跨系统」的互斥需求。

---

## 本章小结

1. **分布式锁的演进**：SETNX → SET NX EX → SET + LUA 解锁 → 看门狗续期 → Redlock
2. **Redlock 争议**：解决主从切换问题，但无法解决 GC 停顿和时钟漂移
3. **最佳实践**：细粒度锁 + 可重入 + 原子解锁 + 看门狗自动续期
4. **不要滥用锁**：单 key 操作用 Lua 脚本即可，不需要分布式锁
5. **生产建议**：优先使用 Redisson 现成的分布式锁实现，自己实现容易踩坑

> **一句话记住**：分布式锁是分布式系统中的万不得已的最后手段 —— 能用原子操作解决的问题，绝不用锁。
