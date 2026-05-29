# 第十章：Redisson 实战与高级特性

> **本章核心**：Redisson 是 Java 生态中最强大的 Redis 客户端和分布式工具集。本章深入讲解 Redisson 的核心功能，包括分布式锁、分布式集合、布隆过滤器、限流器和延迟队列等高级特性。

---

## 10.1 Redisson 核心功能概览

### 10.1.1 简介

Redisson 不只是一个 Redis 客户端，更是一个基于 Redis 的 **Java 分布式工具集**。它提供了数十种分布式数据结构和服务的实现：

```
分布式对象     分布式集合    分布式锁     分布式服务
  ┌────────┐   ┌────────┐   ┌───────┐   ┌────────┐
  │Bucket │   │Map     │   │Lock   │   │Executor│
  │Atomic │   │Set     │   │RLock  │   │Schedule│
  │Bloom  │   │Queue   │   │RWLock │   │Remote  │
  │Rate   │   │Deque   │   │Count  │   │Call    │
  │Limiter│   │List    │   │Down   │   │Service │
  └────────┘   └────────┘   └───────┘   └────────┘
```

### 10.1.2 集成配置

```xml
<!-- Maven 依赖 -->
<dependency>
    <groupId>org.redisson</groupId>
    <artifactId>redisson-spring-boot-starter</artifactId>
    <version>3.27.0</version>
</dependency>
```

```yaml
# application.yml
spring:
  redis:
    redisson:
      file: classpath:redisson.yaml
```

```yaml
# redisson.yaml 配置示例
singleServerConfig:
  address: "redis://192.168.1.10:6379"
  password: yourpassword
  connectionPoolSize: 32
  connectionMinimumIdleSize: 8
  idleConnectionTimeout: 10000
  connectTimeout: 5000
  timeout: 3000
  retryAttempts: 3
  retryInterval: 1500

# 集群模式
# clusterServersConfig:
#   nodeAddresses:
#     - "redis://192.168.1.10:7000"
#     - "redis://192.168.1.11:7001"
#     - "redis://192.168.1.12:7002"
#   scanInterval: 1000
```

```java
// Java Config 方式
@Configuration
public class RedissonConfig {
    @Bean
    public RedissonClient redissonClient() {
        Config config = new Config();
        config.useSingleServer()
            .setAddress("redis://192.168.1.10:6379")
            .setPassword("yourpassword")
            .setConnectionPoolSize(32)
            .setConnectionMinimumIdleSize(8);
        
        return Redisson.create(config);
    }
}
```

---

## 10.2 分布式锁的 Redisson 实现

### 10.2.1 可重入锁

```java
@Service
public class RedissonLockService {
    @Autowired
    private RedissonClient redissonClient;
    
    public void doWithLock(String resourceKey) {
        RLock lock = redissonClient.getLock(resourceKey);
        
        try {
            // 加锁（等待超时30秒，自动续期30秒）
            if (lock.tryLock(30, 30, TimeUnit.SECONDS)) {
                try {
                    // 业务逻辑
                    System.out.println("执行业务: " + resourceKey);
                } finally {
                    lock.unlock();  // 手动解锁
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```

**Redisson 锁的核心优势**：
- ✅ **自动看门狗**：默认每 10 秒续期一次（leaseTime 传 -1 即可开启）
- ✅ **可重入**：同一线程可多次获取同一把锁
- ✅ **自动解锁**：持有锁的线程崩溃后，锁自动释放（30 秒后）
- ✅ **等待中断**：支持 `tryLock` 超时设置

### 10.2.2 公平锁

```java
// Fair Lock：按照请求顺序获取锁（先进先出）
RLock fairLock = redissonClient.getFairLock("fair:resource");
fairLock.lock();
try {
    // 业务逻辑
} finally {
    fairLock.unlock();
}
```

### 10.2.3 读写锁

```java
@Autowired
private RedissonClient redissonClient;

public void handleReadWrite() {
    RReadWriteLock rwLock = redissonClient.getReadWriteLock("cache:product:1001");
    RLock readLock = rwLock.readLock();
    RLock writeLock = rwLock.writeLock();
    
    // 读操作（可并发读）
    readLock.lock();
    try {
        Object value = redisTemplate.opsForValue().get("product:1001");
        return value;
    } finally {
        readLock.unlock();
    }
    
    // 写操作（独占写）
    writeLock.lock();
    try {
        redisTemplate.opsForValue().set("product:1001", newValue);
    } finally {
        writeLock.unlock();
    }
}
```

### 10.2.4 红锁（RedLock）

```java
@Configuration
public class RedlockConfig {
    @Bean
    public RedissonClient redissonNode1() {
        Config config = new Config();
        config.useSingleServer().setAddress("redis://node1:6379");
        return Redisson.create(config);
    }
    // ... node2, node3, node4, node5
    
    @Bean
    public RedissonMultiLock redLock(RedissonClient... nodes) {
        RLock[] locks = Arrays.stream(nodes)
            .map(client -> client.getLock("redlock:resource"))
            .toArray(RLock[]::new);
        return new RedissonMultiLock(locks);
    }
}

// 使用 RedLock
@Service
public class RedlockService {
    @Autowired
    private RedissonRedLock redLock;
    
    public void criticalSection() {
        if (redLock.tryLock(5, 30, TimeUnit.SECONDS)) {
            try {
                // 真正互斥的临界区
            } finally {
                redLock.unlock();
            }
        }
    }
}
```

---

## 10.3 分布式集合与布隆过滤器

### 10.3.1 RMap（分布式 Map）

```java
@Service
public class DistributedMapService {
    @Autowired
    private RedissonClient redissonClient;
    
    /**
     * 使用 RMap 替代 Hash 操作
     */
    public void useRMap() {
        RMap<String, User> userMap = redissonClient.getMap("users");
        
        // 写入（自动序列化）
        userMap.put("user:1001", new User("张三", 25));
        userMap.put("user:1002", new User("李四", 30));
        
        // 读取
        User user = userMap.get("user:1001");
        
        // 本地缓存（RMap 内置 MapCache，减少网络IO）
        RMapCache<String, User> cachedMap = redissonClient.getMapCache("cached:users");
        cachedMap.put("user:1001", user, 10, TimeUnit.MINUTES);  // 带 TTL
        
        // 原子操作（类似 HINCRBY）
        userMap.addAndGet("user:1001:score", 10);  // 字段原子增加
    }
}
```

### 10.3.2 RSet 与 RScoredSortedSet

```java
// RSet（分布式 Set）
RSet<String> onlineUsers = redissonClient.getSet("online:users");
onlineUsers.add("user_1001");
onlineUsers.add("user_1002");
boolean exists = onlineUsers.contains("user_1001");

// RScoredSortedSet（分布式 ZSet）
RScoredSortedSet<String> rank = redissonClient.getScoredSortedSet("rank:live");
rank.add(100, "anchor_1001");
rank.add(200, "anchor_1002");
Collection<String> top10 = rank.valueRangeReversed(0, 9);  // TOP 10
```

### 10.3.3 RBloomFilter（布隆过滤器）

```java
@Component
public class BloomFilterManager {
    @Autowired
    private RedissonClient redissonClient;
    
    private RBloomFilter<String> userBloomFilter;
    
    @PostConstruct
    public void init() {
        // 创建布隆过滤器
        // expectedInsertions: 预计插入量（1000万）
        // falseProbability: 期望误判率（1%）
        userBloomFilter = redissonClient.getBloomFilter("bloom:users");
        userBloomFilter.tryInit(10_000_000L, 0.01);
        
        // 预热：从数据库加载所有用户ID
        // loadAllUserIds();
    }
    
    /**
     * 注册用户ID
     */
    public void addUserId(String userId) {
        userBloomFilter.add(userId);
    }
    
    /**
     * 判断用户ID是否存在
     * @return true=可能存在（有1%概率误判），false=一定不存在
     */
    public boolean mightContain(String userId) {
        return userBloomFilter.contains(userId);
    }
    
    /**
     * 缓存穿透防护示例
     */
    public User getUserById(String userId) {
        // 1. 布隆过滤器判断
        if (!mightContain(userId)) {
            return null;  // 一定不存在，直接返回
        }
        
        // 2. 可能存在，查缓存
        User user = getFromCache(userId);
        if (user != null) {
            return user;
        }
        
        // 3. 缓存未命中，查数据库
        // （即使到这里，1%的误判率也只是额外查一次数据库）
        return getFromDatabase(userId);
    }
}
```

**布隆过滤器内存计算：**
```
公式：m = -n * ln(p) / (ln2)^2

n = 1000万（预计插入量）
p = 0.01（1%误判率）

计算结果：m ≈ 95,426,121 bit ≈ 11.4 MB

所以：11.4MB 内存就可以判断 1000万 用户ID是否存在！
```

---

## 10.4 RRateLimiter 限流器

### 10.4.1 基本使用

```java
@Component
public class RedissonRateLimiter {
    @Autowired
    private RedissonClient redissonClient;
    
    /**
     * 创建令牌桶限流器
     */
    public boolean tryAcquire(String key, long permits, long rate, long rateInterval) {
        RRateLimiter rateLimiter = redissonClient.getRateLimiter(key);
        
        // 初始化：每10秒生成10个令牌（即 1 QPS）
        rateLimiter.trySetRate(RateType.OVERALL, rate, rateInterval, RateIntervalUnit.SECONDS);
        
        return rateLimiter.tryAcquire(permits);
    }
    
    /**
     * API限流示例
     */
    public boolean allowApiCall(String apiKey) {
        String rateLimiterKey = "ratelimit:api:" + apiKey;
        RRateLimiter rateLimiter = redissonClient.getRateLimiter(rateLimiterKey);
        
        // 每个 API 每秒最多 100 次调用
        rateLimiter.trySetRate(RateType.PER_CLIENT, 100, 1, RateIntervalUnit.SECONDS);
        
        return rateLimiter.tryAcquire();
    }
}
```

---

## 10.5 延迟队列实现

### 10.5.1 基于 RDelayedQueue

```java
@Component
public class RedissonDelayQueue {
    @Autowired
    private RedissonClient redissonClient;
    
    private RBlockingQueue<String> blockingQueue;
    private RDelayedQueue<String> delayedQueue;
    
    @PostConstruct
    public void init() {
        // 创建阻塞队列
        blockingQueue = redissonClient.getBlockingQueue("delay:queue");
        
        // 包装为延迟队列
        delayedQueue = redissonClient.getDelayedQueue(blockingQueue);
    }
    
    /**
     * 添加延迟任务
     */
    public void addDelayedTask(String taskId, long delay, TimeUnit unit) {
        delayedQueue.offer(taskId, delay, unit);
        log.info("添加延迟任务: {}, 延迟: {} {}", taskId, delay, unit);
    }
    
    /**
     * 消费线程
     */
    @Component
    public static class DelayConsumer {
        @Autowired
        private RedissonClient redissonClient;
        
        @PostConstruct
        public void start() {
            Executors.newSingleThreadExecutor().submit(() -> {
                RBlockingQueue<String> queue = redissonClient.getBlockingQueue("delay:queue");
                
                while (true) {
                    try {
                        // 阻塞获取（任务到期才出队）
                        String taskId = queue.take();
                        processTask(taskId);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            });
        }
        
        private void processTask(String taskId) {
            log.info("执行延迟任务: {}", taskId);
            // 业务处理
        }
    }
}
```

### 10.5.2 实战：订单超时取消

```java
@Service
public class OrderTimeoutService {
    @Autowired
    private RedissonDelayQueue delayQueue;
    @Autowired
    private OrderRepository orderRepository;
    
    /**
     * 创建订单时注册超时取消任务
     */
    @Transactional
    public Order createOrder(Order order) {
        // 1. 保存订单到数据库
        order.setStatus(OrderStatus.CREATED);
        orderRepository.save(order);
        
        // 2. 添加延迟任务（30分钟后自动取消）
        delayQueue.addDelayedTask(
            "order:timeout:" + order.getId(),
            30, TimeUnit.MINUTES
        );
        
        return order;
    }
    
    /**
     * 消费延迟任务：取消超时订单
     */
    public void cancelTimeoutOrder(String orderId) {
        Order order = orderRepository.findById(orderId).orElse(null);
        if (order != null && order.getStatus() == OrderStatus.CREATED) {
            order.setStatus(OrderStatus.CANCELLED);
            order.setCancelReason("超时未支付");
            orderRepository.save(order);
            
            // 恢复库存
            stockService.restoreStock(order.getProductId(), order.getQuantity());
            
            log.info("订单 {} 超时取消完成", orderId);
        }
    }
}
```

---

## 10.6 RRemoteService（分布式远程调用）

```java
// 定义远程服务接口
public interface TaskExecutor {
    String executeTask(String taskName, Map<String, Object> params);
}

// 服务端实现
@RRemoteService(TaskExecutor.class)
public class TaskExecutorImpl implements TaskExecutor {
    @Override
    public String executeTask(String taskName, Map<String, Object> params) {
        System.out.println("执行远程任务: " + taskName);
        return "任务执行成功: " + taskName;
    }
}

// 服务端注册
@Service
public class RemoteServiceConfig {
    @Autowired
    private RedissonClient redissonClient;
    
    @PostConstruct
    public void registerService() {
        // 注册远程服务
        RRemoteService remoteService = redissonClient.getRemoteService();
        remoteService.register(TaskExecutor.class, new TaskExecutorImpl());
    }
}

// 客户端调用
@Component
public class RemoteServiceClient {
    @Autowired
    private RedissonClient redissonClient;
    
    public void callRemote() {
        RRemoteService remoteService = redissonClient.getRemoteService();
        TaskExecutor executor = remoteService.get(TaskExecutor.class);
        
        // 调用远程方法（如同本地调用）
        String result = executor.executeTask("报表生成", Map.of("date", "2024-01-01"));
        System.out.println(result);
    }
}
```

---

## 本章小结

1. **Redisson 定位**：不只是一个 Redis 客户端，更是一个完整的分布式编程框架
2. **分布式锁**：Redisson 的锁已经内置了可重入、看门狗、自动释放等机制，开箱即用
3. **布隆过滤器**：11MB 就能过滤 1000 万数据的缓存穿透问题
4. **限流器**：RRateLimiter 集成令牌桶算法，一句代码实现限流
5. **延迟队列**：RDelayedQueue 秒级精度，适合订单超时等场景
6. **远程服务**：RRemoteService 可以像本地方法一样调用远程服务

> **一句话记住**：用原生 Redis 命令是「点外卖」，用 Redisson 是「请厨师到家里做饭」——前者满足基本需求，后者提供全方位服务。
