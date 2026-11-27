const test = require('node:test')
const assert = require('node:assert/strict')
const { load, apiHarness, pageHarness } = require('./helpers.cjs')

test('移动、置顶与置底保留全部项目且不修改原列表', () => {
  const sort = load('utils/menu-sort.js')
  const rows = [{ id: 1 }, { id: 2 }, { id: 3 }]
  assert.deepEqual(Array.from(sort.move(rows, 3, 0), r => r.id), [3, 1, 2])
  assert.deepEqual(Array.from(sort.move(rows, 1, 2), r => r.id), [2, 3, 1])
  assert.deepEqual(rows.map(r => r.id), [1, 2, 3])
  assert.equal(sort.move(rows, 99, 0).length, 3)
  assert.equal(sort.move([], 1, 0).length, 0)
})

test('拖动目标考虑滚动偏移并限制上下边界', () => {
  const sort = load('utils/menu-sort.js')
  assert.equal(sort.targetIndex(150, 100, 200, 50, 10), 5)
  assert.equal(sort.targetIndex(-500, 100, 0, 50, 10), 0)
  assert.equal(sort.targetIndex(5000, 100, 0, 50, 10), 9)
})

test('排序一次RPC提交所有ID及原顺序，不传用户身份', async () => {
  const { api, calls } = apiHarness()
  await api.reorderKitchenItems(12, 'dishes', [3, 1, 2], [1, 2, 3])
  assert.equal(calls[0].name, 'reorder_kitchen_items')
  assert.deepEqual(JSON.parse(JSON.stringify(calls[0].args)), {
    p_kitchen_id: 12, p_kind: 'dishes', p_ids: [3, 1, 2], p_expected_ids: [1, 2, 3],
  })
  await assert.rejects(api.reorderKitchenItems(12, 'dishes', [1, 1], [1, 2]))
  await assert.rejects(api.reorderKitchenItems(12, 'orders', [1], [1]))
  assert.equal(calls.length, 1)
})

function fixture(extra = {}) {
  return pageHarness('pages/sort/sort.js', {
    friendly: err => err.message,
    requireUser: async () => ({ id: 'chef' }),
    fetchKitchen: async () => ({ id: 12, owner_id: 'chef' }),
    fetchMembers: async () => [],
    fetchDishes: async () => [{ id: 1, name: '甲' }, { id: 2, name: '乙' }, { id: 3, name: '丙' }],
    fetchCategories: async () => [{ id: 4, name: '凉菜' }, { id: 5, name: '热菜' }],
    ...extra,
  })
}

test('置顶预览不写云端，保存失败保留草稿和原顺序', async () => {
  let args
  const { page } = fixture({ reorderKitchenItems: async (...value) => { args = value; throw new Error('sort_conflict') } })
  page.kitchenId = 12
  page.kind = 'dishes'
  await page.load()
  page.toTop({ currentTarget: { dataset: { id: 3 } } })
  assert.equal(args, undefined)
  assert.equal(page.data.items[0].id, 3)
  await page.save()
  assert.deepEqual(Array.from(args[3]), [1, 2, 3])
  assert.equal(page.data.items[0].id, 3)
  assert.equal(page.data.saving, false)
  assert.equal(page.data.dirty, true)
})

test('非成员不能读取管理列表和排序', async () => {
  const { page } = fixture({ fetchKitchen: async () => ({ owner_id: 'other' }), fetchDishes: async () => { throw new Error('不应读取') } })
  page.kitchenId = 12
  page.kind = 'dishes'
  await page.load()
  assert.equal(page.data.canManage, false)
  assert.equal(page.data.items.length, 0)
})

test('保存期间禁止二次保存和更改顺序', async () => {
  let resolve
  let count = 0
  const { page } = fixture({ reorderKitchenItems: () => { count += 1; return new Promise(r => { resolve = r }) } })
  page.kitchenId = 12
  page.kind = 'categories'
  await page.load()
  page.toTop({ currentTarget: { dataset: { id: 5 } } })
  const saving = page.save()
  page.toBottom({ currentTarget: { dataset: { id: 5 } } })
  await page.save()
  assert.equal(count, 1)
  assert.equal(page.data.items[0].id, 5)
  resolve({ ok: true })
  await saving
  assert.equal(page.data.dirty, false)
})

test('长按拖动按触点换位，触摸取消恢复本次拖动前顺序', async () => {
  const { page, wx } = fixture()
  page.kitchenId = 12
  page.kind = 'dishes'
  await page.load()
  wx.createSelectorQuery = () => {
    const query = {
      in: () => query, select: () => query, boundingClientRect: () => query,
      exec: callback => callback([{ top: 100, bottom: 250, height: 150 }, { height: 50 }]),
    }
    return query
  }
  page.touchStart({ touches: [{ clientY: 125 }] })
  page.startDrag({ currentTarget: { dataset: { id: 1 } } })
  try {
    page.touchMove({ touches: [{ clientY: 225 }] })
    assert.deepEqual(Array.from(page.data.items, r => r.id), [2, 3, 1])
    assert.equal(page.data.dragging, true)
    page.cancelDrag()
    assert.deepEqual(Array.from(page.data.items, r => r.id), [1, 2, 3])
    assert.equal(page.data.dirty, false)
    assert.equal(page._scrollTimer, null)
  } finally { page.endDrag() }
})

test('抬手后到达的尺寸查询不能重新启动拖动', async () => {
  const { page, wx } = fixture()
  page.kitchenId = 12
  page.kind = 'dishes'
  await page.load()
  let measured
  wx.createSelectorQuery = () => {
    const query = { in: () => query, select: () => query, boundingClientRect: () => query, exec: cb => { measured = cb } }
    return query
  }
  page.touchStart({ touches: [{ clientY: 125 }] })
  page.startDrag({ currentTarget: { dataset: { id: 1 } } })
  page.endDrag()
  measured([{ top: 100, bottom: 250, height: 150 }, { height: 50 }])
  assert.equal(page.data.dragging, false)
  assert.equal(page._scrollTimer, null)
})

test('接口未部署时明确提示，不退回逐条更新', async () => {
  const { api, cloud } = apiHarness()
  cloud.database.rpc = async () => ({ error: { code: 'PGRST202' } })
  await assert.rejects(api.reorderKitchenItems(12, 'categories', [2, 1], [1, 2]), /排序服务尚未上线/)
})

for (const thrown of [false, true]) {
  test('缺少错误码的云端函数缺失' + (thrown ? '异常' : '响应') + '也翻译为中文', async () => {
    const { api, cloud } = apiHarness()
    const error = { message: 'Could not find the function public.reorder_kitchen_items(p_expected_ids, p_ids, p_kind, p_kitchen_id) in the schema cache' }
    cloud.database.rpc = async () => { if (thrown) throw error; return { error } }
    await assert.rejects(api.reorderKitchenItems(12, 'categories', [2, 1], [1, 2]), /排序服务尚未上线/)
  })
}
