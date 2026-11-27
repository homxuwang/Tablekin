const test = require('node:test')
const assert = require('node:assert/strict')
const { load, pageHarness } = require('./helpers.cjs')

test('删除数字必须完全匹配，取消或输错均不会放行', async () => {
  const { confirmDelete } = load('utils/confirm-delete.js')
  const makeWx = mode => ({
    showModal: options => {
      if (!options.editable) { options.success({ confirm: mode !== 'cancel' }); return }
      const code = options.title.match(/\b\d{4}\b/)[0]
      options.success({ confirm: mode !== 'cancel', content: mode === 'correct' ? code : '错误' })
    },
    showToast() {},
  })
  assert.equal(await confirmDelete({ title: '删除菜品', content: '无法恢复' }, makeWx('wrong')), false)
  assert.equal(await confirmDelete({ title: '删除菜品', content: '无法恢复' }, makeWx('cancel')), false)
  assert.equal(await confirmDelete({ title: '删除菜品', content: '无法恢复' }, makeWx('correct')), true)
})

function manage(api = {}) {
  const result = pageHarness('pages/manage/manage.js', { friendly: e => e.message, ...api })
  result.page.kitchenId = 12
  result.page.setData({ loading: false, canManage: true,
    dishes: [{ id: 1, name: '番茄炒蛋' }, { id: 2, name: '红烧肉' }],
    categories: [{ id: 3, name: '热菜' }, { id: 4, name: '凉菜' }],
  })
  return result
}

test('当前页展开排序并保留名称，取消不修改列表也不导航', () => {
  const { page, calls } = manage()
  page.openSort({ currentTarget: { dataset: { kind: 'dishes' } } })
  assert.equal(page.data.sortItems[0].name, '番茄炒蛋')
  page.sortTop({ currentTarget: { dataset: { id: 2 } } })
  assert.equal(page.data.sortItems[0].name, '红烧肉')
  page.sortCancel()
  assert.equal(page.data.sortKind, '')
  assert.equal(page.data.dishes[0].name, '番茄炒蛋')
  assert.equal(calls.some(call => call[0] === 'navigate'), false)
})

test('当前页保存分类顺序；请求期间禁止删除和重复保存', async () => {
  let release
  let count = 0
  const { page } = manage({ reorderKitchenItems: () => { count += 1; return new Promise(r => { release = r }) } })
  page.openSort({ currentTarget: { dataset: { kind: 'categories' } } })
  page.sortTop({ currentTarget: { dataset: { id: 4 } } })
  const saving = page.sortSave()
  page.removeCategory({ currentTarget: { dataset: { id: 3 } } })
  await page.sortSave()
  assert.equal(count, 1)
  release({ ok: true })
  await saving
  assert.equal(page.data.categories[0].name, '凉菜')
  assert.equal(page.data.sortKind, '')
})

test('分类删除输错不调用API，且验证过程不能重复发起', async () => {
  let deleted = 0
  const { page, wx } = manage({ deleteCategory: async () => { deleted += 1 } })
  let dialog
  wx.showModal = options => {
    if (!options.editable) options.success({ confirm: true })
    else dialog = options
  }
  const first = page.removeCategory({ currentTarget: { dataset: { id: 3 } } })
  await page.removeCategory({ currentTarget: { dataset: { id: 3 } } })
  dialog.success({ confirm: true, content: 'invalid' })
  await first
  assert.equal(deleted, 0)
  assert.equal(page.data.categoryBusy, false)
})

test('删除菜品输入正确数字才执行，API在途期间拒绝重复点击', async () => {
  let count = 0
  let release
  const { page, wx } = pageHarness('pages/dish/dish.js', {
    friendly: e => e.message,
    deleteDish: () => { count += 1; return new Promise(r => { release = r }) },
  })
  page.setData({ canEdit: true, editMode: true, dishId: 12 })
  page.data.form.name = '番茄炒蛋'
  wx.showModal = options => options.success({ confirm: true, content: options.editable ? options.title.match(/\b\d{4}\b/)[0] : '' })
  const task = page.remove()
  await Promise.resolve()
  await Promise.resolve()
  await Promise.resolve()
  await page.remove()
  assert.equal(count, 1)
  assert.equal(page.data.deleting, true)
  release()
  await task
  assert.equal(page.data.canEdit, false)
  assert.equal(page.data.deleting, false)
})

test('当前页内拖动换位，取消手势恢复，离开页面停止滚动定时器', () => {
  const { page, wx } = manage()
  page.openSort({ currentTarget: { dataset: { kind: 'dishes' } } })
  wx.createSelectorQuery = () => {
    const query = {
      in: () => query, select: () => query, boundingClientRect: () => query,
      exec: callback => callback([{ top: 100, bottom: 300, height: 200 }, { height: 100 }]),
    }
    return query
  }
  page.sortTouchStart({ touches: [{ clientY: 150 }] })
  page.sortStartDrag({ currentTarget: { dataset: { id: 1 } } })
  try {
    page.sortTouchMove({ touches: [{ clientY: 250 }] })
    assert.equal(page.data.sortItems[0].name, '红烧肉')
    page.sortCancelDrag()
    assert.equal(page.data.sortItems[0].name, '番茄炒蛋')
    assert.equal(page.data.sortDirty, false)
    page.onHide()
    assert.equal(page._sortTimer, null)
  } finally { page.sortEndDrag() }
})

test('内联排序失败保留草稿，刷新页面不会丢弃未保存顺序', async () => {
  const { page } = manage({ reorderKitchenItems: async () => { throw new Error('sort_conflict') } })
  page.openSort({ currentTarget: { dataset: { kind: 'dishes' } } })
  page.sortTop({ currentTarget: { dataset: { id: 2 } } })
  await page.sortSave()
  await page.load()
  assert.equal(page.data.sortError, 'sort_conflict')
  assert.equal(page.data.sortItems[0].name, '红烧肉')
  assert.equal(page.data.dishes[0].name, '番茄炒蛋')
})

for (const kind of ['ingredient', 'kitchen']) {
  test(kind + '删除第二次验证取消时保留数据并释放锁', async () => {
    let deleted = 0
    const api = { friendly: err => err.message, deleteIngredient: async () => { deleted += 1 }, deleteKitchen: async () => { deleted += 1 } }
    const { page, wx } = pageHarness(kind === 'ingredient' ? 'pages/ingredients/ingredients.js' : 'pages/kitchen-form/kitchen-form.js', api)
    page.setData({ list: [{ id: 1, name: '鸡蛋' }], editMode: true, isOwner: true })
    wx.showModal = options => options.success({ confirm: !options.editable })
    if (kind === 'ingredient') await page.removeItem({ currentTarget: { dataset: { id: 1 } } })
    else await page.removeKitchen()
    assert.equal(deleted, 0)
    if (kind === 'ingredient') assert.equal(page._stockDialog, false)
    else assert.equal(page.data.deleting, false)
  })
}
