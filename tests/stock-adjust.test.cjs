const test = require('node:test')
const assert = require('node:assert/strict')
const { load } = require('./helpers.cjs')

// 库存相关的云端协议：前端只负责把意图讲清楚，绝不自己算绝对值、绝不直写 stock。
function stockHarness() {
  const calls = []
  function table(name) {
    return {
      insert(payload) {
        calls.push({ name: 'insert', table: name, payload })
        return { select: async () => ({ data: [Object.assign({ id: 7, stock: 0 }, payload)] }) }
      },
      update(payload) {
        calls.push({ name: 'update', table: name, payload })
        return { eq: () => ({ select: async () => ({ data: [] }) }) }
      },
    }
  }
  const cloud = {
    auth: { getSession: async () => ({ data: { user: { id: 'chef' } } }) },
    database: {
      rpc: async (name, args) => {
        calls.push({ name, args })
        return { data: { ok: true, ingredient_id: args.p_ingredient_id, change: 10, balance: 110, replayed: false } }
      },
      from: table,
    },
  }
  return { api: load('utils/api.js', { './cloud': { cloud } }), calls, cloud }
}

test('入库走 delta，让服务端在锁内加，不传绝对值也不传身份', async () => {
  const { api, calls } = stockHarness()
  await api.adjustStock({ ingredientId: 7, mode: 'delta', value: 10, reason: '入库' })
  assert.equal(calls[0].name, 'adjust_stock_atomic')
  assert.equal(calls[0].args.p_mode, 'delta')
  assert.equal(calls[0].args.p_value, 10)
  assert.equal(calls[0].args.p_expected_stock, null)
  assert.equal('p_owner_id' in calls[0].args, false)
  assert.equal('p_actor_id' in calls[0].args, false)
})

test('盘点走 recount，把盘点前页面上的值一并交给服务端核对', async () => {
  const { api, calls } = stockHarness()
  await api.adjustStock({ ingredientId: 7, mode: 'recount', value: 125, expectedStock: 100, reason: '盘点校正' })
  assert.equal(calls[0].args.p_mode, 'recount')
  assert.equal(calls[0].args.p_value, 125)
  assert.equal(calls[0].args.p_expected_stock, 100)
})

test('前端不再直写 stock，也不自己插库存流水', async () => {
  const { api, calls } = stockHarness()
  await api.adjustStock({ ingredientId: 7, mode: 'delta', value: 3 })
  const wrote = calls.filter(call => call.name === 'update' || (call.name === 'insert' && call.table === 'stock_logs'))
  assert.deepEqual(wrote, [])
})

test('幂等键原样透传，响应丢失后重试可以安全重发', async () => {
  const { api, calls } = stockHarness()
  await api.adjustStock({ ingredientId: 7, mode: 'delta', value: 3, requestId: 'in-7-123' })
  assert.equal(calls[0].args.p_request_id, 'in-7-123')
})

test('新建食材先落 0，再走盘点事务记初始库存', async () => {
  const { api, calls } = stockHarness()
  await api.createIngredient({ kitchen_id: 15, name: '鸡蛋', unit: '个', stock: 10 })
  assert.equal(calls[0].name, 'insert')
  assert.equal('stock' in calls[0].payload, false)
  assert.equal(calls[1].name, 'adjust_stock_atomic')
  assert.equal(calls[1].args.p_mode, 'recount')
  assert.equal(calls[1].args.p_expected_stock, 0)
  assert.equal(calls[1].args.p_value, 10)
})

test('初始库存为 0 时不多发一次请求', async () => {
  const { api, calls } = stockHarness()
  await api.createIngredient({ kitchen_id: 15, name: '盐', unit: '克', stock: 0 })
  assert.equal(calls.length, 1)
})

test('盘点撞上接单扣库时，把两个数字都讲清楚让用户刷新', () => {
  const { api } = stockHarness()
  const text = api.friendly(new Error('stock_changed:115:100'))
  assert.match(text, /115/)
  assert.match(text, /100/)
  assert.match(text, /刷新/)
})

test('邀请码走拥有者专用接口，不再从厨房行里读', async () => {
  const { api, calls } = stockHarness()
  assert.equal(typeof api.getKitchenInvite, 'function')
  assert.equal(typeof api.resetKitchenInvite, 'function')
  await api.getKitchenInvite(15)
  await api.resetKitchenInvite(15)
  assert.deepEqual(calls.map(call => call.name), ['get_kitchen_invite', 'reset_kitchen_invite'])
  assert.equal(calls[0].args.p_kitchen_id, 15)
})

test('盘点未传 expectedStock 时不能被默认成 0', async () => {
  const { api, calls } = stockHarness()
  await assert.rejects(api.adjustStock({ ingredientId: 7, mode: 'recount', value: 10 }), /盘点前/)
  assert.equal(calls.length, 0)
})

test('初始库存失败仍返回已创建食材信息，页面可避免重复创建', async () => {
  const { api, cloud } = stockHarness()
  cloud.database.rpc = async () => ({ error: { message: 'timeout' } })
  await assert.rejects(api.createIngredient({ kitchen_id: 15, name: '鸡蛋', stock: 10 }), err => {
    assert.equal(err.ingredient.id, 7)
    assert.equal(err.initialStock, 10)
    return true
  })
})

test('云端新的库存与邀请错误码有中文提示', () => {
  const { api } = stockHarness()
  assert.match(api.friendly(new Error('not_kitchen_owner')), /拥有者/)
  assert.match(api.friendly(new Error('ingredient_not_found')), /食材/)
})
