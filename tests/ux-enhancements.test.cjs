const test = require('node:test')
const assert = require('node:assert/strict')
const { load, pageHarness } = require('./helpers.cjs')

function makeCart() {
  const map = new Map()
  const cart = load('utils/cart.js', {}, {
    wx: {
      getStorageSync: k => map.get(k),
      setStorageSync: (k, v) => map.set(k, structuredClone(v)),
      removeStorageSync: k => map.delete(k),
    },
  })
  return { cart, map }
}

test('菜单页内联增减份数、更新分类角标并在清空时自动关闭抽屉', async () => {
  const { cart } = makeCart()
  const { page } = pageHarness('pages/menu/menu.js', {
    requireUser: async () => ({ id: 'u1' }),
    fetchKitchen: async () => ({ id: 10, name: '小王厨房' }),
    fetchCategories: async () => [{ id: 1, name: '热菜' }, { id: 2, name: '凉菜' }],
    fetchDishes: async () => [
      { id: 101, kitchen_id: 10, category_id: 1, name: '红烧肉', is_available: true },
      { id: 102, kitchen_id: 10, category_id: 2, name: '拍黄瓜', is_available: true },
    ],
    fetchIngredients: async () => [],
    fetchRecipes: async () => [],
    fetchMembers: async () => [],
    listKitchenTags: async () => [],
    buildAvailability: () => ({}),
    signImageUrls: async () => ({}),
    friendly: err => err.message,
    asArray: v => (Array.isArray(v) ? v : []),
  }, { '../../utils/cart': cart })
  page.kitchenId = 10
  await page.load()

  page.addToCart({ currentTarget: { dataset: { id: 101 } } })
  page.addToCart({ currentTarget: { dataset: { id: 101 } } })
  assert.equal(page.data.cartCount, 2)
  assert.equal(page.data.shownDishes[0].cartQty, 2)
  assert.equal(page.data.categories[0].cartQty, 2)
  assert.equal(page.data.categories[1].cartQty, 0)

  page.toggleCartSheet()
  assert.equal(page.data.showCartSheet, true)

  page.decreaseFromCart({ currentTarget: { dataset: { id: 101 } } })
  assert.equal(page.data.cartCount, 1)
  assert.equal(page.data.showCartSheet, true)

  page.decreaseFromCart({ currentTarget: { dataset: { id: 101 } } })
  assert.equal(page.data.cartCount, 0)
  assert.equal(page.data.showCartSheet, false)
})

test('菜单页阻止已下架菜品加入点菜清单，且随机帮选自动跳过下架/缺料菜', async () => {
  const { cart } = makeCart()
  const { page, calls } = pageHarness('pages/menu/menu.js', {
    requireUser: async () => ({ id: 'u1' }),
    fetchKitchen: async () => ({ id: 10, name: '小王厨房' }),
    fetchCategories: async () => [],
    fetchDishes: async () => [
      { id: 101, kitchen_id: 10, name: '停售菜', is_available: false },
      { id: 102, kitchen_id: 10, name: '正常菜', is_available: true, description: '好吃' },
    ],
    fetchIngredients: async () => [],
    fetchRecipes: async () => [],
    fetchMembers: async () => [],
    listKitchenTags: async () => [],
    buildAvailability: () => ({}),
    signImageUrls: async () => ({}),
    friendly: err => err.message,
    asArray: v => (Array.isArray(v) ? v : []),
  }, { '../../utils/cart': cart })
  page.kitchenId = 10
  await page.load()

  page.addToCart({ currentTarget: { dataset: { id: 101 } } })
  assert.equal(page.data.cartCount, 0)
  assert.ok(calls.some(c => c[0] === 'toast' && /已下架/.test(c[1].title)))

  page.pickRandomDish()
  const modal = calls.find(c => c[0] === 'modal')
  assert.ok(modal)
  assert.match(modal[1].title, /正常菜/)
  modal[1].success({ confirm: true })
  assert.equal(page.data.cartCount, 1)
})

test('结算页快捷日期、快捷备注切换与一键上报缺料', async () => {
  const reported = []
  const { cart } = makeCart()
  const { page } = pageHarness('pages/cart/cart.js', {
    todayString: () => '2026-11-26',
    reportShortage: async payload => { reported.push(payload); return true },
    friendly: err => err.message,
  }, { '../../utils/cart': cart })
  page.onLoad({ kitchenId: 10 })
  assert.equal(page.data.quickDates.length, 3)
  assert.equal(page.data.quickDates[1].value, '2026-11-27')

  page.setData({ mealType: 'asap' })
  page.pickQuickDate({ currentTarget: { dataset: { date: '2026-11-27' } } })
  assert.equal(page.data.orderDate, '2026-11-27')
  assert.equal(page.data.mealType, 'point')

  page.appendQuickNote({ currentTarget: { dataset: { note: '少放辣' } } })
  page.appendQuickNote({ currentTarget: { dataset: { note: '不要香菜' } } })
  assert.equal(page.data.note, '少放辣、不要香菜')
  page.appendQuickNote({ currentTarget: { dataset: { note: '少放辣' } } })
  assert.equal(page.data.note, '不要香菜')

  page.setData({
    dinerName: '小明',
    shortage: { problems: [{ ingredientName: '五花肉', needed: 300, stock: 100, dishes: '红烧肉' }] },
  })
  await page.reportCartShortage()
  assert.equal(reported.length, 1)
  assert.equal(reported[0].kitchenId, 10)
})

test('菜品详情页支持直接增减点菜清单份数', () => {
  const { cart } = makeCart()
  const { page } = pageHarness('pages/dish/dish.js', {}, { '../../utils/cart': cart })
  page.kitchenId = 10
  page.dishId = 201
  page.setData({ dishId: 201, kitchenId: 10, form: { name: '番茄炒蛋', is_available: true } })

  page.addDishToCart()
  assert.equal(page.data.cartQty, 1)
  assert.equal(page.data.cartTotal, 1)

  page.addDishToCart()
  assert.equal(page.data.cartQty, 2)

  page.decreaseDishFromCart()
  assert.equal(page.data.cartQty, 1)
})

test('订单页支持按状态筛选并计算进行中数量', () => {
  const { page } = pageHarness('pages/orders/orders.js', {})
  page.allOrders = [
    { id: 1, kitchen_id: 10, status: 'pending' },
    { id: 2, kitchen_id: 10, status: 'accepted' },
    { id: 3, kitchen_id: 10, status: 'done' },
    { id: 4, kitchen_id: 10, status: 'cancelled' },
  ]
  page.applyFilter()
  assert.equal(page.data.activeCount, 2)
  assert.equal(page.data.orders.length, 4)

  page.pickStatusFilter({ currentTarget: { dataset: { status: 'active' } } })
  assert.equal(page.data.orders.length, 2)

  page.pickStatusFilter({ currentTarget: { dataset: { status: 'done' } } })
  assert.equal(page.data.orders.length, 2)
})

test('订单详情页一键再来一单装回清单并跳结算页', () => {
  const { cart } = makeCart()
  const { page, calls } = pageHarness('pages/order-detail/order-detail.js', {}, { '../../utils/cart': cart })
  page.setData({
    kitchenId: 10,
    items: [
      { dish_id: 101, dish_name: '红烧排骨', quantity: 2 },
      { dish_id: 102, dish_name: '番茄炒蛋', quantity: 1 },
    ],
  })
  page.reorder()
  const saved = cart.readCart(10)
  assert.equal(saved[101].count, 2)
  assert.equal(saved[102].count, 1)
  assert.ok(calls.some(c => c[0] === 'navigate' && /\/pages\/cart\/cart\?kitchenId=10/.test(c[1].url)))
})

test('首页支持快捷跳转输码加入页', () => {
  const { page, calls } = pageHarness('pages/home/home.js', {})
  page.goJoin()
  assert.ok(calls.some(c => c[0] === 'navigate' && c[1].url === '/pages/join/join'))
})
