const test = require('node:test')
const assert = require('node:assert/strict')
const { apiHarness, pageHarness } = require('./helpers.cjs')
const meal = require('../utils/meal-time')
const future = meal.maxOrderDate()

test('预约日期传到 RPC，顾客不传 owner/diner 身份', async () => {
  const { api, calls } = apiHarness()
  await api.createOrder({ kitchenId: 12, orderDate: future, mealTimeType: 'point', mealTimeStart: '18:30', items: [{ dish_id: 7, quantity: 2 }] })
  assert.equal(calls[0].args.p_order_date, future)
  assert.equal(calls[0].args.p_items[0].quantity, 2)
  assert.equal('owner_id' in calls[0].args, false)
  assert.equal('diner_id' in calls[0].args, false)
})

test('倒置时间段不会被悄悄改成不限', async () => {
  const { api, calls } = apiHarness()
  await assert.rejects(api.createOrder({ kitchenId: 12, orderDate: future, mealTimeType: 'range', mealTimeStart: '19:00', mealTimeEnd: '18:00', items: [{ dish_id: 7 }] }), /结束时间/)
  assert.equal(calls.length, 0)
})

test('不存在的日期不能发给服务端', async () => {
  const { api, calls } = apiHarness()
  await assert.rejects(api.createOrder({ kitchenId: 12, orderDate: '2099-02-30', mealTimeType: 'point', mealTimeStart: '18:00', items: [{ dish_id: 7 }] }), /日期/)
  assert.equal(calls.length, 0)
})

test('空已读数组是无操作，不会误标所有提醒', async () => {
  const { api, calls } = apiHarness()
  assert.equal(await api.markNotificationsRead([]), 0)
  assert.equal(calls.length, 0)
})

test('显式全部已读使用 null，单条已读传 ID', async () => {
  const { api, calls } = apiHarness()
  await api.markNotificationsRead()
  await api.markNotificationsRead([9])
  assert.equal(calls[0].args.p_ids, null)
  assert.deepEqual(Array.from(calls[1].args.p_ids), [9])
})

test('拒单进度以拒单终止，不再等待出餐', () => {
  const { api } = apiHarness()
  const steps = api.orderSteps({ status: 'rejected', decided_at: 'stamp' })
  assert.equal(steps[steps.length - 1].key, 'rejected')
  assert.equal(steps[steps.length - 1].done, true)
})

test('撤单进度对顾客和大厨使用中性文案', () => {
  const { api } = apiHarness()
  assert.equal(api.orderSteps({ status: 'cancelled' })[1].label, '点菜人已撤回')
})

test('全部已读覆盖未显示的提醒', async () => {
  const args = []
  const { page } = pageHarness('pages/orders/orders.js', {
    markNotificationsRead: async (...value) => args.push(value),
    fetchMyNotifications: async () => [], fetchUnreadNotificationCount: async () => 0,
  })
  page.data.notices = [{ id: 1 }]
  page.data.unreadCount = 9
  await page.dismissNotices()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(args[0].length, 0)
  assert.equal(page.data.unreadCount, 0)
})

test('打开提醒标记这一条并跳到订单', async () => {
  const args = []
  const { page, calls } = pageHarness('pages/orders/orders.js', { markNotificationsRead: async ids => args.push(Array.from(ids)) })
  page.data.notices = [{ id: 11, order_id: 31 }]
  page.data.unreadCount = 1
  await page.openNotice({ currentTarget: { dataset: { id: 31, noticeId: 11 } } })
  assert.deepEqual(args, [[11]])
  assert.equal(page.data.unreadCount, 0)
  assert.match(calls.find(call => call[0] === 'navigate')[1].url, /id=31/)
})

test('全部已读失败保留未读记录', async () => {
  const { page } = pageHarness('pages/orders/orders.js', {
    markNotificationsRead: async () => { throw new Error('network') }, friendly: err => err.message,
  })
  page.data.notices = [{ id: 11 }]
  page.data.unreadCount = 1
  await page.dismissNotices()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(page.data.notices.length, 1)
  assert.equal(page.data.unreadCount, 1)
})
