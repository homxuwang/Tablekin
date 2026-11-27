const test = require('node:test')
const assert = require('node:assert/strict')
const { load, pageHarness } = require('./helpers.cjs')

test('已读后的徽标不被旧计数请求覆盖', async () => {
  let spec, resolve
  load('custom-tab-bar/index.js', {
    '../utils/api': { fetchUnreadNotificationCount: () => new Promise(done => { resolve = done }) },
  }, { Component: value => { spec = value } })
  const bar = { ...spec.methods, data: { unreadCount: 3 }, _refreshVisible: true }
  bar.setData = patch => Object.assign(bar.data, patch)
  const old = bar.refreshBadge()
  await Promise.resolve()
  bar.setUnreadCount(0)
  resolve(3)
  await old
  assert.equal(bar.data.unreadCount, 0)
})

for (const file of ['pages/orders/orders.js', 'pages/order-detail/order-detail.js']) {
  test(file + ' 拒单与撤单确认期间阻止重入', () => {
    const { page, calls } = pageHarness(file, {})
    page.orderId = 31
    const event = { currentTarget: { dataset: { id: 31 } } }
    page.reject(event)
    page.cancel(event)
    assert.equal(calls.filter(call => call[0] === 'modal').length, 1)
    assert.ok(page.data.busy || page.data.busyId)
    calls.find(call => call[0] === 'modal')[1].success({ confirm: false })
    assert.equal(!!(page.data.busy || page.data.busyId), false)
  })
}
