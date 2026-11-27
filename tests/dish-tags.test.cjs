const test = require('node:test')
const assert = require('node:assert/strict')
const { load, pageHarness } = require('./helpers.cjs')

// load() 把模块跑在 vm 沙箱里，跨 realm 的数组原型不同，断言前先转成普通值
function plain(value) {
  return JSON.parse(JSON.stringify(value == null ? null : value))
}

// 标签走的是 text[] 列 + 服务端 CHECK：前端负责归一化，服务端负责兜底。
function tagHarness() {
  const calls = []
  const filters = []
  function query() {
    const self = {
      eq(column, value) { filters.push(['eq', column, value]); return self },
      ilike(column, value) { filters.push(['ilike', column, value]); return self },
      in(column, value) { filters.push(['in', column, value]); return self },
      contains(column, value) { filters.push(['contains', column, value]); return self },
      overlaps(column, value) { filters.push(['overlaps', column, value]); return self },
      order() { return self },
      limit() { return self },
      then(resolve) { return Promise.resolve({ data: [] }).then(resolve) },
    }
    return self
  }
  const cloud = {
    auth: { getSession: async () => ({ data: { user: { id: 'chef' } } }) },
    database: {
      rpc: async (name, args) => {
        calls.push({ name, args })
        return { data: { ok: true, kitchen_id: args.p_kitchen_id, scope: 'kitchen', tags: [{ tag: '川菜', dish_count: 3 }, { tag: '辣', dish_count: 1 }] } }
      },
      from: table => ({
        select() {
          calls.push({ name: 'select', table })
          return query()
        },
        insert(payload) {
          calls.push({ name: 'insert', table, payload })
          return { select: async () => ({ data: [Object.assign({ id: 5 }, payload)] }) }
        },
      }),
    },
  }
  return { api: load('utils/api.js', { './cloud': { cloud } }), calls, filters, cloud }
}

test('标签归一化：掐空白、去重、丢掉空值，并保持填写顺序', () => {
  const tags = load('utils/dish-tags.js')
  assert.deepEqual(plain(tags.clean([' 川菜 ', '川菜', '', null, '辣'])), ['川菜', '辣'])
  assert.deepEqual(plain(tags.tags({})), [])
  assert.deepEqual(plain(tags.tags({ tags: ['素', '素'] })), ['素'])
})

test('一次输入多个标签：中英文逗号、顿号、分号都能切开', () => {
  const tags = load('utils/dish-tags.js')
  assert.deepEqual(plain(tags.parse('川菜 辣, 下饭')), ['川菜 辣', '下饭'])
  assert.deepEqual(plain(tags.parse('川菜、辣，下饭；素')), ['川菜', '辣', '下饭', '素'])
  assert.deepEqual(plain(tags.parse('')), [])
})

test('非法标签在提交前就被挡住', () => {
  const tags = load('utils/dish-tags.js')
  assert.equal(tags.validate('川菜'), '')
  assert.match(tags.validate('一二三四五六七八九十十一二三'), /12/)
  assert.match(tags.validate('川菜,辣'), /逗号/)
  assert.match(tags.validate('"辣"'), /引号/)
  assert.match(tags.validate('  '), /不能为空/)
  assert.throws(() => tags.fields(Array.from({ length: 13 }, (_, i) => 't' + i)), /12/)
  assert.throws(() => tags.fields(['川菜,辣']), /逗号/)
})

test('加删标签各归位，超过上限直接拒绝', () => {
  const tags = load('utils/dish-tags.js')
  assert.deepEqual(plain(tags.add(['川菜'], '辣')), ['川菜', '辣'])
  assert.deepEqual(plain(tags.add(['川菜'], '川菜')), ['川菜'])
  assert.deepEqual(plain(tags.remove(['川菜', '辣'], '川菜')), ['辣'])
  const full = Array.from({ length: 12 }, (_, i) => 't' + i)
  assert.throws(() => tags.add(full, '再来一个'), /12/)
})

test('保存菜品时标签跟着图片一起归一化，不会把脏值送到服务端', async () => {
  const { api, calls } = tagHarness()
  await api.createDish({ name: '水煮牛肉', tags: [' 川菜 ', '川菜', '辣'] })
  const payload = calls.find(c => c.name === 'insert').payload
  assert.deepEqual(Array.from(payload.tags), ['川菜', '辣'])
})

test('单标签与多标签搜索：默认要全部满足，可切成任一满足', async () => {
  const { api, filters } = tagHarness()
  await api.searchDishes({ keyword: '牛肉', tags: ['川菜', '辣'] })
  assert.deepEqual(filters[0], ['ilike', 'name', '%牛肉%'])
  assert.deepEqual(filters[1], ['contains', 'tags', ['川菜', '辣']])

  filters.length = 0
  await api.searchDishes({ tags: ['川菜', '辣'], tagMode: 'any' })
  assert.deepEqual(filters[0], ['overlaps', 'tags', ['川菜', '辣']])
})

test('只选标签不输菜名也能搜，两个都不给就不发请求', async () => {
  const { api, calls, filters } = tagHarness()
  await api.searchDishes({ tags: ['素'] })
  assert.deepEqual(plain(filters[0]), ['contains', 'tags', ['素']])

  filters.length = 0
  calls.length = 0
  assert.deepEqual(plain(await api.searchDishes({})), [])
  assert.equal(calls.length, 0)
})

test('标签云走 RPC，厨房内与全部厨房只是 kitchenId 不同', async () => {
  const { api, calls } = tagHarness()
  assert.deepEqual(plain(await api.listKitchenTags(12)), [{ name: '川菜', count: 3 }, { name: '辣', count: 1 }])
  assert.equal(calls[0].args.p_kitchen_id, 12)
  await api.listKitchenTags(0)
  assert.equal(calls[1].args.p_kitchen_id, 0)
})

test('服务端挡下非法标签时给出能看懂的提示', () => {
  const { api } = tagHarness()
  const error = new Error('new row for relation "dishes" violates check constraint "dishes_tags_valid"')
  error.code = '23514'
  assert.match(api.friendly(error), /标签不合规/)
  const other = new Error('violates check constraint "dishes_image_paths_valid"')
  other.code = '23514'
  assert.match(api.friendly(other), /图片/)
})

function dishPage(extra = {}) {
  return pageHarness('pages/dish/dish.js', { friendly: e => e.message, ...extra })
}

test('菜品页：一次加多个标签，去掉已选的，超过上限给出提示', () => {
  const { page, calls } = dishPage()
  page.data.canEdit = true
  page.data.editMode = true
  page.allTags = [{ name: '川菜', count: 2 }, { name: '辣', count: 1 }]

  page.data.tagInput = '川菜, 辣，下饭'
  page.confirmTag()
  assert.deepEqual(Array.from(page.data.tags), ['川菜', '辣', '下饭'])
  assert.equal(page.data.tagInput, '')
  // 建议里只剩还没选上的
  assert.deepEqual(page.data.tagSuggestions, [])

  page.removeTag({ currentTarget: { dataset: { name: '辣' } } })
  assert.deepEqual(Array.from(page.data.tags), ['川菜', '下饭'])

  page.data.tagInput = '一'
  page.confirmTag()
  assert.equal(page.data.tags.length, 3)

  page.data.tags = Array.from({ length: 12 }, (_, i) => 't' + i)
  page.data.tagInput = '再来'
  page.confirmTag()
  assert.match(calls.find(c => c[0] === 'toast')[1].title, /12/)
})

test('菜品页：点已有标签就能复用，保存时带上标签', async () => {
  let payload
  const { page } = dishPage({
    updateDish: async (id, input) => { payload = input; return { id } },
    replaceDishIngredients: async () => {},
  })
  page.data.canEdit = true
  page.data.editMode = true
  page.data.dishId = 5
  page.data.form.name = '水煮牛肉'
  page.allTags = [{ name: '川菜', count: 2 }]
  page.syncTags(page.data.tags)
  page.addSuggestion({ currentTarget: { dataset: { name: '川菜' } } })
  assert.deepEqual(Array.from(page.data.tags), ['川菜'])

  await page.save()
  assert.deepEqual(Array.from(payload.tags), ['川菜'])
})

test('菜单页：标签筛选与分类叠加，只出同时满足的菜', () => {
  const { page } = pageHarness('pages/menu/menu.js', {
    asArray: rows => (Array.isArray(rows) ? rows : []),
    fetchKitchen: async () => ({ id: 1, name: '小厨' }),
    fetchCategories: async () => [],
    fetchDishes: async () => [
      { id: 1, name: '水煮牛肉', category_id: 9, tags: ['川菜', '辣'] },
      { id: 2, name: '开水白菜', category_id: 9, tags: ['川菜'] },
      { id: 3, name: '拍黄瓜', category_id: 8, tags: ['辣'] },
    ],
    fetchIngredients: async () => [],
    fetchRecipes: async () => [],
    fetchMembers: async () => [],
    listKitchenTags: async () => [{ name: '川菜', count: 2 }, { name: '辣', count: 2 }],
    signImageUrls: async () => ({}),
  })
  page.data.dishes = [
    { id: 1, name: '水煮牛肉', category_id: 9, tags: ['川菜', '辣'] },
    { id: 2, name: '开水白菜', category_id: 9, tags: ['川菜'] },
    { id: 3, name: '拍黄瓜', category_id: 8, tags: ['辣'] },
  ]
  page.applyFilter()
  assert.equal(page.data.shownDishes.length, 3)

  page.pickTag({ currentTarget: { dataset: { name: '川菜' } } })
  assert.deepEqual(plain(page.data.shownDishes.map(d => d.id)), [1, 2])

  // 两个标签叠加 = 同时满足
  page.pickTag({ currentTarget: { dataset: { name: '辣' } } })
  assert.deepEqual(plain(page.data.shownDishes.map(d => d.id)), [1])

  page.clearTags()
  assert.equal(page.data.shownDishes.length, 3)
})

test('搜索页：标签与菜名可以叠加，切到任一满足会重新搜', async () => {
  const seen = []
  const { page } = pageHarness('pages/search/search.js', {
    friendly: e => e.message,
    asArray: rows => (Array.isArray(rows) ? rows : []),
    searchDishes: async opts => { seen.push(opts); return [] },
    listKitchenTags: async () => [{ name: '川菜', count: 2 }, { name: '辣', count: 1 }],
    signImageUrls: async () => ({}),
    fetchKitchensByIds: async () => [],
  })
  await page.loadTags()
  assert.deepEqual(plain(page.data.allTags.map(t => t.name)), ['川菜', '辣'])

  page.pickTag({ currentTarget: { dataset: { name: '川菜' } } })
  assert.equal(seen[0].tags[0], '川菜')
  assert.equal(seen[0].tagMode, 'all')
  assert.equal(page.data.allTags[0].picked, true)

  page.switchTagMode({ currentTarget: { dataset: { mode: 'any' } } })
  assert.equal(seen[1].tagMode, 'any')

  // 再点一次同一个标签就是取消
  page.pickTag({ currentTarget: { dataset: { name: '川菜' } } })
  assert.deepEqual(plain(page.data.pickedTags), [])
})
