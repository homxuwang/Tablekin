# Tablekin（吃好喝好）— iOS 版（Flutter）

面向 iOS 打造的家人朋友互点菜、实时接单与家庭厨房协作应用。

## 核心特性

- **点菜（顾客视角）**：发现公开厨房、上次点菜快速续点、进行中订单实时进度、菜名/厨房/多标签搜索、邀请码一键加入私密厨房。
- **点单与库存联动**：菜单页直接内联 `- / +` 份数步进器，自动计算可做份数；缺料菜品可一键提醒大厨补货；iOS 原生日期/时间选择器支持「尽快」「时间点」「时间段」。
- **下厨与管理（大厨视角）**：新建/编辑厨房、食材仓库（入库/防并发冲突盘点/流水明细/低库存预警）、菜品多图上传与配方绑定、**原生拖拽排序分类与菜品**、成员与邀请码分享/换码。
- **实时订单流转**：支持「我点的 / 我收到的」切换，大厨一键「收到 → 接单（自动原子扣库存）→ 已出餐」或「做不了」，点菜人实时追踪垂直进度轴。
- **开箱即用 + 云端无缝切换**：内置「本地体验模式」（含模拟好友下单工具），同时内置 **Supabase 云端同步** 适配器，可在 App 内「账号与云端连接」页面随时接入自己的 Supabase 项目。

## 后端方案评估（为什么首选 Supabase）

| 方案 | 好友互点 & 实时接单 | 事务与库存扣减 | 跨账号协作 | 综合结论 |
| --- | --- | --- | --- | --- |
| **Supabase (PostgreSQL)** | 原生 Realtime 实时推送 | 行级锁原子事务 + RLS，100% 匹配原业务 | 邮箱/验证码/Apple 登录 + 邀请码无门槛 | **最推荐（已内置完整适配与建表 SQL）** |
| Apple CloudKit | 依赖静默推送 | Public DB 缺乏关系事务锁 | 仅限 Apple ID，CKShare 体验受限 | 不推荐作为主后端 |
| Cloudflare + D1 | 需自建 Durable Objects / WebSocket | SQLite 写锁 + 需自建 Auth/RLS/R2 胶水层 | 需自研鉴权 | 工程维护成本偏高 |

项目通过 [`KitchenBackend`](lib/services/kitchen_backend.dart) 抽象层解耦后端，未来如需扩展 Cloudflare Workers + D1 只需新增一个实现类，无需改动任何 UI 代码。

## 快速运行（macOS + Xcode）

1. **安装依赖**
   ```bash
   flutter pub get
   ```
2. **启动 iOS 模拟器或真机**
   ```bash
   flutter run -d ios
   ```
3. **接入你自己的 Supabase 项目（开启多人真机互点）**
   - 在 [Supabase](https://supabase.com) 创建免费项目。
   - 打开 **SQL Editor**，复制并执行 [`supabase/migrations/001_init.sql`](supabase/migrations/001_init.sql)。
   - 在 App 首页右上角点击「体验版」→ 填入 **Project URL** 与 **Anon Key** 即可切换至云端同步（或启动时通过 `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` 注入）。
