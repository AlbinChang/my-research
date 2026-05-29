# 第二章：Redis 核心数据结构实战

> **本章核心**：深入八种核心数据结构的实战用法，每种结构都包含内部编码原理、生产级代码示例、常见坑位和真实案例。学完本章，你将在任何时候都能选出「最合适的那个数据结构」。

---

## 2.1 String：不仅仅是 KV

### 2.1.1 内部编码与内存优化

Redis 的 String 有三种内部编码方式：

| 编码 | 条件 | 说明 |
|------|------|------|
| **int** | 值为整型（如 `123`） | 8 字节存储，最省内存 |
| **embstr** | 值长度 ≤ 44 字节（Redis 7+ 为 ≤ 62） | 一次内存分配，只读 |
| **raw** | 值长度 > 44 字节 | 两次内存分配，可修改 |

```bash
# 验证内部编码
SET key1 100
OBJECT ENCODING key1  # "int"

SET key2 "hello"
OBJECT ENCODING key2  # "embstr"

SET key3 "a"  # 单字符
OBJECT ENCODING key3  # "embstr"

# 大于44字节的字符串
SET key4 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STRLEN key4  # 51
OBJECT ENCODING key4  # "raw"
```

**🔥 生产最佳实践：用 int 编码节省 90% 内存**

假设你要缓存 1000 万个用户状态（在线/离线）：
```bash
# ❌ 低效方案：存字符串
SET user:10001:status "online"  # embstr/raw 编码，占用约 30+ 字节

# ✅ 高效方案：用整数表示
SET user:10001:status 1  # int 编码，仅 8 字节
# 1=在线, 0=离线, 2=忙碌...
```

1000 万个 key 从 30 字节降到 8 字节，仅**值部分**就节省了 **220MB** 内存（不算 key 本身的额外开销）。

### 2.1.2 原子计数器：INCR 在高并发下的正确姿势

**业务场景**：文章阅读量统计、库存扣减、积分累计、限流计数器。

```bash
# 基本用法
INCR article:readcount:1001   # 原子+1，返回新值
INCRBY article:readcount:1001 10   # 原子+10
DECR article:readcount:1001   # 原子-1
DECRBY article:readcount:1001 5    # 原子-5
```

**Java 实现阅读量累加：**

```java
@Service
public class ArticleService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    // 方案一：逐条 INCR（每请求一次+1）
    public Long incrementReadCount(Long articleId) {
        String key = "article:readcount:" + articleId;
        return redisTemplate.opsForValue().increment(key);  // 返回最新的阅读数
    }
    
    // 方案二：批量上报（推荐，减少Redis操作次数）
    public void batchIncrementReadCount(Map<Long, Integer> increments) {
        // 使用 Pipeline 批量提交
        redisTemplate.executePipelined((RedisCallback<Object>) connection -> {
            increments.forEach((articleId, count) -> {
                String key = "article:readcount:" + articleId;
                byte[] rawKey = key.getBytes(StandardCharsets.UTF_8);
                connection.incrBy(rawKey, count);
            });
            return null;
        });
    }
}
```

**⚠️ INCR 的常见陷阱：**

```bash
# 陷阱1：INCR 对非数字字符串执行会报错
SET foo "abc"
INCR foo  # (error) ERR value is not an integer or out of range

# 陷阱2：INCR 结果超过 64 位有符号整数上限（9223372036854775807）也会报错
# 解决方案：使用 INCRBYFLOAT（浮点数）或设计更合理的分片策略

# 陷阱3：INCR 和 SET 的并发问题
# 错误示例：
if (redisTemplate.hasKey(key)) {
    redisTemplate.opsForValue().increment(key);  // 非原子操作
} else {
    redisTemplate.opsForValue().set(key, 1);
}
# ✅ 正确做法：直接用 INCR，key 不存在会自动从 0 开始
redisTemplate.opsForValue().increment(key);  // 一次搞定
```

### 2.1.3 分布式全局 ID 生成

**业务场景**：订单号、流水号、分布式系统主键。

```java
@Component
public class RedisIdGenerator {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String ID_KEY = "global:id:generator";
    // 使用业务前缀区分不同ID类型
    private static final String ID_KEY_ORDER = "id:order";
    private static final String ID_KEY_PAYMENT = "id:payment";
    
    /**
     * 生成全局唯一订单ID
     * 格式：日期(8位) + 自增序号(10位) = 18位
     */
    public String generateOrderId() {
        String date = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        String key = ID_KEY_ORDER + ":" + date;
        
        // INCR 自增，每天一个独立计数器
        Long seq = redisTemplate.opsForValue().increment(key);
        
        // 设置过期时间为明天凌晨（自动清理历史计数器）
        LocalDateTime tomorrow = LocalDate.now().plusDays(1).atStartOfDay();
        long expireSeconds = Duration.between(LocalDateTime.now(), tomorrow).getSeconds();
        redisTemplate.expire(key, expireSeconds, TimeUnit.SECONDS);
        
        // 格式化为10位序号，左补0
        String seqStr = String.format("%010d", seq);
        return date + seqStr;
    }
}
```

**🔥 生产注意**：
- 每天换一个 key 可以防止单 key 的 INCR 溢出
- 设置 TTL 让 Redis 自动清理历史 ID 计数器
- 相比雪花算法（Snowflake），这种方案不需要配置机器 ID，更适合容器化环境
- 相比数据库自增，这种方案性能提升 100 倍+（内存 vs 磁盘 IO）

### 2.1.4 商品库存扣减（生产级方案）

以下是在第一章案例基础上完善的库存扣减方案：

```java
@Component
public class StockService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String STOCK_PREFIX = "stock:";
    
    /**
     * 扣减库存（返回扣减后的库存数量）
     * @return -1: key不存在, -2: 库存不足, >=0: 扣减成功
     */
    public long decrementStock(Long itemId, int quantity) {
        String key = STOCK_PREFIX + itemId;
        
        // 使用Lua脚本保证原子性
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
        
        DefaultRedisScript<Long> script = new DefaultRedisScript<>();
        script.setScriptText(lua);
        script.setResultType(Long.class);
        
        return redisTemplate.execute(script, Collections.singletonList(key), 
            String.valueOf(quantity));
    }
    
    /**
     * 恢复库存（订单取消/超时未支付时调用）
     */
    public void restoreStock(Long itemId, int quantity) {
        redisTemplate.opsForValue().increment(STOCK_PREFIX + itemId, quantity);
    }
}
```

**⚠️ 常见误区**：不要在 Java 代码中做「读 → 判断 → 写」，这不是原子的，一定会出超卖。

---

## 2.2 Hash：对象存储的艺术

### 2.2.1 为什么 Hash 比 JSON 字符串更优

很多开发者喜欢把对象序列化为 JSON 字符串存入 String，但这种方式有严重缺陷：

```bash
# ❌ 错误做法：整个对象存为JSON字符串
SET user:10001 '{"name":"张三","age":25,"email":"zhangsan@example.com"}'
# 问题：想改 age 字段需要整个读出、反序列化、修改、再序列化、再写入
# 在高并发下会导致「更新丢失」问题
```

```bash
# ✅ 正确做法：用 Hash 存储对象字段
HSET user:10001 name "张三" age 25 email "zhangsan@example.com"
# 优点：可以单独修改/读取某个字段
HINCRBY user:10001 age 1   # 年龄+1，原子操作
```

**对比分析**：

| 操作 | JSON String | Hash |
|------|------------|------|
| 全部写入 | SET (一次序列化) | HMSET (需多次hset) |
| 读取单个字段 | GET+反序列化整个JSON | HGET (O(1)) |
| 更新单个字段 | GET+反序列化+修改+序列化+SET | HSET (一次操作) |
| 原子增减字段 | ❌ 不支持 | ✅ HINCRBY |
| 内存效率 | 较高（无额外元信息） | 较低（有field开销） |

**结论**：
- **频繁读/写单个字段**（如用户积分、文章点赞数、订单状态）→ **Hash**
- **整个对象一次性读取且不频繁修改**（如配置信息、静态数据）→ **String + JSON**

### 2.2.2 小对象压缩机制（ziplist）

Hash 在字段数少且值小时，使用 **ziplist** 编码替代 hashtable，内存节省 90%：

```bash
# 当同时满足以下条件时，使用 ziplist：
# - hash-max-ziplist-entries: 512 （字段数 ≤ 512）
# - hash-max-ziplist-value: 64 （每个字段的值 ≤ 64 字节）

# ziplist 编码（内存连续，节省空间）
HSET config:app theme "dark" language "zh" timeout "30"
DEBUG OBJECT config:app  # Encoding: ziplist

# hashtable 编码（超过阈值后自动转换）
# 往这个 hash 中不断添加很多大字段...
```

**🔥 生产调优建议**：
```bash
# 根据业务场景调整阈值
config set hash-max-ziplist-entries 1024  # 从512提高到1024
config set hash-max-ziplist-value 128     # 从64提高到128
```
📌 Redis 7.0+ 已将 ziplist 替换为 listpack，上述配置项更名为 `hash-max-listpack-entries`/`hash-max-listpack-value`，功能和用法不变。但注意：ziplist 过大时（超过几千个字段），更新中间字段的性能会下降（需要重新分配内存并移动数据）。

### 2.2.3 批量操作：HMGET/HMSET 的性能优势

```java
// ❌ 错误：逐个查询
User user = new User();
user.setName(redisTemplate.opsForHash().get("user:10001", "name"));   // 1次网络往返
user.setAge(redisTemplate.opsForHash().get("user:10001", "age"));     // 再1次
user.setEmail(redisTemplate.opsForHash().get("user:10001", "email")); // 再1次
// 共3次网络往返

// ✅ 正确：批量查询
List<Object> fields = redisTemplate.<Object, Object>opsForHash()
    .multiGet("user:10001", Arrays.asList("name", "age", "email"));
// 仅1次网络往返
user.setName((String) fields.get(0));
user.setAge((Integer) fields.get(1));
user.setEmail((String) fields.get(2));
```

性能差距：本地测试 3 次 GET vs 1 次 HMGET，在 100ms 网络延迟下，耗时差可达 **3 倍**。在网络延迟较高（跨机房调用）时差距更明显。

### 2.2.4 生产案例：用户会话信息存储

```java
@Component
public class SessionManager {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String SESSION_PREFIX = "session:";
    private static final long SESSION_TTL = 30; // 30分钟
    
    /**
     * 创建用户会话
     */
    public String createSession(Long userId, String username, String role) {
        String sessionId = UUID.randomUUID().toString().replace("-", "");
        String key = SESSION_PREFIX + sessionId;
        
        // 使用Hash存储会话信息
        Map<String, String> sessionData = new HashMap<>();
        sessionData.put("userId", String.valueOf(userId));
        sessionData.put("username", username);
        sessionData.put("role", role);
        sessionData.put("createdAt", String.valueOf(System.currentTimeMillis()));
        sessionData.put("lastAccess", String.valueOf(System.currentTimeMillis()));
        
        redisTemplate.opsForHash().putAll(key, sessionData);
        redisTemplate.expire(key, SESSION_TTL, TimeUnit.MINUTES);
        
        return sessionId;
    }
    
    /**
     * 访问时刷新会话过期时间（滑动过期）
     */
    public boolean refreshSession(String sessionId) {
        String key = SESSION_PREFIX + sessionId;
        Long expire = redisTemplate.getExpire(key, TimeUnit.SECONDS);
        if (expire != null && expire > 0) {
            // 更新最后访问时间
            redisTemplate.opsForHash().put(key, "lastAccess", 
                String.valueOf(System.currentTimeMillis()));
            // 刷新TTL
            redisTemplate.expire(key, SESSION_TTL, TimeUnit.MINUTES);
            return true;
        }
        return false; // 会话已过期
    }
    
    /**
     * 获取会话中的指定字段（无需全部读取）
     */
    public String getSessionField(String sessionId, String field) {
        String key = SESSION_PREFIX + sessionId;
        Object value = redisTemplate.opsForHash().get(key, field);
        return value != null ? (String) value : null;
    }
}
```

**🔥 设计要点**：
1. 使用 Hash 存储会话字段，可以单独读取/更新某个字段
2. 滑动过期机制：用户每次操作都刷新 TTL，避免活跃用户被强制踢下线
3. 单 key 存储所有会话字段，而不是每个字段一个 key，减少 key 数量

---

## 2.3 List：队列与栈的多种玩法

### 2.3.1 LPUSH + BRPOP 实现可靠消息队列

```bash
# 生产者
LPUSH queue:task "task_001"
LPUSH queue:task "task_002"

# 消费者（阻塞式读取，没有消息时挂起等待）
BRPOP queue:task 0  # 0表示无限等待
# 返回：1) "queue:task"  2) "task_001"
```

**Java 实现：**

```java
@Component
public class RedisQueue {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String QUEUE_KEY = "queue:task";
    
    /**
     * 发送消息
     */
    public void send(String message) {
        redisTemplate.opsForList().leftPush(QUEUE_KEY, message);
    }
    
    /**
     * 批量发送
     */
    public void sendBatch(List<String> messages) {
        redisTemplate.executePipelined((RedisCallback<Object>) connection -> {
            for (String msg : messages) {
                byte[] rawKey = QUEUE_KEY.getBytes(StandardCharsets.UTF_8);
                byte[] rawMsg = msg.getBytes(StandardCharsets.UTF_8);
                connection.lPush(rawKey, rawMsg);
            }
            return null;
        });
    }
    
    /**
     * 消费者线程：阻塞获取消息
     */
    @Component
    public static class QueueConsumer {
        @PostConstruct
        public void startConsume() {
            Executors.newSingleThreadExecutor().submit(() -> {
                while (true) {
                    try {
                        // BRPOP 阻塞等待，0=无限等待
                        List<String> messages = redisTemplate.opsForList()
                            .rightPop(QUEUE_KEY, 30, TimeUnit.SECONDS);
                        
                        if (messages != null) {
                            processMessage(messages.get(0));
                        }
                    } catch (Exception e) {
                        log.error("消费消息异常", e);
                    }
                }
            });
        }
        
        private void processMessage(String message) {
            // 业务处理逻辑
            System.out.println("处理消息: " + message);
        }
    }
}
```

**⚠️ List 做消息队列的局限性**：
- 不支持消息确认机制（消费后自动删除）→ 消费端崩溃会丢失消息
- 不支持重复消费 → 消费后即删除
- 不支持消费者组 → 只能广播或争抢

> 生产级场景建议使用 Redis Stream（见 2.9 节）或专业 MQ（Kafka/RocketMQ）。

### 2.3.2 LTRIM 实现固定长度时间线

**业务场景**：用户最近浏览记录（只保留最近 100 条）。

```bash
# 每次浏览后执行：
LPUSH user:10001:history "item_2001"
LTRIM user:10001:history 0 99  # 只保留前100条

# 查询最近浏览
LRANGE user:10001:history 0 9  # 最近10条
```

```java
public void addBrowseHistory(Long userId, Long itemId) {
    String key = "user:" + userId + ":history";
    redisTemplate.opsForList().leftPush(key, String.valueOf(itemId));
    redisTemplate.opsForList().trim(key, 0, 99);  // 保留100条
}

public List<String> getBrowseHistory(Long userId, int limit) {
    String key = "user:" + userId + ":history";
    return redisTemplate.opsForList().range(key, 0, limit - 1);
}
```

### 2.3.3 分页查询的陷阱与替代方案

```bash
# ❌ 错误：使用 LRANGE 做深度分页
LRANGE user:10001:history 10000 10009
# 底层是链表，越往后遍历越慢，时间复杂度 O(N)

# ✅ 正确：限制分页深度，或用 Sorted Set 代替
# 方案一：只支持前 N 页（如最多翻100页）
if (pageNum > 100) {
    return Collections.emptyList();  // 拒绝深度翻页
}

# 方案二：用 Sorted Set 替代 List（按时间戳排序）
ZADD user:10001:history_ts 1680000000 "item_2001"
ZREVRANGE user:10001:history_ts 0 9 WITHSCORES  # 最近10条
```

---

## 2.4 Set：标签与关系运算

### 2.4.1 标签系统与集合运算

**业务场景**：用户兴趣标签、文章分类、权限系统。

```bash
# 为用户打标签
SADD user:10001:tags "tech" "programming" "redis" "java"
SADD user:10002:tags "tech" "python" "ai" "machine-learning"

# 集合运算：找到共同兴趣
SINTER user:10001:tags user:10002:tags  # 交集："tech"
SUNION user:10001:tags user:10002:tags  # 并集
SDIFF user:10001:tags user:10002:tags    # 差集

# 判断用户是否有某标签
SISMEMBER user:10001:tags "redis"  # 1（是）
```

**Java 实现内容推荐：**

```java
@Service
public class RecommendService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    /**
     * 基于用户兴趣标签推荐内容
     */
    public List<Long> recommendContent(Long userId, int limit) {
        String userTagKey = "user:" + userId + ":tags";
        
        // 获取用户的所有标签
        Set<String> userTags = redisTemplate.opsForSet().members(userTagKey);
        
        // 对每个标签，找到对应的内容ID集合，取并集
        String unionKey = "recommend:union:" + userId;
        redisTemplate.delete(unionKey);
        
        for (String tag : userTags) {
            String contentKey = "tag:" + tag + ":contents";
            redisTemplate.opsForSet().unionAndStore(unionKey, contentKey, unionKey);
        }
        
        // 随机取出 limit 条推荐内容
        Set<String> contentIds = redisTemplate.opsForSet()
            .distinctRandomMembers(unionKey, limit);
        
        // 清理临时 key
        redisTemplate.delete(unionKey);
        
        return contentIds.stream()
            .map(Long::valueOf)
            .collect(Collectors.toList());
    }
}
```

### 2.4.2 SPOP 实现抽奖系统

```bash
# 初始化奖池（每个用户一个唯一ID）
SADD lottery:20240101 "user_1001" "user_1002" ... "user_10000"

# 抽奖：随机移除并返回一个元素
SPOP lottery:20240101  # 一等奖
SPOP lottery:20240101  # 二等奖

# 或者不删除元素（用于查看中奖结果但保留资格直到活动结束）
SRANDMEMBER lottery:20240101 3  # 随机抽3个中奖用户
```

```java
public List<String> drawLottery(String lotteryKey, int prizeCount) {
    // SPOP 原子性地移除并返回随机元素
    return redisTemplate.opsForSet().pop(lotteryKey, prizeCount);
}
```

### 2.4.3 Set vs Bitmap 在大数据量下的选择

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 用户标签（<1000标签） | Set | 操作灵活，支持交并差 |
| 日活用户（千万级） | Bitmap | 内存极致节省 |
| 抽奖（万级） | Set | 随机操作方便 |
| 黑名单（百万级） | Set 或 BloomFilter | Set精确，BloomFilter省内存 |

---

## 2.5 Sorted Set：排行榜与延时队列

### 2.5.1 实时排行榜

**业务场景**：直播间热榜、文章热榜、游戏天梯排名。

```bash
# 更新主播热度分（每次新增送礼物/点赞都加）
ZINCRBY live:rank:20240101 100 "anchor_1001"   # 给主播1001加100分
ZINCRBY live:rank:20240101 50  "anchor_1002"

# 查询TOP10
ZREVRANGE live:rank:20240101 0 9 WITHSCORES  # 按分数从高到低

# 查询某个主播的排名
ZREVRANK live:rank:20240101 "anchor_1001"  # 返回排名（0开始）

# 查询主播的当前分数
ZSCORE live:rank:20240101 "anchor_1001"
```

**Java 实现直播间热榜：**

```java
@Service
public class LiveRankService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String RANK_PREFIX = "live:rank:";
    
    /**
     * 增加主播热度（礼物/点赞/分享等事件触发）
     */
    public void addScore(Long anchorId, int score) {
        String key = RANK_PREFIX + LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        redisTemplate.opsForZSet().incrementScore(key, String.valueOf(anchorId), score);
        
        // 设置过期时间（次日凌晨自动清除）
        redisTemplate.expire(key, 1, TimeUnit.DAYS);
    }
    
    /**
     * 获取排行榜TOP N
     */
    public List<RankItem> getTopN(int n) {
        String key = RANK_PREFIX + LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        Set<ZSetOperations.TypedTuple<String>> result = redisTemplate.opsForZSet()
            .reverseRangeWithScores(key, 0, n - 1);
        
        List<RankItem> list = new ArrayList<>();
        int rank = 1;
        for (ZSetOperations.TypedTuple<String> tuple : result) {
            list.add(new RankItem(rank++, Long.valueOf(tuple.getValue()), tuple.getScore()));
        }
        return list;
    }
    
    @Data
    @AllArgsConstructor
    public static class RankItem {
        private int rank;
        private Long anchorId;
        private double score;
    }
}
```

### 2.5.2 延时队列实现

**💡 原理**：使用 ZADD 将任务的执行时间戳作为 score，轮询 ZRANGEBYSCORE 获取到期的任务。

```java
@Component
public class DelayQueue {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String DELAY_QUEUE_KEY = "delay:queue:tasks";
    
    /**
     * 添加延时任务
     * @param taskId 任务ID
     * @param delayMillis 延迟时间（毫秒）
     */
    public void addTask(String taskId, long delayMillis) {
        long executeTime = System.currentTimeMillis() + delayMillis;
        redisTemplate.opsForZSet().add(DELAY_QUEUE_KEY, taskId, executeTime);
    }
    
    /**
     * 消费线程：轮询获取到期任务
     */
    @Component
    public static class DelayConsumer {
        @Scheduled(fixedDelay = 1000) // 每秒轮询一次
        public void poll() {
            long now = System.currentTimeMillis();
            
            // 获取所有score <= now的任务（已到期的任务）
            Set<String> tasks = redisTemplate.opsForZSet()
                .rangeByScore(DELAY_QUEUE_KEY, 0, now);
            
            if (tasks != null && !tasks.isEmpty()) {
                for (String taskId : tasks) {
                    // 尝试移除任务（保证只有一个线程能消费到）
                    Long removed = redisTemplate.opsForZSet()
                        .remove(DELAY_QUEUE_KEY, taskId);
                    
                    if (removed != null && removed > 0) {
                        // 成功移除，说明当前线程抢到了这个任务
                        processTask(taskId);
                    }
                    // 如果removed为0，说明其他线程已经消费了
                }
            }
        }
        
        private void processTask(String taskId) {
            System.out.println("执行延时任务: " + taskId);
        }
    }
}
```

**⚠️ 注意事项**：
- 这种方案的精度受限于轮询间隔（上例为 1 秒），不适合毫秒级精度的延时任务
- 适合：订单超时取消（30分钟）、定时通知、活动预热
- 不适合：高频定时任务（毫秒级）

---

## 2.6 Bitmap：极致压缩的大数据统计

### 2.6.1 原理与编码

Bitmap 本质上是 String 的位操作，一个字节（8 bit）可以记录 8 个状态：

```
一个8位的Bitmap：0 1 0 1 1 0 0 1
                  ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓
                位0-位7，每位代表一个元素的0/1状态
```

内存计算公式：
```
内存(Bytes) = 用户ID最大值 / 8

例如：用户ID最大10亿（假设用户ID从0开始或可映射）
内存 = 10^9 / 8 = 125MB
```

仅 **125MB 内存** 就可以记录 10 亿用户的日活状态！

### 2.6.2 日活用户统计（亿级用户场景）

**业务场景**：统计每天/每周/每月的活跃用户数。

```bash
# 用户 10086 在 2024-01-01 访问了App
SETBIT user:dau:20240101 10086 1    # 将第10086位置为1

# 用户 10088 也访问了
SETBIT user:dau:20240101 10088 1

# 查询用户 10086 是否在当天活跃
GETBIT user:dau:20240101 10086      # 返回 1

# 统计当天活跃用户总数
BITCOUNT user:dau:20240101          # 统计1的个数

# 统计本周活跃用户（周一到周日的OR）
BITOP OR user:dau:week:1 user:dau:20240101 user:dau:20240102 ... 
BITCOUNT user:dau:week:1

# 统计本周每天都活跃的用户（周一到周日的AND）
BITOP AND user:dau:week_active user:dau:20240101 user:dau:20240102 ...
BITCOUNT user:dau:week_active
```

**Java 实现日活统计：**

```java
@Service
public class DailyActiveUserService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String DAU_PREFIX = "user:dau:";
    
    /**
     * 记录用户活跃
     * @param userId 用户ID（需要从原始ID映射为连续的整数ID）
     */
    public void recordActive(long mappedUserId) {
        String key = DAU_PREFIX + LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        redisTemplate.opsForValue().setBit(key, mappedUserId, true);
    }
    
    /**
     * 获取日活数
     */
    public long getDailyActiveUsers(String date) {
        String key = DAU_PREFIX + date;
        Long count = redisTemplate.execute(
            (RedisCallback<Long>) conn -> conn.bitCount(key.getBytes()));
        return count == null ? 0 : count;
    }
    
    /**
     * 获取周活数
     */
    public long getWeeklyActiveUsers() {
        String destKey = "user:dau:weekly_temp";
        LocalDate today = LocalDate.now();
        
        // 获取本周一到今天的日期
        List<byte[]> keys = new ArrayList<>();
        LocalDate monday = today.with(java.time.DayOfWeek.MONDAY);
        for (LocalDate date = monday; !date.isAfter(today); date = date.plusDays(1)) {
            keys.add((DAU_PREFIX + date.format(DateTimeFormatter.BASIC_ISO_DATE)).getBytes());
        }
        
        // BITOP OR
        redisTemplate.execute((RedisCallback<Long>) conn -> {
            conn.bitOp(io.lettuce.core.BitFieldArgs.BitOpType.OR, 
                destKey.getBytes(), keys.toArray(new byte[0][]));
            return null;
        });
        
        // 统计活跃数
        Long count = redisTemplate.execute(
            (RedisCallback<Long>) conn -> conn.bitCount(destKey.getBytes()));
        
        redisTemplate.delete(destKey); // 清理临时key
        return count == null ? 0 : count;
    }
}
```

**⚠️ 重要：用户ID映射问题**

Bitmap 的核心约束是「位偏移量需要是连续的整数」。如果你的用户 ID 不连续（通常是自增 ID，中间有删除/空洞），需要做一次映射：

```java
// 方案：维护一个用户ID→序号的双向映射
// 使用 Redis Hash 做映射
public long mapUserId(Long rawUserId) {
    String mappingKey = "user:id:mapping";
    Boolean exists = redisTemplate.opsForHash().hasKey(mappingKey, String.valueOf(rawUserId));
    if (exists != null && exists) {
        return Long.parseLong(
            (String) redisTemplate.opsForHash().get(mappingKey, String.valueOf(rawUserId)));
    }
    // 使用 INCR 生成连续序号
    Long seq = redisTemplate.opsForValue().increment("user:id:sequence");
    redisTemplate.opsForHash().put(mappingKey, String.valueOf(rawUserId), String.valueOf(seq));
    return seq;
}
```

### 2.6.3 签到系统

```java
@Service
public class SignInService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    /**
     * 用户签到（每位代表一天）
     * 一年最多366位，只需要 366/8 ≈ 46 字节
     */
    public boolean signIn(Long userId, LocalDate date) {
        String key = "user:sign:" + userId + ":" + date.getYear();
        int offset = date.getDayOfYear() - 1;  // 0-based
        
        Boolean hasSigned = redisTemplate.opsForValue().setBit(key, offset, true);
        return hasSigned == null || !hasSigned;  // true=本次签到成功
    }
    
    /**
     * 计算连续签到天数
     */
    public int getContinuousSignDays(Long userId, LocalDate today) {
        String key = "user:sign:" + userId + ":" + today.getYear();
        int count = 0;
        
        // 从今天往前遍历
        for (int i = today.getDayOfYear() - 1; i >= 0; i--) {
            Boolean bit = redisTemplate.opsForValue().getBit(key, i);
            if (Boolean.TRUE.equals(bit)) {
                count++;
            } else {
                break;  // 遇到未签到就停止
            }
        }
        return count;
    }
}
```

---

## 2.7 HyperLogLog：基数估算的艺术

### 2.7.1 原理与误差边界

HyperLogLog（HLL）使用概率算法估算集合的基数（不重复元素数量），

- **标准误差**：0.81%
- **固定内存**：12KB（无论处理多少数据）
- **适用场景**：不要求绝对精确的计数场景

```bash
# 添加元素
PFADD uv:page:home "user_1001" "user_1002" "user_1003"
PFADD uv:page:home "user_1001"  # 重复添加不影响

# 统计基数（不重复元素数）
PFCOUNT uv:page:home  # 返回 3

# 合并多个HLL（跨页面统计全站UV）
PFMERGE uv:site:total uv:page:home uv:page:detail uv:page:search
PFCOUNT uv:site:total
```

### 2.7.2 百万级 UV 统计对比

假设每天 1000 万独立访客：

| 方案 | 内存占用 | 精确度 | 速度 |
|------|---------|--------|------|
| Set | 1000万 × 8字节 = 80MB+ | 精确 | O(N) |
| Bitmap（有映射） | 125MB | 精确 | O(1) |
| Bitmap（无映射） | 根据最大ID | 精确 | O(1) |
| **HyperLogLog** | **12KB** | ±0.81% | O(1) |

HLL 用 **12KB** 实现了 Set 需要 **80MB** 才能做到的事情，误差不到 1%，但这个误差是否可以接受取决于业务场景。

**🔥 最佳实践**：
- 首页/活动页 UV 统计 → HLL（误差 1% 完全可以接受）
- 财务/对账类精确统计 → Set 或数据库

### 2.7.3 Java 实现 UV 统计

```java
@Service
public class UVService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String UV_PREFIX = "uv:";
    
    /**
     * 记录访客
     */
    public void recordVisit(String pageId, String visitorId) {
        String key = UV_PREFIX + pageId + ":" + 
            LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE);
        redisTemplate.opsForHyperLogLog().add(key, visitorId);
    }
    
    /**
     * 获取UV数
     */
    public long getUV(String pageId, String date) {
        String key = UV_PREFIX + pageId + ":" + date;
        Long count = redisTemplate.opsForHyperLogLog().size(key);
        return count == null ? 0 : count;
    }
    
    /**
     * 获取全站UV（合并所有页面）
     */
    public long getSiteUV(String date) {
        String destKey = UV_PREFIX + "site:" + date;
        String pattern = UV_PREFIX + "*:" + date;
        
        // 查找所有页面的HLL key
        Set<String> keys = redisTemplate.keys(pattern);
        if (keys == null || keys.isEmpty()) {
            return 0;
        }
        
        // 合并到临时key
        Long result = redisTemplate.opsForHyperLogLog().union(destKey, keys.toArray(new String[0]));
        redisTemplate.delete(destKey);  // 清理临时key
        
        return result == null ? 0 : result;
    }
}
```

---

## 2.8 GEO：位置服务

### 2.8.1 附近的人/商家查询

Redis GEO 基于 geohash 算法实现，底层使用 Sorted Set 存储：

```bash
# 添加位置（经度 纬度 成员名）
GEOADD shops 116.397128 39.916527 "shop_1001"   # 天安门附近
GEOADD shops 116.326461 39.900805 "shop_1002"   # 西单附近
GEOADD shops 116.455166 39.914501 "shop_1003"   # 国贸附近

# 查询附近的商家（以 116.40,39.91 为中心，半径5公里）
GEORADIUS shops 116.40 39.91 5 km WITHCOORD WITHDIST COUNT 10 ASC
# 返回：商家名、距离、坐标

# 查询两个商家之间的距离
GEODIST shops shop_1001 shop_1002 km  # 返回公里数

# 获取商家的 geohash 字符串
GEOHASH shops shop_1001  # 返回 geohash（可用于其他系统）
```

### 2.8.2 Java 实现附近商家查询

```java
@Service
public class NearbyService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String GEO_KEY = "shops";
    
    /**
     * 添加商家位置
     */
    public void addShop(Long shopId, double longitude, double latitude) {
        redisTemplate.opsForGeo().add(GEO_KEY, 
            new Point(longitude, latitude), 
            String.valueOf(shopId));
    }
    
    /**
     * 查找附近的商家
     */
    public List<NearbyShop> findNearby(double longitude, double latitude, 
                                        double radiusKm, int limit) {
        Circle circle = new Circle(new Point(longitude, latitude), 
            new Distance(radiusKm, RedisGeoCommands.DistanceUnit.KILOMETERS));
        
        RedisGeoCommands.GeoRadiusCommandArgs args = 
            RedisGeoCommands.GeoRadiusCommandArgs.newGeoRadiusArgs()
                .includeDistance()
                .includeCoordinates()
                .sortAscending()
                .limit(limit);
        
        GeoResults<RedisGeoCommands.GeoLocation<String>> results = 
            redisTemplate.opsForGeo().radius(GEO_KEY, circle, args);
        
        List<NearbyShop> list = new ArrayList<>();
        if (results != null) {
            for (GeoResult<RedisGeoCommands.GeoLocation<String>> result : results) {
                NearbyShop shop = new NearbyShop();
                shop.setShopId(Long.valueOf(result.getContent().getName()));
                shop.setDistance(result.getDistance().getValue());
                shop.setLongitude(result.getContent().getPoint().getX());
                shop.setLatitude(result.getContent().getPoint().getY());
                list.add(shop);
            }
        }
        return list;
    }
    
    @Data
    public static class NearbyShop {
        private Long shopId;
        private Double distance;
        private Double longitude;
        private Double latitude;
    }
}
```

**⚠️ 生产注意事项**：
1. GEO 底层是 Sorted Set，当数据量巨大（百万级以上）时，ZSET 的读写性能开始下降
2. GEO 不支持多边形区域查询（如「查某个商圈内的商家」），需要其他方案补充
3. 频繁更新的场景（如外卖骑手位置），建议使用独立 Redis 实例

---

## 2.9 Stream：消息队列的终极方案

### 2.9.1 核心概念

Redis 5.0 引入的 Stream 是 Redis 消息队列的集大成者：

| 概念 | 说明 |
|------|------|
| **消息** | 一个键值对组成的 Map |
| **Consumer Group** | 消费者组，组内消费者共同消费消息 |
| **Consumer** | 消费者，归属于某个消费者组 |
| **ID** | 消息唯一 ID（格式：时间戳-序号） |
| **last_delivered_id** | 消费者组已投递的最大消息ID |
| **pending_ids** | 已投递但未确认的消息列表（PEL） |

```bash
# 生产消息
XADD order:events * orderId "1001" status "created" amount "299.00"
# 返回消息ID，如：1704067200000-0

# 创建消费者组
XGROUP CREATE order:events group1 $  # $ 表示从最新消息开始消费

# 消费者读取消息
XREADGROUP GROUP group1 consumer1 COUNT 10 BLOCK 5000 STREAMS order:events >
# > 表示获取未被组内消费的消息

# 确认消息（处理完成后调用，防止重复消费）
XACK order:events group1 1704067200000-0

# 查看未确认的消息（用于异常恢复）
XPENDING order:events group1
```

### 2.9.2 生产案例：订单异步处理

```java
@Component
public class OrderStreamService {
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    private static final String STREAM_KEY = "order:events";
    private static final String GROUP_NAME = "order-process-group";
    
    @PostConstruct
    public void init() {
        // 创建消费者组（如果不存在）
        try {
            redisTemplate.opsForStream().createGroup(STREAM_KEY, GROUP_NAME);
        } catch (Exception e) {
            // 组已存在，忽略异常
        }
    }
    
    /**
     * 发送订单事件
     */
    public String sendOrderEvent(OrderEvent event) {
        Map<String, Object> fields = new HashMap<>();
        fields.put("orderId", event.getOrderId());
        fields.put("status", event.getStatus());
        fields.put("amount", String.valueOf(event.getAmount()));
        fields.put("timestamp", String.valueOf(System.currentTimeMillis()));
        
        RecordId recordId = redisTemplate.opsForStream()
            .add(STREAM_KEY, fields);
        return recordId.getValue();
    }
    
    /**
     * 消费者：使用 @Scheduled 定期拉取
     */
    @Scheduled(fixedDelay = 100)
    public void consumeOrderEvents() {
        List<MapRecord<String, Object, Object>> records = redisTemplate.opsForStream()
            .read(Consumer.from(GROUP_NAME, "consumer-1"),
                StreamReadOptions.empty().count(10).block(Duration.ofMillis(100)),
                StreamOffset.create(STREAM_KEY, ReadOffset.lastConsumed()));
        
        if (records != null) {
            for (MapRecord<String, Object, Object> record : records) {
                try {
                    processOrder(record.getValue());
                    // 确认消费
                    redisTemplate.opsForStream().acknowledge(STREAM_KEY, GROUP_NAME, record.getId());
                } catch (Exception e) {
                    log.error("处理订单事件失败: {}", record.getId(), e);
                    // 不确认，消息会留在pending列表中，后续可以重新消费
                }
            }
        }
    }
    
    /**
     * 处理pending消息（异常恢复）
     */
    @Scheduled(fixedDelay = 60000) // 每分钟检查一次
    public void processPendingMessages() {
        PendingMessagesSummary summary = redisTemplate.opsForStream()
            .pending(STREAM_KEY, GROUP_NAME);
        
        if (summary != null && summary.getTotalPendingCount() > 0) {
            // 读取pending消息
            List<MapRecord<String, Object, Object>> records = redisTemplate.opsForStream()
                .read(Consumer.from(GROUP_NAME, "consumer-1"),
                    StreamReadOptions.empty().count(100),
                    StreamOffset.create(STREAM_KEY, ReadOffset.from("0")));
            
            if (records != null) {
                for (MapRecord<String, Object, Object> record : records) {
                    try {
                        processOrder(record.getValue());
                        redisTemplate.opsForStream()
                            .acknowledge(STREAM_KEY, GROUP_NAME, record.getId());
                    } catch (Exception e) {
                        log.error("重试处理失败: {}", record.getId(), e);
                    }
                }
            }
        }
    }
    
    private void processOrder(Map<Object, Object> data) {
        String orderId = (String) data.get("orderId");
        String status = (String) data.get("status");
        // 处理订单业务逻辑...
        log.info("处理订单: {} 状态: {}", orderId, status);
    }
}
```

### 2.9.3 Stream vs List vs Pub/Sub 对比

| 特性 | Stream | List (BRPOP) | Pub/Sub |
|------|--------|-------------|---------|
| 消息持久化 | ✅ RDB/AOF | ✅ RDB/AOF | ❌ 不持久化 |
| 消费者组 | ✅ | ❌ | ❌ |
| 消息确认 | ✅ XACK | ❌ POP即确认 | ❌ |
| 消息回溯 | ✅ 按ID范围 | ❌ | ❌ |
| 阻塞读取 | ✅ | ✅ | ✅ |
| 消息丢失风险 | 低（确认机制） | 高（消费端崩溃丢失） | 高（离线订阅者丢失） |

**🔥 选型建议**：
- 需要消息可靠性 + 消费者组 → **Stream**
- 轻量级 FIFO，可接受消息丢失 → **List**
- 实时广播，不需要持久化 → **Pub/Sub**

---

## 本章小结

1. **String**：核心胜在原子计数和全局 ID 生成，注意 INCR 的 64 位上限问题
2. **Hash**：管理对象字段的神器，用 ziplist 编码节省内存，适合频繁增减字段的场景
3. **List**：最简单的队列实现，但可靠性差，适合非关键链路
4. **Set**：集合运算能力强大，抽奖、标签系统首选
5. **Sorted Set**：排行榜场景无可替代，延时队列的轻量级实现
6. **Bitmap**：亿级用户日活统计的极致方案，125MB 解决 10 亿用户
7. **HyperLogLog**：UV 统计的免维护方案，12KB 解决千万级基数统计
8. **GEO**：附近的人/商家查询的最简单方案，但大数据量需注意
9. **Stream**：生产级消息队列，解决了 List 和 Pub/Sub 的可靠性问题

**章节练习**：思考你当前的项目场景，看能否用一种更合适的 Redis 数据结构来重构现有的缓存方案？
