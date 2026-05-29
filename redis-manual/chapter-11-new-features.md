# 第十一章：Redis 7.x 新特性与展望

> **本章核心**：回顾 Redis 7.x 的重要新特性，了解 Redis 未来的演进方向，以及附录中的常用命令速查和配置参考。

---

## 11.1 Redis 7.x 核心新特性

### 11.1.1 Redis Functions（替代 Lua）

Redis 7.0 引入 Redis Functions，作为 Lua 脚本的升级替代方案：

**Lua 脚本的问题：**
```
1. 脚本通过 EVALSHA 传播到从节点，管理分散
2. 无版本管理，覆盖旧脚本容易出错
3. 没有权限控制
```

**Redis Functions 的优势：**
```
1. 集中管理：函数库一次性加载到 Redis，所有节点共享
2. 版本控制：支持函数库的版本管理
3. 权限控制：可以限制某些用户执行函数
4. 标准化：类似数据库的存储过程
```

```bash
# 加载函数库
FUNCTION LOAD "#!lua name=mylib
redis.register_function('hgetall_with_count', function(keys, args)
    local key = keys[1]
    local data = redis.call('HGETALL', key)
    local count = redis.call('HLEN', key)
    return {count, data}
end)
"

# 调用函数
FCALL mylib hgetall_with_count 1 user:1001

# 列出所有函数
FUNCTION LIST

# 删除函数库
FUNCTION DELETE mylib
```

### 11.1.2 ACL 增强

Redis 6.0 引入了 ACL，7.x 进一步强化：

```bash
# 创建用户并授权
ACL SETUSER alice on >password123 +@all -@dangerous ~* &*
# on: 启用用户
# >password123: 设置密码
# +@all: 赋予所有类别命令权限
# -@dangerous: 移除危险命令（如 KEYS, FLUSHALL, CONFIG等）
# ~*: 允许访问所有 key
# &*: 允许使用所有 Pub/Sub 频道

# 创建只读用户（适合应用端）
ACL SETUSER app_readonly on >app_pass +@read ~*

# 查看用户
ACL LIST

# ACL 日志（查看被拒绝的操作）
ACL LOG
```

**🔥 生产最佳实践：**
```bash
# 为不同团队创建不同权限的用户
# 运营团队：只读 + 特定 key 前缀
ACL SETUSER ops on >ops_pass +@read ~cache:*

# 开发团队：读写 + 无危险命令
ACL SETUSER dev on >dev_pass +@all -@dangerous ~*

# 管理员：全部权限
ACL SETUSER admin on >admin_pass +@all ~* &*
```

### 11.1.3 性能提升

| 特性 | Redis 6.x | Redis 7.x | 提升 |
|------|----------|----------|------|
| 最大内存效率 | 基线 | 内存使用降低 20-30% | 🚀 |
| SET 命令吞吐量 | ~10万 QPS | ~15万 QPS | +50% |
| Pipeline 模式 | ~100万 QPS | ~150万 QPS | +50% |
| 持久化加载时间 | 基线 | RDB 加载快 2-3 倍 | 🚀 |
| AOF 重写效率 | 基线 | 内存节省 30%+ | 🚀 |

### 11.1.4 其他重要更新

```bash
# 1. Auto-failover 改进（Redis 7.2+）
# 支持自动故障转移中更好的数据保护

# 2. 新增命令
# ZINTERCARD: 计算交集的基数（省内存）
ZINTERCARD 2 set1 set2

# 3. 更好的内存管理
# 使用 jemalloc 优化，减少内存碎片

# 4. 使用 listpack 替代 ziplist，小哈希/小列表内存占用降低约 30%
```

---

## 11.2 RedisJSON 与 Search 模块

### 11.2.1 RedisJSON

RedisJSON 是一个 Redis 模块，提供了原生的 JSON 支持：

```bash
# 安装模块
redis-server --loadmodule /path/to/rejson.so

# 使用 RedisJSON
JSON.SET product:1001 $ '{"name":"iPhone 15","price":5999,"spec":{"cpu":"A16","ram":"8GB"}}'

# 读取完整 JSON
JSON.GET product:1001

# 读取特定路径
JSON.GET product:1001 $.name  # "iPhone 15"
JSON.GET product:1001 $.spec.cpu  # "A16"

# 更新单个字段
JSON.SET product:1001 $.price 4999  # 降价

# 自增数字字段
JSON.NUMINCRBY product:1001 $.price 500

# 获取 JSON 结构中的数组长度
JSON.ARRLEN product:1001 $.tags
```

### 11.2.2 RediSearch

RediSearch 提供了全文搜索功能：

```bash
# 创建索引
FT.CREATE idx:products ON HASH PREFIX 1 product: SCHEMA \
    name TEXT WEIGHT 5.0 \
    description TEXT WEIGHT 1.0 \
    price NUMERIC SORTABLE \
    category TAG

# 写入数据
HSET product:1001 name "iPhone 15" description "最新款智能手机" price 5999 category "手机"
HSET product:1002 name "MacBook Pro" description "高性能笔记本" price 14999 category "电脑"

# 全文搜索
FT.SEARCH idx:products "iPhone" LIMIT 0 10

# 带条件的搜索
FT.SEARCH idx:products "手机" FILTER price 1000 10000 SORTBY price DESC

# 聚合查询
FT.AGGREGATE idx:products "*" GROUPBY 1 @category REDUCE COUNT 0 AS count
# 返回每个分类的商品数量
```

---

## 11.3 Redis 未来趋势

**1. Redis Stack**：将 Redis 从缓存升级为多功能数据平台
- Redis Stack = Redis Core + Search + JSON + TimeSeries + Bloom + Graph
- 一站式解决更多数据需求

**2. 向量搜索**：AI 时代的关键能力
- Redis 正在增强向量相似性搜索能力
- 适合 AI Embedding 存储和检索

**3. 多线程演进**：突破单线程瓶颈
- Redis 6.x 引入了网络 IO 多线程
- 未来可能在命令执行层面支持多线程

**4. 云原生**：Kubernetes 部署成为主流
- Redis Operator 自动化运维
- Redis Cluster on Kubernetes 成熟

---

## 附录 A：常用命令速查

### A.1 连接管理

```bash
# 连接 Redis
redis-cli -h 127.0.0.1 -p 6379 -a password

# 认证
AUTH password

# 选择数据库（0-15）
SELECT 0

# 测试连接
PING  # 返回 PONG
```

### A.2 Key 操作

```bash
# 基本操作
DEL key [key ...]        # 删除 key
EXISTS key               # 检查 key 是否存在
EXPIRE key 3600          # 设置过期时间（秒）
TTL key                  # 查看剩余 TTL（秒）
TYPE key                 # 检查 key 类型
RENAME key newkey        # 重命名

# 遍历
SCAN 0 MATCH pattern:* COUNT 100

# 批量删除（Lua 脚本）
EVAL "return redis.call('DEL', unpack(redis.call('KEYS', ARGV[1])))" 0 "user:*"
# ⚠️ 仅适用小量 key，大量 key 用 SCAN + UNLINK
```

### A.3 String

```bash
SET key value [NX|XX] [EX seconds|PX milliseconds]
GET key
GETSET key newvalue
MSET key1 value1 key2 value2
MGET key1 key2
INCR key
INCRBY key 100
DECR key
DECRBY key 100
INCRBYFLOAT key 1.5
STRLEN key
APPEND key value
```

### A.4 Hash

```bash
HSET hash field value
HGET hash field
HMSET hash field1 value1 field2 value2
HMGET hash field1 field2
HDEL hash field
HEXISTS hash field
HGETALL hash  # ⚠️ 慎用，大 hash 可能阻塞
HSCAN hash 0
HINCRBY hash field 10
HLEN hash
```

### A.5 List

```bash
LPUSH key value [value ...]
RPUSH key value [value ...]
LPOP key
RPOP key
BRPOP key timeout  # 阻塞弹出
BLPOP key timeout
LRANGE key start stop
LLEN key
LTRIM key start stop
```

### A.6 Set

```bash
SADD key member [member ...]
SREM key member [member ...]
SMEMBERS key  # ⚠️ 慎用
SSCAN key 0
SISMEMBER key member
SCARD key  # 元素数量
SINTER key1 key2  # 交集
SUNION key1 key2  # 并集
SDIFF key1 key2   # 差集
SPOP key [count]  # 随机弹出
SRANDMEMBER key [count]  # 随机查看
```

### A.7 Sorted Set

```bash
ZADD key score member [score member ...]
ZREM key member
ZSCORE key member
ZINCRBY key increment member
ZCARD key  # 元素数量
ZRANK key member  # 排名（低到高）
ZREVRANK key member  # 排名（高到低）
ZRANGE key start stop [WITHSCORES]
ZREVRANGE key start stop [WITHSCORES]
ZRANGEBYSCORE key min max
ZREMRANGEBYSCORE key min max
ZINTERSTORE dest numkeys key [key ...]
ZUNIONSTORE dest numkeys key [key ...]
```

### A.8 其他

```bash
# Bitmap
SETBIT key offset value
GETBIT key offset
BITCOUNT key [start end]
BITOP AND|OR|XOR|NOT dest key [key ...]

# HyperLogLog
PFADD key element [element ...]
PFCOUNT key [key ...]
PFMERGE dest source [source ...]

# GEO
GEOADD key longitude latitude member
GEOPOS key member
GEODIST key member1 member2 [km|m|mi|ft]
GEORADIUS key longitude latitude radius unit

# Stream
XADD key * field value [field value ...]
XREAD COUNT 10 STREAMS key 0
XGROUP CREATE key group $
XREADGROUP GROUP group consumer COUNT 10 STREAMS key >
XACK key group id [id ...]
XPENDING key group
```

---

## 附录 B：Redis 配置参考

### B.1 生产环境最小配置

```bash
# redis.conf 生产环境推荐配置

# 网络
bind 0.0.0.0
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

# 安全
requirepass YourStrongPassword
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command KEYS ""
rename-command SHUTDOWN ""

# 内存
maxmemory 8gb
maxmemory-policy allkeys-lru
maxmemory-samples 10

# 持久化
appendonly yes
appendfsync everysec
aof-use-rdb-preamble yes
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 256mb

# 复制
replica-read-only yes
repl-diskless-sync yes
repl-backlog-size 100mb
min-replicas-to-write 1
min-replicas-max-lag 10

# 慢查询
slowlog-log-slower-than 10000
slowlog-max-len 128

# 客户端
maxclients 10000

# 高级配置
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
activerehashing yes
```
📌 Redis 7.0+ 已将 ziplist 替换为 listpack，以上配置项在 7.0+ 中对应更名为 `hash-max-listpack-entries`、`hash-max-listpack-value`、`set-max-listpack-entries`、`zset-max-listpack-entries`、`zset-max-listpack-value`，功能和用法不变。

---

## 结束语

感谢你读完这本手册。

Redis 是一个看似简单、实则深邃的系统。写好 `SET/GET` 只需要一分钟，但要真正在生产环境中用好 Redis，需要理解它的**数据模型、持久化机制、高可用设计、性能调优、监控运维**——这也是本书试图系统化呈现的内容。

**送你三句话：**

1. **始终牢记 Redis 的单线程本质**——一个慢查询可以拖垮整个系统
2. **缓存不是银弹**——穿透、击穿、雪崩、一致性，每个问题都有特定解法
3. **实战是最好的学习**——读完一章，去自己的项目里找到对应的场景实践一下

如果你在阅读或实践中遇到问题，欢迎随时交流。

祝你在高并发系统的道路上越走越远！

---

*Redis 高并发实战手册 · 完*
