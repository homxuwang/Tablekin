const test = require('node:test')
const assert = require('node:assert/strict')
const { load, pageHarness } = require('./helpers.cjs')

test('旧单图兼容、多图去重并以首图为第一张', () => {
  const images = load('utils/dish-images.js')
  assert.deepEqual(Array.from(images.paths({ image_path: 'old' })), ['old'])
  assert.deepEqual(Array.from(images.paths({ image_paths: ['a', 'b', 'a'], image_path: 'b' })), ['b', 'a'])
  assert.deepEqual(Array.from(images.paths({ image_paths: [], image_path: null })), [])
})

test('设置首图移动顺序，删除首图自动使用剩余第一张', () => {
  const images = load('utils/dish-images.js')
  const first = images.cover(['a', 'b', 'c'], 'c')
  assert.deepEqual(Array.from(first), ['c', 'a', 'b'])
  const patch = images.fields(first.filter(p => p !== 'c'))
  assert.equal(patch.image_path, 'a')
  assert.equal(images.fields([]).image_path, null)
  assert.throws(() => images.fields(Array.from({ length: 10 }, (_, i) => 'p' + i)), /9/)
})

function harness(extra = {}) {
  return pageHarness('pages/dish/dish.js', { friendly: e => e.message, ...extra })
}

test('页面首图选择及移除同时维护两个字段', () => {
  const { page } = harness()
  page.data.canEdit = true
  page.data.editMode = true
  page.setImages(['a', 'b'], { a: 'url-a', b: 'url-b' })
  page.setCover({ currentTarget: { dataset: { path: 'b' } } })
  assert.equal(page.data.form.image_path, 'b')
  assert.equal(page.data.imageUrl, 'url-b')
  page.removeImage({ currentTarget: { dataset: { path: 'b' } } })
  assert.equal(page.data.form.image_path, 'a')
})

test('多图上传部分失败保留成功图片，并保持选择顺序', async () => {
  const { page, calls } = harness({
    uploadDishImage: async file => { if (file === 'bad') throw new Error('网络失败'); return file + '-path' },
    signImageUrls: async paths => Object.fromEntries(paths.map(p => [p, 'url-' + p])),
  })
  page.data.canEdit = true
  page.data.editMode = true
  page.setImages(['old'], { old: 'url-old' })
  await page.uploadImages([{ tempFilePath: 'one' }, { tempFilePath: 'bad' }, { tempFilePath: 'two' }])
  assert.deepEqual(Array.from(page.data.form.image_paths), ['old', 'one-path', 'two-path'])
  assert.equal(page.data.form.image_path, 'old')
  assert.equal(page.data.uploading, false)
  assert.match(calls.find(c => c[0] === 'modal')[1].content, /1/)
})

test('上传中禁止保存、删除图片与首图切换', () => {
  const { page } = harness({ createDish: () => { throw new Error('不应保存') } })
  page.data.canEdit = true
  page.data.editMode = true
  page.setImages(['a', 'b'], {})
  page.data.uploading = true
  page.save()
  page.removeImage({ currentTarget: { dataset: { path: 'a' } } })
  page.setCover({ currentTarget: { dataset: { path: 'b' } } })
  assert.equal(page.data.form.image_path, 'a')
  assert.equal(page.data.form.image_paths.length, 2)
})

test('签名失败不清空永久路径且新上传可用临时图预览', async () => {
  const { page } = harness({ uploadDishImage: async () => 'stored', signImageUrls: async () => ({}) })
  page.data.canEdit = true
  page.data.editMode = true
  await page.uploadImages([{ tempFilePath: 'local.jpg' }])
  assert.equal(page.data.form.image_path, 'stored')
  assert.equal(page.data.images[0].url, 'local.jpg')
})

test('保存多图原子提交首图和列表，不将签名URL写入数据库', async () => {
  const calls = []
  const cloud = {
    auth: { getSession: async () => ({ data: { user: { id: 'chef' } } }) },
    database: { from: () => ({ insert: payload => {
      calls.push(payload)
      return { select: async () => ({ data: [{ id: 1, ...payload }] }) }
    } }) },
  }
  const api = load('utils/api.js', { './cloud': { cloud } })
  await api.createDish({ name: '菜', image_paths: ['a', 'b'], image_path: 'b' })
  assert.deepEqual(Array.from(calls[0].image_paths), ['b', 'a'])
  assert.equal(calls[0].image_path, 'b')
  await assert.rejects(api.createDish({ image_paths: Array.from({ length: 10 }, (_, i) => 'p' + i) }), /9/)
  assert.equal(calls.length, 1)
})

test('删除确认或请求在途时不能上传或保存菜品', () => {
  const { page } = harness({ createDish: () => { throw new Error('不应保存') } })
  page.data.canEdit = true
  page.data.editMode = true
  page.data.deleting = true
  assert.equal(page.imageBusy(), true)
  page.save()
  page.onInput({ currentTarget: { dataset: { field: 'name' } }, detail: { value: '改名' } })
  assert.equal(page.data.form.name, '')
})

test('已有8张时只选1张，并且直接上传也不超过9张', async () => {
  let uploaded = 0
  const { page, wx } = harness({
    uploadDishImage: async () => { uploaded += 1; return 'new' },
    signImageUrls: async () => ({}),
  })
  page.data.canEdit = true
  page.data.editMode = true
  page.setImages(Array.from({ length: 8 }, (_, i) => 'old' + i), {})
  wx.chooseMedia = args => { assert.equal(args.count, 1); args.fail({ errMsg: 'cancel' }) }
  page.chooseImage()
  assert.equal(page.data.choosingImages, false)
  await page.uploadImages([{ tempFilePath: 'a' }, { tempFilePath: 'b' }])
  assert.equal(uploaded, 1)
  assert.equal(page.data.form.image_paths.length, 9)
})

test('顾客预览全部可用图片，跳过签名失败图片', () => {
  const { page, wx } = harness()
  page.setImages(['a', 'b', 'c'], { a: 'url-a', c: 'url-c' })
  wx.previewImage = args => {
    assert.equal(args.current, 'url-c')
    assert.deepEqual(Array.from(args.urls), ['url-a', 'url-c'])
  }
  page.previewImages({ currentTarget: { dataset: { path: 'c' } } })
})

test('保存图片字段和配方快照，配方失败后重试不重复创建菜品', async () => {
  let resolveDish
  let payload
  const { page } = harness({
    createDish: input => { payload = input; return new Promise(resolve => { resolveDish = resolve }) },
    replaceDishIngredients: async (id, kitchenId, recipe) => {
      assert.equal(id, 7)
      assert.equal(recipe[0].amount, 2)
      throw new Error('配方失败')
    },
  })
  page.data.canEdit = true
  page.data.editMode = true
  page.data.form.name = '菜'
  page.data.recipe = [{ ingredient_id: 1, amount: '2' }]
  page.setImages(['a', 'b'], { a: 'url-a', b: 'url-b' })
  const task = page.save()
  page.data.recipe[0].amount = '8'
  resolveDish({ id: 7 })
  await task
  assert.deepEqual(Array.from(payload.image_paths), ['a', 'b'])
  assert.equal(payload.image_path, 'a')
  assert.equal(page.data.dishId, 7)
  assert.equal(page.data.saving, false)
})
