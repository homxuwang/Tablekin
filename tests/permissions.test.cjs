const test = require('node:test')
const assert = require('node:assert/strict')
const { pageHarness } = require('./helpers.cjs')

test('共有人分享成员页时不会生成管理邀请', () => {
  const { page } = pageHarness('pages/members/members.js', {})
  page.kitchenId = 12
  page.data.kitchen = { name: '我家' }
  page.data.inviteCode = 'secret'
  page.data.isOwner = false
  assert.equal(page.onShareAppMessage().path, '/pages/menu/menu?kitchenId=12')
})

test('只有拥有者生成邀请卡片', () => {
  const { page } = pageHarness('pages/members/members.js', {})
  page.kitchenId = 12
  page.data.kitchen = { name: '我家' }
  page.data.inviteCode = 'secret'
  page.data.isOwner = true
  assert.match(page.onShareAppMessage().path, /join\/join\?code=secret/)
})

test('共有人不能提交厨房资料修改', async () => {
  let writes = 0
  const { page } = pageHarness('pages/kitchen-form/kitchen-form.js', {
    updateKitchen: () => { writes++; return Promise.resolve({ id: 12 }) },
  })
  page.data.editMode = true
  page.data.isOwner = false
  page.data.form.name = '新名称'
  page.save()
  await Promise.resolve()
  assert.equal(writes, 0)
})
