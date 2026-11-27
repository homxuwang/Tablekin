const test = require('node:test')
const assert = require('node:assert/strict')
const { pageHarness } = require('./helpers.cjs')

for (const tagsFail of [false, true]) {
  test('进入已有厨房加载菜品与首图，标签' + (tagsFail ? '失败也可点菜' : '正常显示'), async () => {
    const { page } = pageHarness('pages/menu/menu.js', {
      requireUser: async () => ({ id: 'diner' }),
      fetchKitchen: async () => ({ id: 12, name: '家里的厨房' }),
      fetchCategories: async () => [],
      fetchDishes: async () => [{ id: 1, name: '炒蛋', image_path: 'stored-cover', tags: ['家常'] }],
      fetchIngredients: async () => [], fetchRecipes: async () => [], fetchMembers: async () => [],
      listKitchenTags: async () => { if (tagsFail) throw new Error('标签不可用'); return [{ name: '家常' }] },
      buildAvailability: () => ({}),
      signImageUrls: async () => ({ 'stored-cover': 'image-url' }),
      friendly: err => err.message, asArray: v => Array.isArray(v) ? v : [],
    })
    page.kitchenId = 12
    await page.load()
    assert.equal(page.data.error, '')
    assert.equal(page.data.kitchen.name, '家里的厨房')
    assert.equal(page.data.shownDishes[0].imageUrl, 'image-url')
    assert.equal(page.data.allTags.length, tagsFail ? 0 : 1)
  })
}
