# 第八章：Redis 在微服务中的深度实践

> **本章核心**：Redis 在微服务架构中扮演着比缓存更丰富的角色。本章深入讲解限流降级、分布式 Session、消息推送、实时计数、幂等性设计等微服务核心场景的 Redis 实战方案。

---

## 8.1 限流与降级

### 8.1.1 为什么需要限流

微服务中，限流是保护系统不被突发流量冲垮的第一道防线：

```
[外部流量] → [网关/Nginx] → [限流层] → [业务服务] → [数据库]
                 ↓
          抛弃超量请求
```

### 8.1.2 基于 Redis 的计数器限流

**固定窗口算法（最简单的限流）：**

```java
@Component
public class FixedWindowRateLimiter {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    /**
     * 固定窗口限流
     * @param key 限流key（如 "ratelimit:api:/order/create"）
     * @param maxRequests 窗口内最大请求数
     * @param windowSeconds 窗口大小（秒）
     * @return true=允许通过，false=被限流
     */
    public boolean allowRequest(String key, int maxRequests, int windowSeconds) {
        long count = redisTemplate.opsForValue().increment(key);
        if (count == 1) {
            // 第一次访问，设置过期时间
            redisTemplate.expire(key, windowSeconds, TimeUnit.SECONDS);
        }
        return count <= maxRequests;
    }
}
```

**问题**：固定窗口存在「临界突变」问题——在窗口切换瞬间可能通过 2 倍流量。

**滑动窗口算法（更精确）：**

```java
@Component
public class SlidingWindowRateLimiter {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    /**
     * 使用有序集合实现滑动窗口限流
     */
    public boolean allowRequest(String key, int maxRequests, long windowMillis) {
        long now = System.currentTimeMillis();
        long windowStart = now - windowMillis;
        
        // 使用 Lua 脚本保证原子性
        String lua = """
            -- 移除窗口外的数据（过期请求）
            redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, ARGV[1])
            
            -- 统计当前窗口内的请求数
            local count = redis.call('ZCARD', KEYS[1])
            
            if tonumber(count) < tonumber(ARGV[3]) then
                -- 添加当前请求
                redis.call('ZADD', KEYS[1], ARGV[2], ARGV[2])
                -- 设置过期时间（自动清理）
                redis.call('EXPIRE', KEYS[1], ARGV[4])
                return 1  -- 允许通过
            end
            return 0  -- 限流
            """;
        
        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(lua, Long.class),
            Collections.singletonList(key),
            String.valueOf(windowStart),       // ARGV[1]
            String.valueOf(now),               // ARGV[2]
            String.valueOf(maxRequests),        // ARGV[3]
            String.valueOf(windowMillis / 1000 + 1)  // ARGV[4]
        );
        
        return Long.valueOf(1).equals(result);
    }
}
```

### 8.1.3 令牌桶限流

令牌桶比计数器更平滑，允许一定的突发流量：

```java
@Component
public class TokenBucketRateLimiter {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    /**
     * 令牌桶限流
     * @param key 限流key
     * @param capacity 桶容量（最大突发量）
     * @param rate 每秒填充令牌数
     */
    public boolean tryAcquire(String key, int capacity, int rate) {
        String lua = """
            local key = KEYS[1]
            local capacity = tonumber(ARGV[1])
            local rate = tonumber(ARGV[2])
            local now = tonumber(ARGV[3])
            
            -- 获取当前桶中令牌数
            local tokens = redis.call('HGET', key, 'tokens')
            local lastRefill = redis.call('HGET', key, 'lastRefill')
            
            if not tokens then
                tokens = capacity
                lastRefill = now
            else
                tokens = tonumber(tokens)
                lastRefill = tonumber(lastRefill)
                
                -- 计算这段时间应该填充的令牌
                local elapsed = now - lastRefill
                local newTokens = elapsed * rate / 1000
                tokens = math.min(capacity, tokens + newTokens)
                lastRefill = now
            end
            
            if tokens >= 1 then
                redis.call('HSET', key, 'tokens', tokens - 1)
                redis.call('HSET', key, 'lastRefill', lastRefill)
                redis.call('EXPIRE', key, 10)
                return 1
            end
            return 0
            """;
        
        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(lua, Long.class),
            Collections.singletonList(key),
            String.valueOf(capacity),
            String.valueOf(rate),
            String.valueOf(System.currentTimeMillis())
        );
        
        return Long.valueOf(1).equals(result);
    }
}
```

### 8.1.4 分布式限流实战：API 网关限流

```java
@Component
public class GatewayRateLimiter {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    /**
     * 多维度限流
     */
    public boolean multiDimensionRateLimit(String userId, String apiPath, String ip) {
        // 1. 全局限流（整个API网关：10万QPS）
        if (!allowRequest("ratelimit:global", 100000, 1)) {
            log.warn("全局限流触发");
            return false;
        }
        
        // 2. 用户级别限流（每个用户：1000 QPS）
        if (!allowRequest("ratelimit:user:" + userId, 1000, 1)) {
            log.warn("用户限流触发: {}", userId);
            return false;
        }
        
        // 3. API 级别限流（每个API：10000 QPS）
        if (!allowRequest("ratelimit:api:" + apiPath, 10000, 1)) {
            log.warn("API限流触发: {}", apiPath);
            return false;
        }
        
        // 4. IP 级别限流（每个IP：500 QPS）
        if (!allowRequest("ratelimit:ip:" + ip, 500, 1)) {
            log.warn("IP限流触发: {}", ip);
            return false;
        }
        
        return true;
    }
}
```

---

## 8.2 分布式 Session 管理

### 8.2.1 传统 Session 的问题

```
传统方案（Tomcat Session）：
  [用户] → [Nginx] → [Tomcat1]  → Session存在Tomcat1内存
  [用户] → [Nginx] → [Tomcat2]  → Session不存在！（因为Session在Tomcat1）

解决方案：
  1. Nginx 粘性 Session（ip_hash）→ 但Tomcat宕机后Session丢失
  2. Session 复制（Tomcat集群间广播）→ 网络开销大，有延迟
  3. ✅ 集中式 Session（Redis）→ 统一存储，所有节点共享
```

### 8.2.2 Spring Session + Redis 集成

```xml
<!-- pom.xml 添加依赖 -->
<dependency>
    <groupId>org.springframework.session</groupId>
    <artifactId>spring-session-data-redis</artifactId>
</dependency>
```

```yaml
spring:
  session:
    store-type: redis          # 使用Redis存储Session
    redis:
      namespace: spring:session
      flush-mode: on_save       # 每次保存后刷新到Redis
  redis:
    host: 192.168.1.10
    port: 6379
```

```java
@Configuration
@EnableRedisHttpSession(maxInactiveIntervalInSeconds = 1800) // 30分钟
public class RedisSessionConfig {
    @Bean
    public RedisSerializer<Object> springSessionDefaultRedisSerializer() {
        return new GenericJackson2JsonRedisSerializer();
    }
}
```

**工作原理：**
```
用户登录 → Spring Session 创建 Session → 存储到 Redis
  Key: "spring:session:sessions:" + sessionId
  Hash: {
    "sessionAttr:username": "张三",
    "sessionAttr:role": "admin",
    "maxInactiveInterval": 1800,
    "lastAccessedTime": 1704067200000,
    "creationTime": 1704067200000
  }
  TTL: 30分钟（每次访问刷新）
```

### 8.2.3 Session 安全优化

```java
@Component
public class SessionSecurityManager {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    /**
     * 实现「单用户单会话」（同一账号只能在一个设备登录）
     */
    public String createSessionWithKickout(Long userId) {
        String userSessionKey = "user:session:" + userId;
        
        // 获取用户当前的 sessionId
        String oldSessionId = (String) redisTemplate.opsForValue().get(userSessionKey);
        
        if (oldSessionId != null) {
            // 踢掉旧的 Session
            String oldSessionKey = "spring:session:sessions:" + oldSessionId;
            redisTemplate.delete(oldSessionKey);
            log.info("踢掉用户 {} 的旧会话: {}", userId, oldSessionId);
        }
        
        // 创建新 session（实际由 Spring Session 自动创建）
        String newSessionId = UUID.randomUUID().toString();
        redisTemplate.opsForValue().set(userSessionKey, newSessionId, 
            30, TimeUnit.MINUTES);
        
        return newSessionId;
    }
}
```

---

## 8.3 消息推送与实时计数

### 8.3.1 WebSocket + Redis Pub/Sub 实现广播

```
[WebSocket Server1] ← Redis Pub/Sub → [WebSocket Server2]
     ↓                                      ↓
[用户A]                                 [用户B]

当用户A发送消息：Server1 → Redis PUBLISH → Server2收到 → 推给用户B
```

```java
@Controller
public class WebSocketController {
    @Autowired
    private RedisTemplate<String, Object> redisTemplate;
    
    private static final String CHANNEL = "ws:notify";
    
    /**
     * 发送全局通知
     */
    public void sendGlobalNotification(Notification notification) {
        // 发布到 Redis Channel，所有 WebSocket 服务都会收到
        redisTemplate.convertAndSend(CHANNEL, notification);
    }
    
    @Bean
    public MessageListenerAdapter messageListener() {
        return new MessageListenerAdapter((MessageListener) (message, pattern) -> {
            // 收到 Pub/Sub 消息后，推送给连接到当前服务器的 WebSocket 客户端
            String payload = new String(message.getBody(), StandardCharsets.UTF_8);
            websocketHandler.broadcast(payload);
        });
    }
}
```

### 8.3.2 实时计数与在线人数

```java
@Service
public class OnlineCounter {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String ONLINE_KEY = "online:users";
    
    /**
     * 用户上线
     */
    public void userOnline(Long userId) {
        // 使用 Bitmap 记录在线状态
        redisTemplate.opsForValue().setBit(ONLINE_KEY, userId, true);
        // 设置过期时间（每10分钟刷新一次）
        redisTemplate.expire(ONLINE_KEY, 10, TimeUnit.MINUTES);
    }
    
    /**
     * 用户心跳（刷新在线状态）
     */
    public void heartbeat(Long userId) {
        redisTemplate.opsForValue().setBit(ONLINE_KEY, userId, true);
        redisTemplate.expire(ONLINE_KEY, 10, TimeUnit.MINUTES);
    }
    
    /**
     * 获取在线人数
     */
    public long getOnlineCount() {
        Long count = redisTemplate.execute(
            (RedisCallback<Long>) conn -> conn.bitCount(ONLINE_KEY.getBytes()));
        return count == null ? 0 : count;
    }
    
    /**
     * 更精确的在线方案：使用 Sorted Set
     * score=最新心跳时间，定期清理离线用户
     */
    public void preciseHeartbeat(Long userId) {
        String preciseKey = "online:precise";
        redisTemplate.opsForZSet().add(preciseKey, 
            String.valueOf(userId), System.currentTimeMillis());
        redisTemplate.expire(preciseKey, 10, TimeUnit.MINUTES);
    }
    
    @Scheduled(fixedDelay = 30000) // 每30秒清理一次
    public void cleanOfflineUsers() {
        String preciseKey = "online:precise";
        long threshold = System.currentTimeMillis() - 300_000; // 5分钟无心跳视为离线
        redisTemplate.opsForZSet().removeRangeByScore(preciseKey, 0, threshold);
    }
}
```

---

## 8.4 幂等性设计

### 8.4.1 为什么需要幂等

在微服务中，网络超时、重试机制可能导致同一请求被处理多次：

```
用户点击「提交订单」
  → 请求1 到订单服务
  → 网络超时（但订单已创建成功）
  → 用户再次点击「提交订单」
  → 请求2 到订单服务
  → 如果不做幂等，会创建两个相同的订单！
```

### 8.4.2 基于 Redis 的幂等方案

```java
@Component
public class IdempotentService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String IDEMPOTENT_PREFIX = "idempotent:";
    private static final long DEFAULT_TTL = 24; // 幂等key保留24小时
    
    /**
     * 生成幂等令牌（客户端调用接口前先获取）
     */
    public String generateIdempotentToken() {
        String token = UUID.randomUUID().toString().replace("-", "");
        String key = IDEMPOTENT_PREFIX + token;
        redisTemplate.opsForValue().set(key, "0", DEFAULT_TTL, TimeUnit.HOURS);
        return token;
    }
    
    /**
     * 执行幂等操作
     * @param idempotentKey 由业务参数生成的唯一key
     * @param expireSeconds 幂等保留时间
     * @param operation 要执行的业务操作
     */
    public <T> T executeWithIdempotent(String idempotentKey, 
                                       long expireSeconds,
                                       Supplier<T> operation) {
        String key = IDEMPOTENT_PREFIX + idempotentKey;
        
        // 使用 SET NX 原子操作
        Boolean set = redisTemplate.opsForValue()
            .setIfAbsent(key, "processing", expireSeconds, TimeUnit.SECONDS);
        
        if (!Boolean.TRUE.equals(set)) {
            // key 已存在，说明该操作已执行或正在执行
            String status = redisTemplate.opsForValue().get(key);
            if ("completed".equals(status)) {
                // 已执行完成，直接返回成功
                return (T) "SUCCESS_ALREADY_EXECUTED";
            }
            // 正在执行中，等待或返回重试
            throw new IdempotentException("操作正在处理中，请勿重复提交");
        }
        
        try {
            // 执行业务逻辑
            T result = operation.get();
            
            // 标记为已完成
            redisTemplate.opsForValue().set(key, "completed", 
                expireSeconds, TimeUnit.SECONDS);
            
            return result;
        } catch (Exception e) {
            // 业务失败，删除幂等key（允许重试）
            redisTemplate.delete(key);
            throw e;
        }
    }
    
    /**
     * 基于业务参数的幂等Key生成
     * 例如：幂等key = "order:create:{userId}:{orderNo}"
     */
    public static String buildIdempotentKey(String bizType, Object... params) {
        StringBuilder sb = new StringBuilder(bizType);
        for (Object param : params) {
            sb.append(":").append(param);
        }
        return sb.toString();
    }
}
```

### 8.4.3 订单防重实战

```java
@Service
public class OrderService {
    @Autowired
    private IdempotentService idempotentService;
    
    /**
     * 创建订单（幂等）
     */
    @Transactional
    public Order createOrder(Long userId, Long productId, Integer quantity) {
        // 生成幂等key：user + product + 时间窗口（同一个用户在1秒内只允许创建一个订单）
        String idempotentKey = IdempotentService.buildIdempotentKey(
            "order:create",
            userId,
            productId,
            System.currentTimeMillis() / 1000  // 精确到秒
        );
        
        return idempotentService.executeWithIdempotent(
            idempotentKey,
            86400, // 保留24小时
            () -> {
                // 真正的业务逻辑
                Order order = new Order();
                order.setUserId(userId);
                order.setProductId(productId);
                order.setQuantity(quantity);
                order.setStatus(OrderStatus.CREATED);
                return orderRepository.save(order);
            }
        );
    }
}
```

---

## 本章小结

1. **限流**：Redis 计数器实现简单限流，令牌桶支持突发流量，多维度限流保护系统
2. **Session 管理**：Spring Session + Redis 实现分布式 Session，集中管理、自动过期
3. **消息推送**：Redis Pub/Sub 实现跨服务实时通信，适合 WebSocket 广播场景
4. **实时计数**：Bitmap 方案省内存，Sorted Set 方案更精确
5. **幂等设计**：SET NX 是幂等的核心，结合业务 key 生成和状态标记

> **一句话记住**：微服务中的 Redis 不只是缓存——它是限流器、会话中心、消息总线、计数器、幂等登记薄——一个麻雀虽小五脏俱全的数据结构服务器。
