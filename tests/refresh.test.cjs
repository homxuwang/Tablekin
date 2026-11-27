const test = require('node:test')
const assert = require('node:assert/strict')
const { load, pageHarness, apiHarness } = require('./helpers.cjs')

test('可见页面启动一个刷新器，处理中跳过，隐藏后停止', async () => {
  const timers = new Map()
  let next = 0
  const refresh = load('utils/live-refresh.js', {}, {
    setInterval(fn) { timers.set(++next, fn); return next },
    clearInterval(id) { timers.delete(id) },
  })
  let reads = 0
  const page = { data: { busy: false } }
  refresh.start(page, () => { reads++ })
  refresh.start(page, () => { reads++ })
  assert.equal(timers.size, 1)
  const tick = Array.from(timers.values())[0]
  tick()
  await Promise.resolve()
  page.data.busy = true
  tick()
  await Promise.resolve()
  assert.equal(reads, 1)
  refresh.stop(page)
  assert.equal(timers.size, 0)
  page.data.busy = false
  tick()
  assert.equal(reads, 1)
})

test('相同页面的并发加载合并，结束后可以重试', async () => {
  const refresh = load('utils/live-refresh.js')
  let resolve
  let reads = 0
  const page = {}
  const task = () => { reads++; return new Promise(done => { resolve = done }) }
  const first = refresh.singleFlight(page, '_load', task)
  const second = refresh.singleFlight(page, '_load', task)
  assert.equal(first, second)
  await Promise.resolve()
  assert.equal(reads, 1)
  resolve('ok')
  await first
  const third = refresh.singleFlight(page, '_load', async () => { reads++; return 'new' })
  assert.equal(await third, 'new')
  assert.equal(reads, 2)
})

test('提醒查询失败明确提示重试，保留已展示提醒', async () => {
  const { page } = pageHarness('pages/orders/orders.js', {
    fetchMyNotifications: async () => { throw new Error('offline') },
    fetchUnreadNotificationCount: async () => 0, friendly: error => error.message,
  })
  page.data.notices = [{ id: 11 }]
  await page.loadNotices()
  assert.equal(page.data.notices.length, 1)
  assert.match(page.data.noticesError, /offline/)
})

test('预约单也计入默认待处理数量', async () => {
  const { api, cloud } = apiHarness()
  const filters = []
  cloud.database.from = table => {
    const query = {
      select() { return query }, in() { return query },
      eq(column, value) { filters.push([column, value]); return query },
      then(resolve) { return Promise.resolve({ data: table === 'orders' ? [{ kitchen_id: 12, status: 'pending' }] : [] }).then(resolve) },
    }
    return query
  }
  const badges = await api.fetchKitchenBadges([12])
  assert.equal(badges[12].pending, 1)
  assert.equal(filters.some(([key]) => key === 'order_date'), false)
})

for (const [file, loader] of [
  ['pages/orders/orders.js', 'loadOrders'],
  ['pages/order-detail/order-detail.js', 'loadDetail'],
]) {
  test(file + ' 隐藏页面取消排队读取', async () => {
    const { page } = pageHarness(file, {})
    let reads = 0, resolve
    page._refreshVisible = true
    page._refreshEpoch = 1
    page[loader] = () => {
      reads++
      return reads === 1 ? new Promise(done => { resolve = done }) : Promise.resolve()
    }
    const first = page.load()
    await Promise.resolve()
    const queued = page.load()
    page.onHide()
    resolve()
    await Promise.all([first, queued])
    assert.equal(reads, 1)
  })
}

test('详情从后台回来立即刷新，不等待下个定时周期', async () => {
  const { page } = pageHarness('pages/order-detail/order-detail.js', {})
  page.orderId = 31
  let reads = 0
  page.loadDetail = async () => { reads++ }
  page.onHide()
  try {
    page.onShow()
    await page._detailRequest
    assert.equal(reads, 1)
  } finally { page.onHide() }
})
