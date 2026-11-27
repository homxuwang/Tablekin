const test = require('node:test')
const assert = require('node:assert/strict')
const { pageHarness } = require('./helpers.cjs')

test('邀请码加载失败有可重试提示', async () => {
  const { page } = pageHarness('pages/members/members.js', {
    getKitchenInvite: async () => { throw new Error('offline') }, friendly: err => err.message,
  })
  page.data.isOwner = true
  await page.loadInvite()
  assert.match(page.data.inviteError, /offline/)
  assert.equal(page.data.inviteCode, '')
})

test('换码成功后旧加载响应不恢复旧邀请码', async () => {
  let resolve
  const { page, calls } = pageHarness('pages/members/members.js', {
    getKitchenInvite: () => new Promise(done => { resolve = done }),
    resetKitchenInvite: async () => ({ invite_code: 'new' }), friendly: err => err.message,
  })
  page.data.isOwner = true
  page.data.inviteCode = 'old'
  const oldRead = page.loadInvite()
  page.resetInvite()
  await calls.find(call => call[0] === 'modal')[1].success({ confirm: true })
  await new Promise(done => setImmediate(done))
  resolve({ invite_code: 'old' })
  await oldRead
  assert.equal(page.data.inviteCode, 'new')
})

test('换码期间不能生成旧邀请卡片', () => {
  const { page } = pageHarness('pages/members/members.js', {})
  page.data.isOwner = true
  page.data.inviteCode = 'old'
  page.data.inviteBusy = true
  assert.doesNotMatch(page.onShareAppMessage().path, /join\/join/)
})
