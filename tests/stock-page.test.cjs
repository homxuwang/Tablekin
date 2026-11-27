const test = require('node:test')
const assert = require('node:assert/strict')
const { pageHarness } = require('./helpers.cjs')

test('入库响应丢失后保留操作并用同一幂等键重试', async () => {
  const attempts = [], seen = new Set()
  let balance = 100
  const { page, calls, storage } = pageHarness('pages/ingredients/ingredients.js', {
    adjustStock: async operation => {
      attempts.push(structuredClone(operation))
      if (!seen.has(operation.requestId)) { seen.add(operation.requestId); balance += operation.value }
      if (attempts.length === 1) throw new Error('request:fail timeout')
      return { balance, replayed: true }
    }, friendly: err => err.message,
  })
  page._stockStorageKey = 'stock-chef-12'
  page.data.list = [{ id: 7, name: '鸡蛋', unit: '个', stockNum: 100 }]
  page.load = async () => {}
  page.stockIn({ currentTarget: { dataset: { id: 7 } } })
  await calls.find(call => call[0] === 'modal')[1].success({ confirm: true, content: '10' })
  await new Promise(resolve => setImmediate(resolve))
  assert.ok(page.data.pendingStock)
  assert.ok(storage.get('stock-chef-12'))
  await page.retryStock()
  assert.equal(attempts[0].requestId, attempts[1].requestId)
  assert.equal(balance, 110)
  assert.equal(page.data.pendingStock, null)
  assert.equal(storage.has('stock-chef-12'), false)
})

test('盘点冲突清除待确认操作并刷新库存', async () => {
  let refreshed = 0
  const { page, calls } = pageHarness('pages/ingredients/ingredients.js', {
    adjustStock: async () => { throw new Error('stock_changed:115:100') }, friendly: err => err.message,
  })
  page._stockStorageKey = 'stock-chef-12'
  page.data.list = [{ id: 7, name: '鸡蛋', unit: '个', stockNum: 100 }]
  page.load = async () => { refreshed++ }
  page.recount({ currentTarget: { dataset: { id: 7 } } })
  await calls.find(call => call[0] === 'modal')[1].success({ confirm: true, content: '120' })
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(page.data.pendingStock, null)
  assert.equal(refreshed, 1)
})

test('新建后初始库存失败，表单转为编辑该食材而不是再次创建', async () => {
  const error = new Error('timeout')
  error.ingredient = { id: 7, name: '鸡蛋' }
  error.initialStock = 10
  const { page } = pageHarness('pages/ingredients/ingredients.js', {
    createIngredient: async () => { throw error }, friendly: err => err.message,
  })
  page.data.form = { id: 0, name: '鸡蛋', unit: '个', stock: '10' }
  page.load = async () => {}
  page.saveForm()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(page.data.form.id, 7)
  assert.equal(page.data.saving, false)
})

test('有待确认入库时不允许新建操作覆盖原幂等编号', async () => {
  let writes = 0
  const { page } = pageHarness('pages/ingredients/ingredients.js', {
    createIngredient: async () => { writes++; return { id: 8 } }, friendly: err => err.message,
  })
  page.load = async () => {}
  page.data.pendingStock = { ingredientId: 7, requestId: 'original' }
  page.data.form = { id: 0, name: '盐', stock: '10' }
  page.saveForm()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(writes, 0)
  assert.equal(page.data.pendingStock.requestId, 'original')
})

test('实际盘点值等于旧页面值时仍交给服务端检查冲突', async () => {
  let reads = 0
  const { page, calls } = pageHarness('pages/ingredients/ingredients.js', {
    adjustStock: async () => { reads++; throw new Error('stock_changed:80:100') }, friendly: err => err.message,
  })
  page.data.list = [{ id: 7, name: '鸡蛋', unit: '个', stockNum: 100 }]
  page.load = async () => {}
  page.recount({ currentTarget: { dataset: { id: 7 } } })
  await calls.find(call => call[0] === 'modal')[1].success({ confirm: true, content: '100' })
  assert.equal(reads, 1)
})

test('初始库存失败恢复提交时快照，不将新ID混入另一张表单', async () => {
  let reject
  const { page } = pageHarness('pages/ingredients/ingredients.js', {
    createIngredient: () => new Promise((_, fail) => { reject = fail }), friendly: err => err.message,
  })
  page.load = async () => {}
  page.data.form = { id: 0, name: '鸡蛋', unit: '个', stock: '10' }
  page.saveForm()
  page.data.form = { id: 42, name: '盐', unit: '克', stock: '20' }
  const err = new Error('timeout')
  err.ingredient = { id: 7 }
  err.initialStock = 10
  reject(err)
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(page.data.form.id, 7)
  assert.equal(page.data.form.name, '鸡蛋')
})
