# 家庭厨房前端联调 Implementation Plan

> For agentic workers: 使用 executing-plans 在当前会话执行，每步先验证失败再修改。

**Goal:** 对接现有 RPC，补齐跨日期点菜、站内提醒和状态刷新。

**Architecture:** 保留现有页面和云 SDK。新增纯日期模块及可见页面刷新工具，数据层负责 RPC 参数，页面负责展示与交互。

**Tech Stack:** 微信小程序 JS/WXML/WXSS、WorkBuddy Cloud SDK、node:test。

### 1. 日期与协议
- [x] tests/helpers.cjs 提供可注入云端响应及微信页面宿主。
- [x] tests/integration.test.cjs 断言指定未来日期传入 p_order_date、无效区间拒绝提交、空已读数组不会误标全部，运行 `node --test tests/*.test.cjs` 确认失败。
- [x] utils/meal-time.js 使用 UTC+8 计算今天，验证真实日期及 HH:mm；utils/api.js 使用用户选择日期，提供日期时间展示，区分空数组和未指定的全部已读。
- [x] 运行测试确认通过。

### 2. 日期交互与终止状态
- [x] 测试 cart 的日期选择、未来日期尽快切换、午夜默认时间，以及详情 cancelled/rejected 提示。
- [x] 修改 cart JS/WXML/WXSS 的日期选择；home/orders/order-detail 使用统一就餐日期时间；修正进度与撤单后展示。
- [x] 核对 UI 绑定及测试。

### 3. 提醒与刷新
- [x] 测试全部已读不受显示条数限制、单条标记、标记失败保留提示、可见刷新停止及请求合并。
- [x] utils/live-refresh.js 管理定时器；custom-tab-bar 显示徽标；orders 支持真实数量、加载更多及错误重试；详情支持自动/下拉刷新。
- [x] chef/manage 不再以今天过滤待处理订单，站内提醒只按会话本人读取。
- [x] 运行全部测试、JS 语法/JSON/页面绑定检查，进行独立代码审查并处理问题。

当前目录没有 Git 仓库，因此不创建分支、提交或 PR。结束时提供本地改动和云端联调检查清单。

